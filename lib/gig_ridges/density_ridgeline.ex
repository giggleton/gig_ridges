defmodule GigRidges.DensityRidgeline do
  @moduledoc """
  The density ridges' geom: the ridgeline (`GigRidges.Ridgeline`), but each point 1.8 times its
  `height` above its baseline where neither the `scale:` option nor a mapped `scale` gives
  another, so neighbouring ridges overlap, and cut off by `rel_min_height` in place of
  `min_height`.

  A point whose height is below `rel_min_height` times the layer's greatest height, across every
  panel, is left out of its ridge, which breaks there. Like `scale`, `rel_min_height` is an option
  and an aesthetic: given as an option, a share from 0 to 1, its value is every point's; else a
  mapped column gives each point its own; else 0, and no point is left out.
  """

  use Giggly.Geom

  alias GigRidges.Ridgeline

  defstruct scale: :none, rel_min_height: :none

  @type t :: %__MODULE__{scale: :none | float(), rel_min_height: :none | float()}

  @unmapped_scale 1.8

  @impl Giggly.Geom
  def options do
    [
      scale:
        Keyword.put(
          Keyword.fetch!(Ridgeline.options(), :scale),
          :doc,
          "How many times its `height` each ridge reaches above its baseline, a number above 0, " <>
            "every point's, over a mapped `scale`; 1.8 where neither gives one."
        ),
      rel_min_height: [
        type: {:custom, __MODULE__, :validate_share, []},
        default: :none,
        doc:
          "The height below which a point is left out of its ridge, as a share of the layer's " <>
            "greatest height, from 0 to 1, every point's, over a mapped `rel_min_height`; 0 " <>
            "where neither gives one."
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

  @doc false
  @spec validate_share(term()) :: {:ok, :none | float()} | {:error, String.t()}
  def validate_share(:none), do: {:ok, :none}

  def validate_share(share) when is_number(share) and share >= 0 and share <= 1,
    do: {:ok, share / 1}

  def validate_share(other), do: {:error, "expected a number from 0 to 1, got: #{inspect(other)}"}

  # The ridgeline this geom draws through: its options this one's, cut off by `rel_min_height`,
  # and its unmapped scale 1.8.
  defp ridgeline(%__MODULE__{} = geom) do
    fields =
      geom
      |> Map.from_struct()
      |> Map.merge(%{cut_off: :rel_min_height, unmapped_scale: @unmapped_scale})

    struct!(Ridgeline, fields)
  end
end
