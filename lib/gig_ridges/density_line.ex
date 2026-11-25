defmodule GigRidges.DensityLine do
  @moduledoc """
  The density line geom: a density, or any `y` above 0, drawn as a ridgeline over a baseline of 0
  (`GigRidges.Ridgeline`), filled R's grey70 down to 0 and outlined in black along its top alone,
  its legend keys the ridgeline's, where ggplot2's `geom_density()` is filled with nothing.

  It takes no `scale` or `min_height`: ggridges' density line lists them among its aesthetics,
  but neither changes what it draws, so they are refused here, as Giggly refuses what would do
  nothing.
  """

  use Giggly.Geom

  alias Giggly.DataFrame
  alias GigRidges.Ridgeline

  defstruct []

  @type t :: %__MODULE__{}

  @impl Giggly.Geom
  def accepted_aesthetics(_geom),
    do: [:x, :y, :group, :alpha, :color, :fill, :linetype, :linewidth]

  @impl Giggly.Geom
  def required_aesthetics(_geom), do: [:x, :y]

  @impl Giggly.Geom
  def numeric_aesthetics(_geom), do: [y: "it is how far the line reaches above 0"]

  @impl Giggly.Geom
  def written_aesthetics(_geom), do: [:ymin, :ymax]

  @impl Giggly.Geom
  def default_aesthetics(_geom, element), do: Ridgeline.default_aesthetics(ridgeline(), element)

  # The rows set up as a ridgeline's whose baseline is 0 and whose height is each `y`, the `y`
  # kept as it was given, as ggridges keeps it, though the ribbon's setup puts it at the baseline.
  @impl Giggly.Geom
  def setup_data(_geom, frame, axis_types) do
    lifted =
      frame
      |> DataFrame.put(:height, DataFrame.pull(frame, :y))
      |> DataFrame.put(:y, List.duplicate(0, DataFrame.row_count(frame)))

    set_up = Ridgeline.setup_data(ridgeline(), lifted, axis_types)
    kept = for name <- DataFrame.names(set_up), name != :height, do: {name, name}

    set_up
    |> DataFrame.put(:y, DataFrame.pull(set_up, :ymax))
    |> DataFrame.select(kept)
  end

  @impl Giggly.Geom
  def draw_panel(_geom, frame, context), do: Ridgeline.draw_panel(ridgeline(), frame, context)
  @impl Giggly.Geom
  def draw_key(_geom, key, context), do: Ridgeline.draw_key(ridgeline(), key, context)
  @impl Giggly.Geom
  def key_size(_geom, key, context), do: Ridgeline.key_size(ridgeline(), key, context)

  # The ridgeline it draws through, the ridgeline's own.
  defp ridgeline, do: %Ridgeline{}
end
