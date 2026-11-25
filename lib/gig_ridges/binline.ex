defmodule GigRidges.Binline do
  @moduledoc """
  The binned ridges' stat: each group's values counted in bins along `x`, as ggplot2's
  `stat_bin()` counts them, every group of a panel in the panel's bins, and each bin written as
  the two ends of a step, so the ridge drawn through them is the histogram's outline.

  The bins are the `breaks:` given, or bins `binwidth:` wide, or else `bins:` of them, 30 unless
  given, spanning the panel's `x`, each placed by `center:` or `boundary:`, as `stat_bin()` places
  them, closed on the right unless `closed: :left`. With `pad:`, as unless `pad: false`, an empty
  bin as wide as the first is added before them and one as wide as the last after. A value outside
  the bins is not counted, and a panel left with fewer than two breaks, as a scale's
  transformation leaves the breaks it cannot take, has no bins and draws nothing.

  Its rows are each bin's two ends, at its `xmin` and a hundred-thousandth of its `width` short of
  its `xmax`: `count`, the values in it; `density`, the count over the width and the group's
  values counted; `ncount` and `ndensity`, each over the group's greatest; and `height`, the
  density, which the density ridges' geom (`GigRidges.DensityRidgeline`) draws. Under
  `draw_baseline: false`, the empty bins before the group's first counted value and after its
  last have no `count`, `density` or `height` but the end beside the counted ones, so the ridge
  rises from where its values begin, not along the baseline. A group with nothing counted has no
  density or shares, and draws no ridge, its counts missing too under `draw_baseline: false`. A
  group's columns holding one value within it are carried.
  """

  use Giggly.Stat

  alias Giggly.DataFrame
  alias GigRidges.{Binning, Groups}

  defstruct binwidth: :none,
            bins: 30,
            center: :none,
            boundary: :none,
            breaks: :none,
            closed: :right,
            pad: true,
            draw_baseline: true

  @type t :: %__MODULE__{
          binwidth: :none | float(),
          bins: pos_integer(),
          center: :none | float(),
          boundary: :none | float(),
          breaks: :none | [float()],
          closed: :right | :left,
          pad: boolean(),
          draw_baseline: boolean()
        }

  # A step's second end, a hundred-thousandth of the bin's width short of its upper edge.
  @short 1.0e-5

  @impl Giggly.Stat
  def options do
    [
      binwidth: [
        type: {:custom, Binning, :validate_binwidth, []},
        default: :none,
        doc: "The bins' width, a number above 0, over `bins:`."
      ],
      bins: [
        type: :pos_integer,
        default: 30,
        doc: "How many bins span the panel's `x` where no `binwidth:` or `breaks:` is given."
      ],
      center: [
        type: {:custom, Binning, :validate_place, []},
        default: :none,
        doc: "A place one bin is centred on, beside no `boundary:`."
      ],
      boundary: [
        type: {:custom, Binning, :validate_place, []},
        default: :none,
        doc: "A place two bins meet at, beside no `center:`."
      ],
      breaks: [
        type: {:custom, Binning, :validate_breaks, []},
        default: :none,
        doc: "The places the bins meet at, two or more, over `binwidth:` and `bins:`."
      ],
      closed: [
        type: {:in, [:right, :left]},
        default: :right,
        doc: "Which end of each bin holds a value on it: `:right` or `:left`."
      ],
      pad: [
        type: :boolean,
        default: true,
        doc: "Whether an empty bin is added at either end."
      ],
      draw_baseline: [
        type: :boolean,
        default: true,
        doc:
          "Whether the ridge runs along its baseline past the group's values (`true`), or rises " <>
            "from where they begin (`false`)."
      ]
    ]
  end

  # A bin's middle and its edge each place every bin, so a layer takes one of them.
  @impl Giggly.Stat
  def option_conflicts(options) do
    if Keyword.get(options, :center, :none) != :none and
         Keyword.get(options, :boundary, :none) != :none,
       do: ["takes center: or boundary:, not both, since each places every bin"],
       else: []
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
  def computed_variables(_stat),
    do: [:x, :count, :density, :ncount, :ndensity, :height, :xmin, :xmax, :width]

  @impl Giggly.Stat
  def numeric_aesthetics(_stat), do: [x: "each group's values are counted in bins along it"]

  @computed [:x, :xmin, :xmax, :width, :count, :density, :ncount, :ndensity, :height]

  @impl Giggly.Stat
  def compute_layer(stat, frame, axes) do
    {groups, carried} = Groups.gather(frame)

    groups
    |> DataFrame.split(:panel)
    |> Enum.sort()
    |> Enum.flat_map(fn {panel, rows} ->
      stat |> Binning.breaks(Map.fetch!(axes, panel).x) |> panel_rows(rows, carried, stat)
    end)
    |> Groups.joined(groups, carried, @computed)
  end

  # A panel's groups' rows binned by `breaks`; none where fewer than two breaks are left, as given
  # breaks a scale's transformation drops leave, where ggridges draws nothing.
  defp panel_rows([_low, _high | _rest] = breaks, rows, carried, stat) do
    fuzzy = Binning.fuzzy(breaks, stat.closed)

    rows
    |> DataFrame.pull(:xs)
    |> Enum.with_index()
    |> Enum.map(fn {values, index} ->
      {edges, counts} = padded(breaks, counts(values, fuzzy, stat.closed), stat.pad)
      steps = steps(edges, counts, stat.draw_baseline)
      Groups.rows(rows, index, length(steps.x), carried, Keyword.new(steps))
    end)
  end

  defp panel_rows(_too_few, _rows, _carried, _stat), do: []

  # The bins' edges and counts, with an empty bin as wide as the first before them and one as
  # wide as the last after where padded, counted after the values are, so they hold none.
  defp padded(edges, counts, false), do: {edges, counts}

  defp padded([first, second | _rest] = edges, counts, true) do
    [last, before_last] = edges |> Enum.reverse() |> Enum.take(2)
    {[first - (second - first) | edges] ++ [last + (last - before_last)], [0 | counts] ++ [0]}
  end

  # How many of `values` fall in each bin between the fuzzy edges, closed on the right, the first
  # holding its lower edge too, or on the left, the last holding its upper; a value outside every
  # bin is not counted.
  defp counts(values, fuzzy, closed) do
    bins = Enum.chunk_every(fuzzy, 2, 1, :discard)
    last = length(bins) - 1

    bins
    |> Enum.with_index()
    |> Enum.map(fn {[low, high], index} ->
      Enum.count(values, &holds?(&1, low, high, closed, index, last))
    end)
  end

  defp holds?(value, low, high, :right, 0, _last), do: value >= low and value <= high
  defp holds?(value, low, high, :right, _index, _last), do: value > low and value <= high
  defp holds?(value, low, high, :left, last, last), do: value >= low and value <= high
  defp holds?(value, low, high, :left, _index, _last), do: value >= low and value < high

  # Each bin written as a step's two ends: its lower edge and just short of its upper, with its
  # edges, width, count, density over the counted values, and the shares of the group's greatest,
  # missing where nothing is counted, so the group draws no ridge, as ggridges draws none;
  # without a baseline, the empty bins outside the counted ones losing their count, density and
  # height but at the end beside them.
  defp steps(edges, counts, draw_baseline) do
    total = Enum.sum(counts)
    bins = edges |> Enum.chunk_every(2, 1, :discard) |> Enum.zip(counts)

    densities =
      Enum.map(bins, fn {[low, high], count} -> share(count, (high - low) * total) end)

    peak_count = Enum.max(counts)
    peak_density = Enum.max(densities)

    rows =
      bins
      |> Enum.zip(densities)
      |> Enum.flat_map(fn {{[low, high], count}, density} ->
        width = high - low

        bin = %{
          xmin: low,
          xmax: high,
          width: width,
          count: count,
          density: density,
          ncount: share(count, peak_count),
          ndensity: share(density, peak_density),
          height: density
        }

        [Map.put(bin, :x, low), Map.put(bin, :x, high - @short * width)]
      end)
      |> unbased(draw_baseline)

    Map.new(@computed, fn name -> {name, Enum.map(rows, &Map.fetch!(&1, name))} end)
  end

  # Without a baseline, the ends before the first counted bin's, but the one beside it, and after
  # the last's, but the one beside it, missing their count, density and height; every end of a
  # group with nothing counted.
  defp unbased(rows, true), do: rows

  defp unbased(rows, false) do
    case rows |> Enum.with_index() |> Enum.filter(fn {row, _index} -> row.count > 0 end) do
      [] ->
        Enum.map(rows, &%{&1 | count: nil, density: nil, height: nil})

      [{_row, first} | _rest] = counted ->
        {_row, last} = List.last(counted)
        rows |> Enum.with_index() |> Enum.map(&outside(&1, first, last))
    end
  end

  defp outside({row, index}, first, last) when index < first - 1 or index > last + 1,
    do: %{row | count: nil, density: nil, height: nil}

  defp outside({row, _index}, _first, _last), do: row

  # A part of a whole, missing where the whole is 0 or missing, as R's 0 / 0 is not a number.
  defp share(part, whole) when is_number(part) and is_number(whole) and whole != 0,
    do: part / whole

  defp share(_part, _whole), do: nil
end
