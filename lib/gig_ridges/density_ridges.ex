defmodule GigRidges.DensityRidges do
  @moduledoc """
  The density ridges stat: each group's density along `x`, estimated with one bandwidth shared by
  every group, so ridges of one plot are smoothed alike.

  Per panel, the bandwidth is the one given, or else worked out from the panel's rows together by
  Silverman's rule, R's `bw.nrd0()`: 0.9 times the lesser of the standard deviation and the
  interquartile range over 1.34, times the number of rows to the power of minus one fifth. Each
  group's density is the normal kernel's, read at 512 places evenly across the panel's rows,
  reaching three bandwidths beyond them, as R's `density()` reaches by default.

  Its rows are each group's places: `x`, the group's `y`, `density`, `ndensity`, the density over
  the group's greatest, and `height`, the density scaled so the layer's greatest reaches the spacing
  between baselines, which the ridgeline draws above each baseline. A group's columns holding one
  value within it are carried.
  """

  use Giggly.Stat.Facts

  defstruct bandwidth: :nrd0

  @type t :: %__MODULE__{bandwidth: :nrd0 | float()}

  @impl Giggly.Stat.Facts
  def options do
    [
      bandwidth: [
        type: {:custom, __MODULE__, :validate_bandwidth, []},
        default: :nrd0,
        doc:
          "The bandwidth every group's density is estimated with, a number above 0, or `:nrd0`, " <>
            "Silverman's rule over the panel's rows together."
      ]
    ]
  end

  @impl Giggly.Stat.Facts
  def accepted_aesthetics(_stat), do: [:x, :y, :group]

  @impl Giggly.Stat.Facts
  def required_aesthetics(_stat), do: [:x, :y]

  @impl Giggly.Stat.Facts
  def written_aesthetics(_stat), do: [:x, :height]

  @impl Giggly.Stat.Facts
  def default_mapping(_stat), do: %{height: :height}

  @impl Giggly.Stat.Facts
  def computed_variables(_stat), do: [:density, :ndensity, :height]

  @impl Giggly.Stat.Facts
  def numeric_aesthetics(_stat), do: [x: "each group's density is estimated along it"]

  @doc false
  @spec validate_bandwidth(term()) :: {:ok, :nrd0 | float()} | {:error, String.t()}
  def validate_bandwidth(:nrd0), do: {:ok, :nrd0}
  def validate_bandwidth(width) when is_number(width) and width > 0, do: {:ok, width / 1}

  def validate_bandwidth(other),
    do: {:error, "expected a number above 0 or :nrd0, got: #{inspect(other)}"}

  defimpl Giggly.Stat, for: __MODULE__ do
    alias Giggly.DataFrame
    alias Giggly.Stat.Carry

    @places 512

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

      densities =
        groups
        |> DataFrame.split(:panel)
        |> Enum.sort()
        |> Enum.flat_map(fn {panel, rows} -> panel_densities(stat, panel, rows) end)

      spacing = spacing(DataFrame.pull(groups, :y))
      greatest = densities |> Enum.map(fn row -> row.density end) |> Enum.max(fn -> 0.0 end)

      computed =
        DataFrame.new(
          panel: Enum.map(densities, fn row -> row.panel end),
          group: Enum.map(densities, fn row -> row.group end),
          x: Enum.map(densities, fn row -> row.x end),
          density: Enum.map(densities, fn row -> row.density end),
          ndensity: Enum.map(densities, fn row -> row.ndensity end),
          height: Enum.map(densities, fn row -> scaled(row.density, greatest, spacing) end)
        )

      carried_columns = DataFrame.select(groups, Enum.map(carried, fn name -> {name, name} end))
      DataFrame.join(computed, carried_columns, [:panel, :group])
    end

    # Each group's density at the panel's places, its bandwidth shared by the panel's groups.
    defp panel_densities(stat, panel, rows) do
      samples = DataFrame.pull(rows, :xs)
      pooled = Enum.concat(samples)
      width = bandwidth(stat.bandwidth, pooled)
      {low, high} = {Enum.min(pooled) - 3 * width, Enum.max(pooled) + 3 * width}
      places = for index <- 0..(@places - 1), do: low + (high - low) * index / (@places - 1)

      rows
      |> DataFrame.pull(:group)
      |> Enum.zip_with(samples, fn group, values ->
        estimates = Enum.map(places, fn place -> estimate(place, values, width) end)
        peak = Enum.max(estimates)

        Enum.zip_with(places, estimates, fn place, density ->
          %{
            panel: panel,
            group: group,
            x: place,
            density: density,
            ndensity: if(peak > 0, do: density / peak, else: 0.0)
          }
        end)
      end)
      |> Enum.concat()
    end

    # The normal kernel's density estimate at `place` from `values`, `width` wide.
    defp estimate(place, values, width) do
      total =
        Enum.reduce(values, 0.0, fn value, sum ->
          distance = (place - value) / width
          sum + :math.exp(-distance * distance / 2)
        end)

      total / (length(values) * width * :math.sqrt(2 * :math.pi()))
    end

    defp bandwidth(width, _values) when is_float(width), do: width

    # Silverman's rule, R's `bw.nrd0()`, falling back as it does where the spread is 0.
    defp bandwidth(:nrd0, values) do
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
end
