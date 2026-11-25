defmodule GigRidges.DensityRidgelineGradient do
  @moduledoc """
  The gradient density ridges' geom: the density ridges' (`GigRidges.DensityRidgeline`), its
  options, aesthetics, scaling and legend keys alike, but a ridge whose `fill` varies along it
  drawn in pieces of one fill each, outlined round in their fill `gradient_lwd:` wide, as the
  gradient ridgeline's (`GigRidges.RidgelineGradient`) are.
  """

  use Giggly.Geom

  alias GigRidges.{DensityRidgeline, RidgelineGradient}

  defstruct scale: :none, rel_min_height: :none, panel_scaling: true, gradient_lwd: 0.5

  @type t :: %__MODULE__{
          scale: :none | float(),
          rel_min_height: :none | float(),
          panel_scaling: boolean(),
          gradient_lwd: float()
        }

  @impl Giggly.Geom
  def options, do: DensityRidgeline.options() ++ [gradient_lwd: RidgelineGradient.gradient_lwd()]

  @impl Giggly.Geom
  def accepted_aesthetics(geom), do: DensityRidgeline.accepted_aesthetics(density(geom))
  @impl Giggly.Geom
  def required_aesthetics(geom), do: DensityRidgeline.required_aesthetics(density(geom))
  @impl Giggly.Geom
  def numeric_aesthetics(geom), do: DensityRidgeline.numeric_aesthetics(density(geom))
  @impl Giggly.Geom
  def written_aesthetics(geom), do: DensityRidgeline.written_aesthetics(density(geom))
  @impl Giggly.Geom
  def default_aesthetics(geom, element),
    do: DensityRidgeline.default_aesthetics(density(geom), element)

  @impl Giggly.Geom
  def setup_data(geom, frame, axis_types),
    do: DensityRidgeline.setup_data(density(geom), frame, axis_types)

  @impl Giggly.Geom
  def draw_panel(geom, frame, context),
    do: DensityRidgeline.draw_panel(density(geom), frame, context)

  @impl Giggly.Geom
  def draw_key(geom, key, context), do: DensityRidgeline.draw_key(density(geom), key, context)
  @impl Giggly.Geom
  def key_size(geom, key, context), do: DensityRidgeline.key_size(density(geom), key, context)

  # The density ridges' geom it draws through, drawing each ridge in pieces.
  defp density(%__MODULE__{} = geom) do
    fields =
      geom
      |> Map.from_struct()
      |> Map.delete(:gradient_lwd)
      |> Map.put(:gradient, RidgelineGradient.millimetres(geom.gradient_lwd))

    struct!(DensityRidgeline, fields)
  end
end
