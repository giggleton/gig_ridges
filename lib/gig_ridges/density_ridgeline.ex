defmodule GigRidges.DensityRidgeline do
  @moduledoc """
  The density ridges' geom: the ridgeline (`GigRidges.Ridgeline`), but each point's `height`
  scaled so the tallest ridge reaches the next baseline, then 1.8 times that above its baseline
  where neither the `scale:` option nor a mapped `scale` gives another, so neighbouring ridges
  overlap, and cut off by `rel_min_height` in place of `min_height`.

  A point whose height is below `rel_min_height` times the layer's greatest height, across every
  panel, is left out of its ridge, which breaks there. Like `scale`, `rel_min_height` is an option
  and an aesthetic: given as an option, a share from 0 to 1, its value is every point's; else a
  mapped column gives each point its own, a point whose value is missing never cut off; else 0,
  and no point is left out.

  It scales each point's `height` by its `iscale`, which it writes: the spacing between the
  layer's baselines, their span over one fewer than how many there are, over the greatest height
  of the point's panel, or of the layer under `panel_scaling: false`, so the tallest ridge reaches
  the next baseline at a `scale` of 1, whatever height is mapped. Over one baseline, `iscale` is
  1, and the heights are drawn as they are; where the greatest height is 0, a point has no
  `iscale`, and is left out. A point with no baseline is left out and the rest spaced by the
  baselines given, where ggridges draws none of the layer. The cut-off is taken on the heights
  scaled.
  """

  use Giggly.Geom

  alias Giggly.DataFrame
  alias GigRidges.{LineStyle, Ridgeline}

  # `outline` and `gradient` are no options: the ridges' outline, the top alone here, and the whole
  # border under the closed density ridges' geom (`GigRidges.DensityRidgeline2`); and `:none`, or
  # the width of the pieces' outlines under the gradient density ridges' geom
  # (`GigRidges.DensityRidgelineGradient`), each geom building the struct itself.
  defstruct scale: :none,
            rel_min_height: :none,
            panel_scaling: true,
            outline: :upper,
            gradient: :none,
            vline_color: :unset,
            vline_colour: :unset,
            vline_width: :unset,
            vline_linetype: :unset

  @type t :: %__MODULE__{
          scale: :none | float(),
          rel_min_height: :none | float(),
          panel_scaling: boolean(),
          outline: :upper | :full,
          gradient: :none | float(),
          vline_color: :unset | String.t() | :none,
          vline_colour: :unset | String.t() | :none,
          vline_width: :unset | float(),
          vline_linetype: :unset | tuple() | :none
        }

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
      ],
      panel_scaling: [
        type: :boolean,
        default: true,
        doc:
          "Whether each panel's ridges are scaled so its greatest height reaches the next " <>
            "baseline (`true`), or the layer's ridges together, so a panel of lower heights " <>
            "draws lower ridges (`false`)."
      ]
    ] ++ LineStyle.vline_options()
  end

  # `vline_color:` and `vline_colour:` given at once.
  @impl Giggly.Geom
  def option_conflicts(options), do: LineStyle.vline_conflicts(options)

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
  def setup_data(geom, frame, axis_types) do
    scaled = DataFrame.put(frame, :iscale, iscales(geom, frame))
    Ridgeline.setup_data(ridgeline(geom), scaled, axis_types)
  end

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

  # Each point's `iscale`: the spacing between the layer's baselines over the greatest height of
  # its panel, or of the layer under `panel_scaling: false`; 1 over one baseline; none where the
  # greatest height is 0.
  defp iscales(geom, frame) do
    heights = DataFrame.pull(frame, :height)

    keys =
      if geom.panel_scaling,
        do: DataFrame.pull(frame, :panel),
        else: List.duplicate(:layer, length(heights))

    case spacing(DataFrame.pull(frame, :y)) do
      :one -> List.duplicate(1.0, length(heights))
      spacing -> scaled_by(keys, greatest_by(keys, heights), spacing)
    end
  end

  # Each point's `iscale` from the greatest height under its key.
  defp scaled_by(keys, greatest, spacing),
    do: Enum.map(keys, fn key -> iscale(spacing, Map.fetch!(greatest, key)) end)

  # The greatest height under each key, a panel or the whole layer.
  defp greatest_by(keys, heights) do
    keys
    |> Enum.zip(heights)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, values} -> {key, greatest(values)} end)
  end

  defp iscale(_spacing, greatest) when greatest == 0, do: nil
  defp iscale(spacing, greatest), do: spacing / greatest

  # The greatest of `heights` that is a number, 0 where none is.
  defp greatest(heights) do
    heights
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> 0.0 end)
  end

  # The spacing between the layer's distinct baselines, their span over one fewer than how many
  # there are; `:one` where there is one or none.
  defp spacing(baselines) do
    distinct = baselines |> Enum.filter(&is_number/1) |> Enum.uniq()

    case length(distinct) do
      count when count < 2 -> :one
      count -> (Enum.max(distinct) - Enum.min(distinct)) / (count - 1)
    end
  end

  # The ridgeline this geom draws through: its options this one's, cut off by `rel_min_height`,
  # its heights scaled by `iscale`, and its unmapped scale 1.8.
  defp ridgeline(%__MODULE__{} = geom) do
    fields =
      geom
      |> Map.from_struct()
      |> Map.delete(:panel_scaling)
      |> Map.merge(%{cut_off: :rel_min_height, unmapped_scale: @unmapped_scale, iscaled: true})

    struct!(Ridgeline, fields)
  end
end
