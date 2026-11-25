defmodule GigRidges.VRidgeline do
  @moduledoc """
  The vertical ridgeline geom: the ridgeline (`GigRidges.Ridgeline`) turned, each group a ridge
  up `y`, its baseline its `x` and its outer edge `scale` times its `width` beyond it, filled back
  to the baseline and outlined along that edge, the ridge of the greatest baseline drawn first,
  filled R's grey80.

  A point whose width is below `min_width` is left out of its ridge, which breaks there; with no
  `min_width`, a point below 0 is, and a point whose mapped `min_width` is missing is never cut
  off. `scale` and `min_width` are each an option and an aesthetic, as the ridgeline's `scale` and
  `min_height` are: an option given is every point's; else a mapped column gives each point its
  own; else a `scale` of 1 and a `min_width` of 0. Its legend keys take the ribbon's room, twice
  as wide as their line.
  """

  use Giggly.Geom

  alias GigRidges.Ridgeline

  defstruct scale: :none, min_width: :none

  @type t :: %__MODULE__{scale: :none | float(), min_width: :none | float()}

  @impl Giggly.Geom
  def options do
    [
      scale: [
        type: {:custom, Ridgeline, :validate_scale, []},
        default: :none,
        doc:
          "How many times its `width` each ridge reaches beyond its baseline, a number above 0, " <>
            "every point's, over a mapped `scale`; 1 where neither gives one."
      ],
      min_width: [
        type: {:custom, Ridgeline, :validate_number, []},
        default: :none,
        doc:
          "The width below which a point is left out of its ridge, every point's, over a " <>
            "mapped `min_width`; 0 where neither gives one."
      ]
    ]
  end

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

  # The ridgeline this geom draws through: along `y`, cut off by `min_width`.
  defp ridgeline(%__MODULE__{scale: scale, min_width: min_width}),
    do: %Ridgeline{scale: scale, min_height: min_width, cut_off: :min_width, along: :y}
end
