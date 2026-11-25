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

  Under `quantile_lines:`, each group has a row for each of its quantiles, `quantile_fun:` of its
  values at the probabilities `quantiles:` gives, a count of equal parts, 4 unless given, or the
  probabilities themselves; R's type 7 quantiles where no function is given. Each line's row is at
  its place, its `density` and `ecdf` read from the ridge's by linear interpolation, its `quantile`
  its number and its `datatype` `"vline"`, which every ridgeline geom draws as a line up the ridge.
  Each place of the ridge has then its `ecdf`, the density's left sum to it times the step between
  places, unnormalised, as ggridges sums it, and its `quantile`, the band between the lines it
  falls in, a category, as ggridges' is a factor.

  Its rows are each group's places: `x`, the group's `y`, `density`, `ndensity`, the density over
  the group's greatest, and `height`, the density, which the density ridges' geom
  (`GigRidges.DensityRidgeline`) scales to the spacing between baselines as it draws, and the
  plain ridgeline draws as it is; and `datatype`, `"ridgeline"`. A group's columns holding one
  value within it are carried,
  a `weight` among them where every group's is one value, as ggridges keeps it.
  """

  use Giggly.Stat

  alias Giggly.DataFrame
  alias GigRidges.{Groups, KernelDensity}

  defstruct bandwidth: :nrd0,
            from: :none,
            to: :none,
            n: 512,
            quantile_lines: false,
            quantiles: 4,
            quantile_fun: &__MODULE__.type7_quantiles/2

  @type t :: %__MODULE__{
          bandwidth: :nrd0 | float(),
          from: :none | float(),
          to: :none | float(),
          n: pos_integer(),
          quantile_lines: boolean(),
          quantiles: pos_integer() | [float()],
          quantile_fun: (list(), [float()] -> number() | [number()])
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
      ],
      quantile_lines: [
        type: :boolean,
        default: false,
        doc:
          "Whether a line is drawn up each ridge at each of its group's quantiles, from its " <>
            "baseline to the ridge, each a row of the layer whose `datatype` is `\"vline\"`."
      ],
      quantiles: [
        type: {:custom, __MODULE__, :validate_quantiles, []},
        default: 4,
        doc:
          "How many parts of equal share the quantile lines cut each group into, a whole number " <>
            "of 2 or more, or the probabilities they are drawn at, each from 0 to 1."
      ],
      quantile_fun: [
        type: {:fun, 2},
        default: &__MODULE__.type7_quantiles/2,
        doc:
          "The function placing the quantile lines, of a group's values and the probabilities, " <>
            "returning a place or a list of them; R's type 7 quantiles where none is given."
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
  def computed_variables(_stat), do: [:x, :density, :ndensity, :height, :ecdf, :quantile]

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

  @doc false
  @spec validate_quantiles(term()) :: {:ok, pos_integer() | [float()]} | {:error, String.t()}
  def validate_quantiles(count) when is_integer(count) and count >= 2, do: {:ok, count}

  def validate_quantiles([_first | _rest] = probabilities) do
    if Enum.all?(probabilities, &(is_number(&1) and &1 >= 0 and &1 <= 1)),
      do: {:ok, Enum.map(probabilities, &(&1 / 1))},
      else: {:error, quantiles_error(probabilities)}
  end

  def validate_quantiles(other), do: {:error, quantiles_error(other)}

  defp quantiles_error(other),
    do:
      "expected a whole number of 2 or more, or probabilities from 0 to 1, got: " <>
        inspect(other)

  # R's type 7 quantiles of `values` at each of `probabilities`, `quantile()`'s default.
  @doc false
  @spec type7_quantiles([number()], [float()]) :: [float()]
  def type7_quantiles(values, probabilities),
    do: Enum.map(probabilities, &quantile(values, &1))

  @impl Giggly.Stat
  def compute_layer(stat, frame, _axes) do
    {groups, carried} = Groups.gather(frame, ws: :weight)

    groups
    |> DataFrame.split(:panel)
    |> Enum.sort()
    |> Enum.flat_map(fn {_panel, rows} -> panel_estimates(stat, rows) end)
    |> Enum.flat_map(fn {rows, index, values, places, densities} ->
      peak = Enum.max(densities)

      ridge = [
        x: places,
        density: densities,
        ndensity: Enum.map(densities, fn density -> share(density, peak) end),
        height: densities,
        datatype: List.duplicate("ridgeline", length(places))
      ]

      stat
      |> quantiled(ridge, values, peak)
      |> Enum.map(fn computed ->
        Groups.rows(rows, index, length(computed[:x]), carried, computed)
      end)
    end)
    |> Groups.joined(groups, carried, computed_columns(stat))
    |> banded(stat)
  end

  defp computed_columns(%__MODULE__{quantile_lines: false}),
    do: [:x, :density, :ndensity, :height, :datatype]

  defp computed_columns(%__MODULE__{quantile_lines: true}),
    do: [:x, :density, :ndensity, :height, :datatype, :ecdf, :quantile]

  # A group's rows: its ridge's alone, or under `quantile_lines:` its ridge's with each place's
  # `ecdf`, the density's left sum to it times the step between places, and its `quantile`, the band
  # between the quantiles it falls in, and a row for each quantile, at its place, its density and
  # `ecdf` read from the ridge's by linear interpolation, its `quantile` its order and its
  # `datatype` `"vline"`, as ggridges writes them.
  defp quantiled(%__MODULE__{quantile_lines: false}, ridge, _values, _peak), do: [ridge]

  defp quantiled(stat, ridge, values, peak) do
    places = ridge[:x]
    densities = ridge[:density]
    ecdf = ecdf(places, densities)
    lines = stat.quantile_fun.(values, probabilities(stat.quantiles)) |> List.wrap()
    edges = Enum.sort(lines)
    bands = Enum.map(places, fn place -> 1 + Enum.count(edges, &(&1 < place)) end)
    line_densities = Enum.map(lines, &interpolated(places, densities, &1))

    [
      ridge ++ [ecdf: ecdf, quantile: bands],
      [
        x: Enum.map(lines, &(&1 / 1)),
        density: line_densities,
        ndensity: Enum.map(line_densities, &(&1 && share(&1, peak))),
        height: line_densities,
        datatype: List.duplicate("vline", length(lines)),
        ecdf: Enum.map(lines, &interpolated(places, ecdf, &1)),
        quantile: Enum.to_list(1..length(lines)//1)
      ]
    ]
  end

  # The probabilities the quantile lines are drawn at: a count's parts' edges, or those given.
  defp probabilities(count) when is_integer(count),
    do: for(part <- 1..(count - 1), do: part / count)

  defp probabilities(given), do: given

  # The density's left sum at each place, times the step between places: 0 at the first, and at
  # the last the share of the density the places span, as ggridges sums it, unnormalised.
  defp ecdf([first, second | _rest], densities) do
    step = second - first
    sums = densities |> Enum.drop(-1) |> Enum.scan(&(&1 + &2))
    Enum.map([0.0 | sums], &(&1 * step))
  end

  # The value at `place` along the curve through `places` and `values`, by R's `approx()`, missing
  # outside the places.
  defp interpolated(places, values, place) do
    places
    |> Enum.zip(values)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [{low, _low_value}, {high, _high_value}] = segment ->
      if place >= low and place <= high, do: along(segment, place)
    end)
  end

  defp along([{low, low_value}, {high, _high_value}], _place) when high == low, do: low_value

  defp along([{low, low_value}, {high, high_value}], place),
    do: low_value + (high_value - low_value) * (place - low) / (high - low)

  # The layer's `quantile` column a category under `quantile_lines:`, as ggridges' is a factor,
  # its levels every band's and line's number.
  defp banded(frame, %__MODULE__{quantile_lines: false}), do: frame

  defp banded(frame, _stat) do
    bands = DataFrame.pull(frame, :quantile)
    levels = Enum.to_list(1..Enum.max([1 | bands])//1)
    DataFrame.put(frame, :quantile, bands, {:category, levels: levels, ordered: false})
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
      densities = KernelDensity.estimate(values, shares, width, {low, high}, count)
      {rows, index, values, places, densities}
    end)
  end

  # The end of the places given, else the one three bandwidths beyond the panel's values.
  defp place_or(:none, beyond), do: beyond
  defp place_or(given, _beyond), do: given

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
end
