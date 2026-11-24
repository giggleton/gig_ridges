defmodule GigRidges.DensityRidgeline do
  @moduledoc """
  The density ridges' geom: the ridgeline (`GigRidges.Ridgeline`), its options and aesthetics
  alike, but each point 1.8 times its `height` above its baseline where neither the `scale:`
  option nor a mapped `scale` gives another, so neighbouring ridges overlap.
  """

  use Giggly.Geom

  alias GigRidges.Ridgeline

  defstruct scale: :none, min_height: :none, rel_min_height: :none

  @type t :: %__MODULE__{
          scale: :none | float(),
          min_height: :none | float(),
          rel_min_height: :none | float()
        }

  @unmapped_scale 1.8

  @impl Giggly.Geom
  def options do
    Keyword.update!(Ridgeline.options(), :scale, fn spec ->
      Keyword.put(
        spec,
        :doc,
        "How many times its `height` each ridge reaches above its baseline, a number above 0, " <>
          "every point's, over a mapped `scale`; 1.8 where neither gives one."
      )
    end)
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

  # The ridgeline this geom draws through, its options this one's and its unmapped scale 1.8.
  defp ridgeline(%__MODULE__{} = geom) do
    struct!(Ridgeline, geom |> Map.from_struct() |> Map.put(:unmapped_scale, @unmapped_scale))
  end
end
