defmodule GigRidges.DensityRidges do
  @moduledoc """
  The density ridges stat: each group's density along `x`, estimated with one bandwidth shared by
  every group, so ridges of one plot are smoothed alike.

  Per panel, the bandwidth is the one given, or else the joint bandwidth: the mean, over the
  panel's groups of two values or more, of each group's by Silverman's rule, R's `bw.nrd0()`, 0.9
  times the lesser of the standard deviation and the interquartile range over 1.34, times the
  number of values to the power of minus one fifth. A group of fewer than three values has no
  density and is left out, though its values still count towards the joint bandwidth and the
  places. Each group's density is the normal kernel's, estimated as R's `density()` estimates one
  (`GigRidges.KernelDensity`), so its values are R's to within round-off, and read at `n:` places,
  512 unless given, evenly from `from:` to `to:`, each end, where not given, three bandwidths
  beyond the panel's rows; a panel whose places would run backwards, `from:` alone above where
  `to:` falls or `to:` alone below `from:`, has none. A value further than four bandwidths
  outside the places adds nothing to the density, though it counts among the group's values, as
  in R's `density()`.

  A `weight` mapped weighs each row's share of its group's density, its weight over the group's
  total, as R's `density(weights = )` takes weights summing to 1; the bandwidth is worked out from
  the values unweighted. Where a group estimated has a weight missing or below 0, or weights
  totalling 0, R's `density()` fails, and the panel has no density, as ggridges draws none of it.

  Its rows are each group's places: `x`, the group's `y`, `density`, `ndensity`, the density over
  the group's greatest, and `height`, the density scaled so the panel's greatest reaches the
  spacing between baselines, or the layer's greatest under `panel_scaling: false`, which the
  ridgeline draws above each baseline. A group's columns holding one value within it are carried,
  a `weight` among them where every group's is one value, as ggridges keeps it.
  """

  use Giggly.Stat

  alias Giggly.DataFrame
  alias Giggly.Stat.Carry
  alias GigRidges.KernelDensity

  defstruct bandwidth: :nrd0, panel_scaling: true, from: :none, to: :none, n: 512

  @type t :: %__MODULE__{
          bandwidth: :nrd0 | float(),
          panel_scaling: boolean(),
          from: :none | float(),
          to: :none | float(),
          n: pos_integer()
        }

  @impl Giggly.Stat
  def options do
    [
      bandwidth: [
        type: {:custom, __MODULE__, :validate_bandwidth, []},
        default: :nrd0,
        doc:
          "The bandwidth every group's density is estimated with, a number above 0, or `:nrd0`, " <>
            "the mean of Silverman's rule over each of the panel's groups."
      ],
      panel_scaling: [
        type: :boolean,
        default: true,
        doc:
          "Whether each panel's ridges are scaled so its greatest density reaches the next " <>
            "baseline (`true`), or the layer's ridges together, so a panel of lower densities " <>
            "draws lower ridges (`false`)."
      ],
      from: [
        type: {:custom, __MODULE__, :validate_end, []},
        default: :none,
        doc:
          "The least place each group's density is read at, a number; three bandwidths below " <>
            "the panel's least value where none is given."
      ],
      to: [
        type: {:custom, __MODULE__, :validate_end, []},
        default: :none,
        doc:
          "The greatest place each group's density is read at, a number above `from:`; three " <>
            "bandwidths above the panel's greatest value where none is given."
      ],
      n: [
        type: {:custom, __MODULE__, :validate_count, []},
        default: 512,
        doc:
          "How many places each group's density is read at, evenly spaced, a whole number of " <>
            "2 or more."
      ]
    ]
  end

  # `from:` and `to:` given together, the least place above or at the greatest.
  @impl Giggly.Stat
  def option_conflicts(options) do
    case {Keyword.get(options, :from, :none), Keyword.get(options, :to, :none)} do
      {from, to} when is_float(from) and is_float(to) and from >= to ->
        ["takes a from: below its to:, got from: #{from} and to: #{to}"]

      _ends ->
        []
    end
  end

  @impl Giggly.Stat
  def accepted_aesthetics(_stat), do: [:x, :y, :group, :weight]

  @impl Giggly.Stat
  def required_aesthetics(_stat), do: [:x, :y]

  @impl Giggly.Stat
  def written_aesthetics(_stat), do: [:x, :height]

  @impl Giggly.Stat
  def default_mapping(_stat), do: %{height: :height}

  @impl Giggly.Stat
  def computed_variables(_stat), do: [:density, :ndensity, :height]

  @impl Giggly.Stat
  def numeric_aesthetics(_stat),
    do: [
      x: "each group's density is estimated along it",
      weight: "each group's density spreads each row's weight"
    ]

  @doc false
  @spec validate_bandwidth(term()) :: {:ok, :nrd0 | float()} | {:error, String.t()}
  def validate_bandwidth(:nrd0), do: {:ok, :nrd0}
  def validate_bandwidth(width) when is_number(width) and width > 0, do: {:ok, width / 1}

  def validate_bandwidth(other),
    do: {:error, "expected a number above 0 or :nrd0, got: #{inspect(other)}"}

  @doc false
  @spec validate_end(term()) :: {:ok, :none | float()} | {:error, String.t()}
  def validate_end(:none), do: {:ok, :none}
  def validate_end(place) when is_number(place), do: {:ok, place / 1}
  def validate_end(other), do: {:error, "expected a number, got: #{inspect(other)}"}

  @doc false
  @spec validate_count(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def validate_count(count) when is_integer(count) and count >= 2, do: {:ok, count}

  def validate_count(other),
    do: {:error, "expected a whole number of 2 or more, got: #{inspect(other)}"}

  @impl Giggly.Stat
  def compute_layer(stat, frame, _axes) do
    finite = DataFrame.filter(frame, {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})
    carried = Carry.constant_columns(finite, DataFrame.names(finite) -- [:x])
    weighed = if :weight in DataFrame.names(finite), do: [ws: {:list, [:weight]}], else: []

    groups =
      DataFrame.summarise(
        finite,
        [:panel, :group],
        [
          {:xs, {:list, [:x]}}
          | weighed ++ for(name <- carried -- [:panel, :group], do: {name, {:first, [name]}})
        ]
      )

    panels =
      groups
      |> DataFrame.split(:panel)
      |> Enum.sort()
      |> Enum.map(fn {_panel, rows} -> panel_estimates(stat, rows) end)

    spacing = spacing(DataFrame.pull(groups, :y))
    layer_greatest = panels |> Enum.concat() |> greatest()

    panels
    |> Enum.flat_map(fn estimates ->
      greatest = if stat.panel_scaling, do: greatest(estimates), else: layer_greatest

      Enum.map(estimates, fn {rows, index, places, densities} ->
        peak = Enum.max(densities)

        group_frame(rows, List.duplicate(index, length(places)), carried,
          x: places,
          density: densities,
          ndensity: Enum.map(densities, fn density -> share(density, peak) end),
          height: Enum.map(densities, fn density -> scaled(density, greatest, spacing) end)
        )
      end)
    end)
    |> joined(groups, carried)
  end

  # The greatest density among `estimates`, 0 where there are none.
  defp greatest(estimates) do
    estimates
    |> Enum.flat_map(fn {_rows, _index, _places, densities} -> densities end)
    |> Enum.max(fn -> 0.0 end)
  end

  # Each group's density at the panel's places, its bandwidth shared by the panel's groups: the
  # panel's rows, the group's index among them, the places and the densities there; a group of
  # fewer than three values has none, so a panel of no larger group has no estimates. A panel
  # where a group estimated has a weight missing or below 0, or weights totalling 0, has none
  # either, as R's `density()` fails there and ggridges draws none of the panel.
  defp panel_estimates(stat, rows) do
    samples = DataFrame.pull(rows, :xs)

    weights =
      if :ws in DataFrame.names(rows),
        do: DataFrame.pull(rows, :ws),
        else: List.duplicate(:unweighted, length(samples))

    estimated =
      for {{values, weighed}, index} <- samples |> Enum.zip(weights) |> Enum.with_index(),
          length(values) >= 3,
          do: {values, shares(values, weighed), index}

    if Enum.any?(estimated, fn {_values, shares, _index} -> shares == :failed end),
      do: [],
      else: estimates(stat, samples, estimated, rows)
  end

  # Each of a group's values' share of its density: 1 over its values unweighted, else its weight
  # over the group's total; `:failed` where a weight is missing or below 0, or they total 0.
  defp shares(values, :unweighted), do: List.duplicate(1 / length(values), length(values))

  defp shares(_values, weights) do
    total = if Enum.all?(weights, &(is_number(&1) and &1 >= 0)), do: Enum.sum(weights), else: 0
    if total > 0, do: Enum.map(weights, &(&1 / total)), else: :failed
  end

  defp estimates(_stat, _samples, [], _rows), do: []

  defp estimates(stat, samples, estimated, rows) do
    pooled = Enum.concat(samples)
    width = bandwidth(stat.bandwidth, samples)
    low = place_or(stat.from, Enum.min(pooled) - 3 * width)
    high = place_or(stat.to, Enum.max(pooled) + 3 * width)
    read(low, high, estimated, width, stat.n, rows)
  end

  # Each estimated group's density at `count` places from `low` to `high`; none where the places
  # would run backwards, one end given beyond the other's default, as ggridges draws none there.
  defp read(low, high, _estimated, _width, _count, _rows) when low >= high, do: []

  defp read(low, high, estimated, width, count, rows) do
    places = KernelDensity.places(low, high, count)

    Enum.map(estimated, fn {values, shares, index} ->
      {rows, index, places, KernelDensity.estimate(values, shares, width, {low, high}, count)}
    end)
  end

  # The end of the places given, else the one three bandwidths beyond the panel's values.
  defp place_or(:none, beyond), do: beyond
  defp place_or(given, _beyond), do: given

  # A group's rows: its carried columns repeated once per place, beside the columns computed.
  defp group_frame(rows, indices, carried, computed) do
    rows
    |> DataFrame.slice(indices)
    |> DataFrame.select(Enum.map(carried, fn name -> {name, name} end))
    |> then(fn frame ->
      Enum.reduce(computed, frame, fn {name, values}, built ->
        DataFrame.put(built, name, values)
      end)
    end)
  end

  # The groups' rows end to end; a layer of no groups has none, in the columns it would have.
  defp joined([], groups, carried),
    do: group_frame(groups, [], carried, x: [], density: [], ndensity: [], height: [])

  defp joined(frames, _groups, _carried), do: DataFrame.concat_rows(frames)

  defp share(density, peak) when peak > 0, do: density / peak
  defp share(_density, _peak), do: 0.0

  defp bandwidth(width, _samples) when is_float(width), do: width

  # The joint bandwidth: the mean of Silverman's rule over the groups of two values or more.
  defp bandwidth(:nrd0, samples) do
    widths = for values <- samples, length(values) >= 2, do: nrd0(values)
    Enum.sum(widths) / length(widths)
  end

  # Silverman's rule, R's `bw.nrd0()`, falling back as it does where the spread is 0.
  defp nrd0(values) do
    count = length(values)
    mean = Enum.sum(values) / count

    deviation =
      :math.sqrt(
        Enum.sum(Enum.map(values, fn value -> (value - mean) ** 2 end)) / max(count - 1, 1)
      )

    spread = (quantile(values, 0.75) - quantile(values, 0.25)) / 1.34

    0.9 * spread_of(min(deviation, spread), deviation, abs(hd(values))) * count ** -0.2
  end

  # The spread Silverman's rule scales, the lesser of the two where it is above 0, else the
  # standard deviation, else the first value's size, else 1, as R's `bw.nrd0()` documents.
  defp spread_of(lesser, _deviation, _first) when lesser > 0, do: lesser
  defp spread_of(_lesser, deviation, _first) when deviation > 0, do: deviation
  defp spread_of(_lesser, _deviation, first) when first > 0, do: first
  defp spread_of(_lesser, _deviation, _first), do: 1.0

  # R's type 7 quantile.
  defp quantile(values, probability) do
    sorted = Enum.sort(values)
    position = (length(sorted) - 1) * probability
    low = floor(position)
    high = ceil(position)
    Enum.at(sorted, low) + (Enum.at(sorted, high) - Enum.at(sorted, low)) * (position - low)
  end

  # The least gap between the layer's distinct baselines, 1 where there is one.
  defp spacing(baselines) do
    baselines
    |> Enum.filter(&is_number/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [lower, upper] -> upper - lower end)
    |> Enum.min(fn -> 1.0 end)
  end

  defp scaled(_density, greatest, _spacing) when greatest == 0, do: 0.0
  defp scaled(density, greatest, spacing), do: density / greatest * spacing
end
