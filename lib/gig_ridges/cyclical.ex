defmodule GigRidges.Cyclical do
  @moduledoc false

  # The cyclical scales, as ggridges' `cyclical_scale()` builds them: Giggly's manual scale
  # (`Giggly.Plot.scale_discrete_manual/3`) handed the values repeated, in order, so each of the
  # scale's values, in the order its limits show them, takes the next of them, starting again at
  # the first once they run out. A manual scale given too few values refuses the plot, so they are
  # repeated to a thousand, or as many as the limits given; a list of breaks is handed on as a
  # function returning it, since a manual scale gives its values to a list of breaks in order, not
  # to the values the data holds, and a cyclical scale's breaks only choose its legend's keys. Its
  # legend is drawn only when `guide:` asks for one, as ggridges' is.

  alias Giggly.Plot

  @repeats 1000

  @doc false
  @spec scale(Plot.t(), atom() | [atom()], keyword(), String.t()) :: Plot.t()
  def scale(plot, aesthetics, options, function) do
    {values, options} = Keyword.pop(options, :values)
    check_values(values, function)

    manual =
      options
      |> Keyword.put_new(:guide, :none)
      |> breaks()
      |> Keyword.put(:values, repeated(values, Keyword.get(options, :limits)))

    Plot.scale_discrete_manual(plot, spelled(aesthetics), manual)
  end

  defp check_values([_value | _rest], _function), do: :ok

  defp check_values(other, function) do
    raise ArgumentError,
          "#{function} takes values:, a list of one value or more, repeated in order, got: " <>
            inspect(other)
  end

  # The values repeated in order, to a thousand or to as many as the limits given.
  defp repeated(values, limits) do
    count = if is_list(limits), do: max(@repeats, length(limits)), else: @repeats
    values |> Stream.cycle() |> Enum.take(count)
  end

  # A list of breaks, or of `{value, label}` pairs, as a function returning its values, a pair's
  # label its value's unless `labels:` gives the labels.
  defp breaks(options) do
    case Keyword.get(options, :breaks) do
      breaks when is_list(breaks) ->
        {values, labels} = Enum.map_reduce(breaks, %{}, &labelled/2)

        options
        |> Keyword.put(:breaks, fn _limits -> values end)
        |> labels(labels)

      _other ->
        options
    end
  end

  defp labelled({value, label}, labels), do: {value, Map.put(labels, value, label)}
  defp labelled(value, labels), do: {value, labels}

  defp labels(options, labels) when map_size(labels) == 0, do: options
  defp labels(options, labels), do: Keyword.put_new(options, :labels, labels)

  defp spelled(aesthetics) when is_list(aesthetics), do: Enum.map(aesthetics, &spelled/1)
  defp spelled(:colour), do: :color
  defp spelled(aesthetic), do: aesthetic
end
