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
  and read at 512 places evenly across the panel's rows, reaching three bandwidths beyond them
  (`GigRidges.KernelDensity`), so its values are R's to within round-off.

  Its rows are each group's places: `x`, the group's `y`, `density`, `ndensity`, the density over
  the group's greatest, and `height`, the density scaled so the panel's greatest reaches the
  spacing between baselines, or the layer's greatest under `panel_scaling: false`, which the
  ridgeline draws above each baseline. A group's columns holding one value within it are carried.
  """

  use Giggly.Stat

  alias Giggly.DataFrame
  alias Giggly.Stat.Carry
  alias GigRidges.KernelDensity

  defstruct bandwidth: :nrd0, panel_scaling: true

  @type t :: %__MODULE__{bandwidth: :nrd0 | float(), panel_scaling: boolean()}

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
      ]
    ]
  end

  @impl Giggly.Stat
  def accepted_aesthetics(_stat), do: [:x, :y, :group]

  @impl Giggly.Stat
  def required_aesthetics(_stat), do: [:x, :y]

  @impl Giggly.Stat
  def written_aesthetics(_stat), do: [:x, :height]

  @impl Giggly.Stat
  def default_mapping(_stat), do: %{height: :height}

  @impl Giggly.Stat
  def computed_variables(_stat), do: [:density, :ndensity, :height]

  @impl Giggly.Stat
  def numeric_aesthetics(_stat), do: [x: "each group's density is estimated along it"]

  @doc false
  @spec validate_bandwidth(term()) :: {:ok, :nrd0 | float()} | {:error, String.t()}
  def validate_bandwidth(:nrd0), do: {:ok, :nrd0}
  def validate_bandwidth(width) when is_number(width) and width > 0, do: {:ok, width / 1}

  def validate_bandwidth(other),
    do: {:error, "expected a number above 0 or :nrd0, got: #{inspect(other)}"}

  @places 512

  @impl Giggly.Stat
  def compute_layer(stat, frame, _axes) do
    finite = DataFrame.filter(frame, {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})
    carried = Carry.constant_columns(finite, DataFrame.names(finite) -- [:x])

    groups =
      DataFrame.summarise(
        finite,
        [:panel, :group],
        [
          {:xs, {:list, [:x]}}
          | for(name <- carried -- [:panel, :group], do: {name, {:first, [name]}})
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
  # fewer than three values has none, so a panel of no larger group has no estimates.
  defp panel_estimates(stat, rows) do
    samples = DataFrame.pull(rows, :xs)

    estimated =
      for {values, index} <- Enum.with_index(samples), length(values) >= 3, do: {values, index}

    estimates(stat, samples, estimated, rows)
  end

  defp estimates(_stat, _samples, [], _rows), do: []

  defp estimates(stat, samples, estimated, rows) do
    pooled = Enum.concat(samples)
    width = bandwidth(stat.bandwidth, samples)
    span = {Enum.min(pooled) - 3 * width, Enum.max(pooled) + 3 * width}
    {low, high} = span
    places = KernelDensity.places(low, high, @places)

    Enum.map(estimated, fn {values, index} ->
      {rows, index, places, KernelDensity.estimate(values, width, span, @places)}
    end)
  end

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
