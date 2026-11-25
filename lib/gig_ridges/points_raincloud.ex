defmodule GigRidges.PointsRaincloud do
  @moduledoc """
  The jittered points' raincloud: each of the layer's points,
  its rows whose `datatype` is `"point"`, dropped below its ridge as rain below a cloud, into a
  band `height:` deep, 0.4 unless given, whose top is `ygap:` below its baseline, 0.05 unless
  given, in the units of the y axis, and moved across by up to `width:` either way, 0 unless
  given; its `ymin` the height it is drawn at. Every other row stays where it is, but under
  `adjust_vlines:` the quantile lines, the rows whose `datatype` is `"vline"`, which then run
  across the band the points fall in.

  It is `GigRidges.PointsJitter` with its band so placed:
  a jitter `width:` across, `height:` halved up or down, about `ygap:` and half of `height:`
  below the baseline, drawn from `seed:`, 0 unless given, as the jitter draws its distances. A
  layer with no `datatype`, as a ridgeline's, is left as it is.

  It is given to a layer's `position:`, alone or with its options, as `position:
  {GigRidges.PointsRaincloud, height: 0.2, seed: 7}`.
  """

  # ggridges' `position_raincloud()`, which is its jitter with the band so placed too.

  use Giggly.Position

  alias GigRidges.PointsJitter

  defstruct width: 0.0, height: 0.4, ygap: 0.05, adjust_vlines: false, seed: 0

  @type t :: %__MODULE__{
          width: float(),
          height: float(),
          ygap: float(),
          adjust_vlines: boolean(),
          seed: integer()
        }

  @impl Giggly.Position
  def options do
    [
      width: [
        type: {:custom, PointsJitter, :validate_amount, []},
        default: 0.0,
        doc: "How far each point moves at most across, either way, in the units of the x axis."
      ],
      height: [
        type: {:custom, PointsJitter, :validate_amount, []},
        default: 0.4,
        doc: "How deep the band the points fall in is, in the units of the y axis."
      ],
      ygap: [
        type: {:custom, PointsJitter, :validate_offset, []},
        default: 0.05,
        doc: "How far below its baseline the points' band begins, in the units of the y axis."
      ],
      adjust_vlines: [
        type: :boolean,
        default: false,
        doc: "Whether the quantile lines run across the points' band, not from the baseline up."
      ],
      seed: [
        type: :integer,
        default: 0,
        doc:
          "The seed the random distances are drawn from, any integer: the same seed moves the " <>
            "same points the same way, so another seed draws other distances."
      ]
    ]
  end

  @impl Giggly.Position
  def compute_layer(raincloud, frame, axis_types),
    do: Giggly.Position.compute_layer(jitter(raincloud), frame, axis_types)

  # The jitter the raincloud is: its band `height` deep, centred `ygap` and half of it below
  # the baseline.
  defp jitter(raincloud) do
    half = raincloud.height / 2

    %PointsJitter{
      width: raincloud.width,
      height: half,
      yoffset: -(raincloud.ygap + half),
      adjust_vlines: raincloud.adjust_vlines,
      seed: raincloud.seed
    }
  end
end
