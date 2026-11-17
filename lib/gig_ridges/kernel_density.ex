defmodule GigRidges.KernelDensity do
  @moduledoc false

  # A Gaussian kernel density estimate, as R's `density()` computes one: each value's share of
  # the rows spread linearly over the two nearest points of a grid of at least 512 points, a power
  # of two past that, reaching four bandwidths beyond the places either end; the grid padded with as
  # many zeros and convolved with the kernel through a Fourier transform, raised to 0 where
  # round-off leaves it below; and the curve read at the places by linear interpolation. Its
  # values are R's to within round-off. Copied from Giggly's own estimate (MIT), the Gaussian
  # kernel and unweighted rows alone, so the plugin depends on none of Giggly's internal
  # statistics.

  @least_points 512
  @reach 4
  @normal_height 0.398_942_280_401_432_7

  @doc false
  @spec estimate([number()], float(), {number(), number()}, pos_integer()) :: [float()]
  def estimate(values, bandwidth, {from, to}, count) do
    grid = grid_points(count)
    low = from - @reach * bandwidth
    high = to + @reach * bandwidth
    step = (high - low) / (grid - 1)

    signal = spread(values, low, step, 2 * grid)
    kernel = Enum.map(distances(grid, low, high), fn distance -> kernel(distance, bandwidth) end)

    estimates =
      signal
      |> circular_correlation(kernel)
      |> Enum.take(grid)
      |> Enum.map(fn value -> max(value, 0.0) end)

    low
    |> places(high, grid)
    |> Enum.zip(estimates)
    |> interpolate(places(from, to, count))
  end

  # How many points the grid takes for `count` places: at least 512, and past that the least
  # power of two holding them.
  defp grid_points(count) when count <= @least_points, do: @least_points

  defp grid_points(count) do
    exponent =
      count
      |> :math.log2()
      |> Float.ceil()
      |> trunc()

    2 ** exponent
  end

  # Each value's share of the rows split between the grid points either side of it, by how near
  # it is to each, summed in the values' order, the grid padded with zeros to `slots` points.
  defp spread(values, low, step, slots) do
    share = 1 / length(values)

    totals =
      Enum.reduce(values, %{}, fn value, totals ->
        place = (value - low) / step
        point = trunc(Float.floor(place / 1))
        fraction = place - point

        totals
        |> Map.update(point, share * (1 - fraction), fn total ->
          total + share * (1 - fraction)
        end)
        |> Map.update(point + 1, share * fraction, fn total -> total + share * fraction end)
      end)

    Enum.map(0..(slots - 1), fn slot -> Map.get(totals, slot, 0.0) end)
  end

  # The distance from the padded grid's first point to each, wrapping round: 0 up to just past
  # the grid's span over its first half and back down over its second.
  defp distances(grid, low, high) do
    slots = 2 * grid
    span = (slots - 1) / (grid - 1) * (high - low)

    upward =
      0.0
      |> places(span, slots)
      |> List.to_tuple()

    Enum.map(0..(slots - 1), fn index ->
      if index <= grid, do: elem(upward, index), else: elem(upward, slots - index)
    end)
  end

  # The normal kernel's height at `distance` from its middle, its standard deviation `bandwidth`.
  defp kernel(distance, bandwidth) do
    standardised = distance / bandwidth
    @normal_height * :math.exp(-0.5 * standardised * standardised) / bandwidth
  end

  # The circular cross-correlation of `signal` with `kernel`, through Nx's Fourier transforms on
  # its binary backend in 64-bit floats.
  defp circular_correlation(signal, kernel) do
    kernel_spectrum =
      kernel
      |> tensor()
      |> Nx.fft(eps: 0)
      |> Nx.conjugate()

    signal
    |> tensor()
    |> Nx.fft(eps: 0)
    |> Nx.multiply(kernel_spectrum)
    |> Nx.ifft(eps: 0)
    |> Nx.real()
    |> Nx.to_flat_list()
  end

  defp tensor(values), do: Nx.tensor(values, type: :f64, backend: Nx.BinaryBackend)

  # `count` places evenly spaced from `low` to `high`, both ends exactly.
  @doc false
  @spec places(number(), number(), pos_integer()) :: [number()]
  def places(low, _high, 1), do: [low]
  def places(low, high, 2), do: [low, high]

  def places(low, high, count) do
    step = (high - low) / (count - 1)
    inner = Enum.map(1..(count - 2), fn index -> low + index * step end)
    Enum.concat([[low], inner, [high]])
  end

  # The curve through `knots`, each `{x, y}` ascending, read at each of `places`, ascending, by
  # linear interpolation.
  defp interpolate(knots, places) do
    spans = Enum.chunk_every(knots, 2, 1, :discard)

    {values, _spans} =
      Enum.map_reduce(places, spans, fn place, spans ->
        ahead = Enum.drop_while(spans, fn [_low, {high_x, _high_y}] -> place > high_x end)
        {read(ahead, place), ahead}
      end)

    values
  end

  defp read([[{low_x, low_y}, _high] | _rest], place) when place == low_x, do: low_y
  defp read([[_low, {high_x, high_y}] | _rest], place) when place == high_x, do: high_y

  defp read([[{low_x, low_y}, {high_x, high_y}] | _rest], place) when place > low_x,
    do: low_y + (high_y - low_y) * ((place - low_x) / (high_x - low_x))

  defp read(_spans, _place), do: 0.0
end
