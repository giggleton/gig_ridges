defmodule GigRidges.RidgelineGradient do
  @moduledoc """
  The gradient ridgeline geom: the ridgeline (`GigRidges.Ridgeline`), its options, aesthetics,
  defaults and legend keys alike, but a ridge whose `fill` varies along it drawn in pieces, one a
  run of points of one fill, from its first point to the next run's, filled and outlined round in
  that fill, `gradient_lwd:` wide in R's line-width units, 0.5 unless given, so the seams do not
  show, and its top line drawn over them, as ggridges' gradient ridgelines draw one.
  """

  use Giggly.Geom

  alias GigRidges.Ridgeline

  defstruct scale: :none, min_height: :none, gradient_lwd: 0.5

  @type t :: %__MODULE__{
          scale: :none | float(),
          min_height: :none | float(),
          gradient_lwd: float()
        }

  @impl Giggly.Geom
  def options, do: Ridgeline.options() ++ [gradient_lwd: gradient_lwd()]

  @doc false
  @spec gradient_lwd() :: keyword()
  def gradient_lwd do
    [
      type: {:custom, __MODULE__, :validate_gradient_lwd, []},
      default: 0.5,
      doc:
        "The width of the outline round each piece of one fill, in R's line-width units " <>
          "(1/96 inch), a number of 0 or more, so the seams between pieces do not show."
    ]
  end

  @doc false
  @spec validate_gradient_lwd(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_gradient_lwd(width) when is_number(width) and width >= 0, do: {:ok, width / 1}

  def validate_gradient_lwd(other),
    do: {:error, "expected a number of 0 or more, got: #{inspect(other)}"}

  # R's line-width units, ggplot2's `.pt`, in a millimetre.
  @line_width_units_per_millimetre 72.27 / 25.4

  @doc false
  @spec millimetres(float()) :: float()
  def millimetres(gradient_lwd), do: gradient_lwd / @line_width_units_per_millimetre

  @impl Giggly.Geom
  def accepted_aesthetics(geom), do: Ridgeline.accepted_aesthetics(ridgeline(geom))
  @impl Giggly.Geom
  def required_aesthetics(geom), do: Ridgeline.required_aesthetics(ridgeline(geom))
  @impl Giggly.Geom
  def numeric_aesthetics(geom), do: Ridgeline.numeric_aesthetics(ridgeline(geom))
  @impl Giggly.Geom
  def written_aesthetics(geom), do: Ridgeline.written_aesthetics(ridgeline(geom))
  @impl Giggly.Geom
  def default_aesthetics(geom, element),
    do: Ridgeline.default_aesthetics(ridgeline(geom), element)

  @impl Giggly.Geom
  def setup_data(geom, frame, axis_types),
    do: Ridgeline.setup_data(ridgeline(geom), frame, axis_types)

  @impl Giggly.Geom
  def draw_panel(geom, frame, context), do: Ridgeline.draw_panel(ridgeline(geom), frame, context)
  @impl Giggly.Geom
  def draw_key(geom, key, context), do: Ridgeline.draw_key(ridgeline(geom), key, context)
  @impl Giggly.Geom
  def key_size(geom, key, context), do: Ridgeline.key_size(ridgeline(geom), key, context)

  # The ridgeline it draws through, drawing each ridge in pieces.
  defp ridgeline(%__MODULE__{} = geom),
    do: %Ridgeline{
      scale: geom.scale,
      min_height: geom.min_height,
      gradient: millimetres(geom.gradient_lwd)
    }
end
