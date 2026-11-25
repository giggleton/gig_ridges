defmodule GigRidges.RidgesTheme do
  @moduledoc false

  # ggridges' `theme_ridges()`, as running it shows it to differ from `theme_grey()`: Giggly's
  # default theme (`Giggly.Plot.theme_gray/2`) at a base size of `font_size`, in `font_family`,
  # which sets every size, spacing and margin that follows from the base size, with its settings
  # laid over it by `Giggly.Plot.theme/2`. Nothing behind the marks is filled and no rectangle is
  # bordered; the major grid lines and the ticks are grey90, `line_size` millimetres wide, with no
  # minor grid; every text is black, the tick labels, the legends' labels, the strips' labels, the
  # subtitle and the caption at six sevenths of the base size; the axes' titles at the far end of
  # their axes unless `center_axis_labels`; the y axis's tick labels on their baselines, so each
  # ridge's name sits on it; the plot's title bold at the base size; the strips grey80 with no
  # margin round their labels; the legends justified left of centre, their keys a line tall; and
  # the plot's margin half the base size, the base size on the right. Without `grid`, the grid
  # lines and the y axis's ticks go, and the ticks left are black.

  alias Giggly.Plot

  # R's grey90, grey80 and grey50, as Giggly takes a colour, by CSS.
  @grey90 "#E5E5E5"
  @grey80 "#CCCCCC"
  @grey50 "#7F7F7F"

  # Six sevenths, the share of the base size ggridges' smaller text is drawn at.
  @small 0.857

  @doc false
  @spec options() :: keyword()
  def options do
    [
      font_size: [
        type: {:custom, __MODULE__, :validate_size, []},
        default: 14,
        doc: "How big its text is, in points: every size, spacing and margin follows from it."
      ],
      font_family: [
        type: :string,
        default: "",
        doc: "The font its text is drawn in, by name; `\"\"`, the default sans-serif."
      ],
      line_size: [
        type: {:custom, __MODULE__, :validate_size, []},
        default: 0.5,
        doc: "How wide its grid lines and ticks are, in millimetres."
      ],
      grid: [
        type: :boolean,
        default: true,
        doc: "Whether the major grid lines and the y axis's ticks are drawn."
      ],
      center_axis_labels: [
        type: :boolean,
        default: false,
        doc: "Whether the axes' titles are centred on their axes, not at their far ends."
      ]
    ]
  end

  @doc false
  @spec validate_size(term()) :: {:ok, number()} | {:error, String.t()}
  def validate_size(size) when is_number(size) and size >= 0, do: {:ok, size}

  def validate_size(other),
    do: {:error, "expected a size, a number of 0 or more, got: #{inspect(other)}"}

  @doc false
  @spec theme(Plot.t() | nil, keyword()) :: term()
  def theme(plot, options) do
    ridges = NimbleOptions.validate!(options, options())
    base = [base_size: ridges[:font_size], base_family: ridges[:font_family]]

    plot
    |> gray(base)
    |> Plot.theme(settings(ridges))
  end

  defp gray(nil, base), do: Plot.theme_gray(base)
  defp gray(plot, base), do: Plot.theme_gray(plot, base)

  defp settings(ridges) do
    size = ridges[:font_size]
    small = size * @small
    hjust = if ridges[:center_axis_labels], do: 0.5, else: 1

    [
      rect: [fill: "transparent", linewidth: 0, linetype: :blank],
      axis_text: [color: "black", size: {:rel, @small}],
      axis_text_x: [margin: [top: small / 4]],
      axis_text_y: [margin: [right: small / 4], vjust: 0],
      axis_title_x: [hjust: hjust, margin: [top: small / 2, bottom: small / 4]],
      axis_title_y: [hjust: hjust, margin: [right: small / 2, left: small / 4]],
      panel_background: :none,
      panel_grid_minor: :none,
      plot_background: :none,
      legend_key: :none,
      legend_justification: {:left, :center},
      legend_key_size: {1, :lines},
      legend_ticks_length: {0.2, :lines},
      legend_text: [size: {:rel, @small}],
      strip_background: [fill: @grey80, color: @grey50, linewidth: 0, linetype: :blank],
      strip_text: [color: "black", size: {:rel, @small}, margin: 0],
      plot_title: [face: :bold, size: {:rel, 1}, vjust: 0.5, margin: [bottom: size / 2]],
      plot_subtitle: [size: {:rel, @small}, margin: [bottom: small / 2]],
      plot_caption: [size: {:rel, @small}, margin: [top: small / 2]],
      plot_margin: [top: size / 2, right: size, bottom: size / 2, left: size / 2]
    ] ++ grid(ridges[:grid], ridges[:line_size])
  end

  defp grid(true, width),
    do: [
      axis_ticks: [color: @grey90, linewidth: width],
      panel_grid_major: [color: @grey90, linewidth: width]
    ]

  defp grid(false, width),
    do: [
      axis_ticks: [color: "black", linewidth: width],
      axis_ticks_y: :none,
      panel_grid_major: :none
    ]
end
