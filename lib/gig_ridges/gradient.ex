defmodule GigRidges.Gradient do
  @moduledoc false

  # A ridge whose fill varies along it drawn in pieces, as ggridges' gradient ridgelines draw
  # one: its points, in order along the ridge, gathered into runs of one fill each; each run a
  # piece from its first point to the next run's first, or to its own last where none follows,
  # filled down to the baseline and outlined round in its own fill, `width` millimetres wide, so
  # the seams between pieces do not show. The ridge's top line is the ridgeline's to draw over
  # them.

  alias Giggly.{DataFrame, Geom}

  @doc false
  @spec pieces(DataFrame.t(), float(), Geom.Context.t()) :: [Geom.primitive()]
  def pieces(ridge, width, context) do
    fills = DataFrame.pull(ridge, :fill)
    count = length(fills)

    fills
    |> Enum.with_index()
    |> Enum.chunk_by(fn {fill, _index} -> fill end)
    |> Enum.flat_map(fn [{fill, first} | _rest] = run ->
      {_fill, last} = List.last(run)
      through = if last + 1 < count, do: last + 1, else: last
      piece(ridge, Enum.to_list(first..through), fill, width, context)
    end)
  end

  # One run's piece: its rows and the next run's first, in the run's fill, outlined round in it.
  defp piece(ridge, indices, fill, width, context) do
    rows = length(indices)

    strip =
      ridge
      |> DataFrame.slice(indices)
      |> DataFrame.put(:fill, List.duplicate(fill, rows))
      |> DataFrame.put(:color, List.duplicate(fill, rows))
      |> DataFrame.put(:linewidth, List.duplicate(width, rows))

    Geom.draw_panel(ribbon(), strip, context)
  end

  defp ribbon, do: Geom.new(Geom.Ribbon, orientation: :x, outline_type: :full, linejoin: :round)
end
