defmodule GigRidges.DensityRidgeline2 do
  @moduledoc """
  The closed density ridges' geom: the density ridges' (`GigRidges.DensityRidgeline`), its
  options, aesthetics, scaling and legend key alike, but each ridge outlined round its whole
  border, its baseline and sides too, where the density ridges' geom outlines its top alone.
  """

  use Giggly.Geom

  alias GigRidges.DensityRidgeline

  defstruct scale: :none,
            rel_min_height: :none,
            panel_scaling: true,
            vline_color: :unset,
            vline_colour: :unset,
            vline_width: :unset,
            vline_linetype: :unset

  @type t :: %__MODULE__{
          scale: :none | float(),
          rel_min_height: :none | float(),
          panel_scaling: boolean(),
          vline_color: :unset | String.t() | :none,
          vline_colour: :unset | String.t() | :none,
          vline_width: :unset | float(),
          vline_linetype: :unset | tuple() | :none
        }

  @impl Giggly.Geom
  def options, do: DensityRidgeline.options()

  # `vline_color:` and `vline_colour:` given at once.
  @impl Giggly.Geom
  def option_conflicts(options), do: GigRidges.LineStyle.vline_conflicts(options)

  @impl Giggly.Geom
  def accepted_aesthetics(geom), do: DensityRidgeline.accepted_aesthetics(closed(geom))
  @impl Giggly.Geom
  def required_aesthetics(geom), do: DensityRidgeline.required_aesthetics(closed(geom))
  @impl Giggly.Geom
  def numeric_aesthetics(geom), do: DensityRidgeline.numeric_aesthetics(closed(geom))
  @impl Giggly.Geom
  def written_aesthetics(geom), do: DensityRidgeline.written_aesthetics(closed(geom))
  @impl Giggly.Geom
  def default_aesthetics(geom, element),
    do: DensityRidgeline.default_aesthetics(closed(geom), element)

  @impl Giggly.Geom
  def setup_data(geom, frame, axis_types),
    do: DensityRidgeline.setup_data(closed(geom), frame, axis_types)

  @impl Giggly.Geom
  def draw_panel(geom, frame, context),
    do: DensityRidgeline.draw_panel(closed(geom), frame, context)

  @impl Giggly.Geom
  def draw_key(geom, key, context), do: DensityRidgeline.draw_key(closed(geom), key, context)
  @impl Giggly.Geom
  def key_size(geom, key, context), do: DensityRidgeline.key_size(closed(geom), key, context)

  # The density ridges' geom this one draws through, its options this one's, outlined round.
  defp closed(%__MODULE__{} = geom),
    do: struct!(DensityRidgeline, geom |> Map.from_struct() |> Map.put(:outline, :full))
end
