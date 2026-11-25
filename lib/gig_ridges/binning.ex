defmodule GigRidges.Binning do
  @moduledoc false

  # An axis cut into bins, as ggplot2's `stat_bin()` cuts one: the breaks a panel's axis is cut at
  # (`breaks/2`), and the same breaks moved outward a hundred-millionth of their median width
  # (`fuzzy/2`), which a value is cut against, so a value on a break that rounding moved still
  # falls where R puts it.
  #
  # The breaks come from the axis as a stat is handed it: the breaks given, put through the
  # axis's transformation and sorted; or bins `binwidth` wide, one edge on `boundary` or one
  # middle on `center`, else on half a width, from the bin holding the axis's low limit to the
  # one holding its high; or else `bins` of them spanning the limits, the outermost two centred
  # on them, or edged on them when the limits fall on a boundary. An axis of zero width takes bins
  # 0.1 wide. Bins that would number more than a million are refused, as R refuses them.
  #
  # Copied from Giggly's own binning (MIT), its arithmetic over finite numbers alone, as a
  # panel's limits are, so the plugin depends on none of Giggly's internal statistics.

  @typedoc "How an axis is binned: the breaks given, a bin width or a number of bins."
  @type spec :: %{
          required(:breaks) => :none | [number()],
          required(:binwidth) => :none | number(),
          required(:bins) => pos_integer(),
          required(:center) => :none | number(),
          required(:boundary) => :none | number(),
          optional(atom()) => term()
        }

  # A panel's breaks along an axis, as ggplot2's `stat_bin()` chooses them from its scale.
  @doc false
  @spec breaks(spec(), Giggly.Stat.axis()) :: [number()]
  def breaks(%{breaks: given}, %{transform: transform}) when is_list(given) do
    given
    |> transform.()
    |> Enum.filter(&is_number/1)
    |> Enum.sort()
  end

  def breaks(%{binwidth: width} = spec, %{limits: limits}) when is_number(width),
    do: width_breaks(limits, width, spec.center, spec.boundary)

  def breaks(%{bins: bins} = spec, %{limits: limits}),
    do: bins_breaks(limits, bins, spec.center, spec.boundary)

  # The breaks, two or more, moved outward a hundred-millionth of their median width: the first
  # down and every other up when bins are closed on the right, the last up and every other down
  # when closed on the left.
  @doc false
  @spec fuzzy([number()], :right | :left) :: [number()]
  def fuzzy(breaks, closed) do
    fuzz = fuzz(breaks)
    last = length(breaks) - 1

    breaks
    |> Enum.with_index()
    |> Enum.map(fn {break, index} -> break + fuzz_sign(index, last, closed) * fuzz end)
  end

  defp bins_breaks({low, high} = limits, _bins, center, boundary) when low == high,
    do: width_breaks(limits, 0.1, center, boundary)

  defp bins_breaks({low, high} = limits, 1, _center, _boundary),
    do: width_breaks(limits, high - low, :none, low)

  defp bins_breaks({low, high} = limits, bins, center, boundary) do
    width = (high - low) / (bins - 1)
    boundary = if center == :none and boundary == :none, do: low - width / 2, else: boundary

    width =
      if boundary != :none and
           (on_boundary?(low, width, boundary) or on_boundary?(high, width, boundary)),
         do: (high - low) / bins,
         else: width

    width_breaks(limits, width, center, boundary)
  end

  defp on_boundary?(limit, width, boundary), do: modulo(limit, width) == modulo(boundary, width)

  # Breaks `width` apart over the limits: an edge on `boundary`, or a middle on `center`, or else
  # an edge half a width from 0, the first break the edge below the low limit and the last past
  # the high one, by R's `seq()`; at least two.
  defp width_breaks({low, high}, width, center, boundary) do
    boundary =
      cond do
        boundary != :none -> boundary
        center != :none -> center - width / 2
        true -> width / 2
      end

    origin = boundary + Float.floor((low - boundary) / width) * width
    last = high + (1 - 1.0e-8) * width

    if (last - origin) / width > 1.0e6 do
      raise ArgumentError,
            "a bin width of #{inspect(width)} cuts the axis into more than 1,000,000 bins; " <>
              "give a wider binwidth:"
    end

    case sequence(origin, last, width) do
      [only] -> [only, only + width]
      breaks -> breaks
    end
  end

  # R's `seq(from, to, by)`: from, then each step on while within `to`, allowing R's 1e-10 of a
  # step for rounding.
  defp sequence(from, to, by) do
    steps = trunc(Float.floor((to - from) / by + 1.0e-10))
    for step <- 0..steps, do: from + step * by
  end

  # R's `%%` on doubles.
  defp modulo(value, by), do: value - Float.floor(value / by) * by

  defp fuzz_sign(0, _last, :right), do: -1
  defp fuzz_sign(_index, _last, :right), do: 1
  defp fuzz_sign(last, last, :left), do: 1
  defp fuzz_sign(_index, _last, :left), do: -1

  # A hundred-millionth of the breaks' median gap; the breaks are two or more.
  defp fuzz(breaks) do
    gaps =
      breaks
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [low, high] -> high - low end)

    1.0e-8 * median(gaps)
  end

  # R's `median()`: the middle value, or the mean of the middle two.
  defp median(values) do
    sorted = Enum.sort(values)
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1,
      do: Enum.at(sorted, middle),
      else: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
  end

  # NimbleOptions' check of a `binwidth:`: a number above 0, kept as a float.
  @doc false
  @spec validate_binwidth(term()) :: {:ok, :none | float()} | {:error, String.t()}
  def validate_binwidth(:none), do: {:ok, :none}
  def validate_binwidth(width) when is_number(width) and width > 0, do: {:ok, width / 1}

  def validate_binwidth(width),
    do: {:error, "expected a bin width, a number above 0, got: #{inspect(width)}"}

  # NimbleOptions' check of a `breaks:`: two or more numbers, no two the same, each a float.
  @doc false
  @spec validate_breaks(term()) :: {:ok, :none | [float()]} | {:error, String.t()}
  def validate_breaks(:none), do: {:ok, :none}

  def validate_breaks([_first, _second | _rest] = breaks) do
    floats = for break <- breaks, is_number(break), do: break / 1

    if length(floats) == length(breaks) and length(Enum.uniq(floats)) == length(floats),
      do: {:ok, floats},
      else: {:error, breaks_error(breaks)}
  end

  def validate_breaks(breaks), do: {:error, breaks_error(breaks)}

  defp breaks_error(breaks),
    do: "expected two or more distinct numbers where the bins meet, got: #{inspect(breaks)}"

  # NimbleOptions' check of a `center:` or `boundary:`: a number, kept as a float.
  @doc false
  @spec validate_place(term()) :: {:ok, :none | float()} | {:error, String.t()}
  def validate_place(:none), do: {:ok, :none}
  def validate_place(place) when is_number(place), do: {:ok, place / 1}
  def validate_place(other), do: {:error, "expected a number, got: #{inspect(other)}"}
end
