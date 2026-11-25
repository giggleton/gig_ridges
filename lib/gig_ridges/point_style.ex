defmodule GigRidges.PointStyle do
  @moduledoc false

  # The style of the points gig_ridges draws by its own options, the jittered points the density
  # ridges' stat writes: their shape, size, stroke, colour, fill and alpha, each checked as Giggly
  # checks its own, a colour as a line's is (`GigRidges.LineStyle`), and a shape by R's number or
  # Giggly's name for it, Giggly's own table and check copied (MIT), as Giggly's shape check is not
  # yet plugin API.

  alias GigRidges.LineStyle

  # The 26 shapes by name, in the order of R's numbers for them, 0 to 25.
  @shapes [
    :square_open,
    :circle_open,
    :triangle_open,
    :plus,
    :cross,
    :diamond_open,
    :triangle_down_open,
    :square_cross,
    :asterisk,
    :diamond_plus,
    :circle_plus,
    :star,
    :square_plus,
    :circle_cross,
    :square_triangle,
    :square,
    :circle_small,
    :triangle,
    :diamond,
    :circle,
    :bullet,
    :circle_filled,
    :square_filled,
    :diamond_filled,
    :triangle_filled,
    :triangle_down_filled
  ]

  # ggridges' points' own defaults: R's shape 19, a solid circle, 1.5 mm across, outlined 0.5 mm.
  @default_shape :circle
  @default_size 1.5
  @default_stroke 0.5

  # NimbleOptions' check of a point's shape: R's number, 0 to 25, Giggly's name for one, a
  # character, drawn as it, or `:none` for no point; or `:unset`.
  @doc false
  @spec validate_shape(term()) :: {:ok, atom() | String.t()} | {:error, String.t()}
  def validate_shape(:unset), do: {:ok, :unset}
  def validate_shape(number) when number in 0..25, do: {:ok, Enum.at(@shapes, number)}
  def validate_shape(shape) when shape in @shapes or shape == :none, do: {:ok, shape}
  def validate_shape(<<_character::utf8>> = character), do: {:ok, character}

  def validate_shape(shape) do
    {:error,
     "expected one of a point's shapes, by name or by its number, 0 to 25, a character, or " <>
       ":none, got: #{inspect(shape)}; the names are #{Enum.map_join(@shapes, ", ", &inspect/1)}"}
  end

  # NimbleOptions' check of a point's size or its stroke: millimetres, 0 or more, a float; a
  # stroke `:none` for no outline; or `:unset`.
  @doc false
  @spec validate_size(term()) :: {:ok, float() | :unset} | {:error, String.t()}
  def validate_size(:unset), do: {:ok, :unset}
  def validate_size(size) when is_number(size) and size >= 0, do: {:ok, size / 1}

  def validate_size(size),
    do: {:error, "expected a size in millimetres, 0 or more, got: #{inspect(size)}"}

  @doc false
  @spec validate_stroke(term()) :: {:ok, float() | :none | :unset} | {:error, String.t()}
  def validate_stroke(:none), do: {:ok, :none}
  def validate_stroke(stroke), do: validate_size(stroke)

  # NimbleOptions' check of a point's alpha: from 0, invisible, to 1, opaque, a float; or `:unset`.
  @doc false
  @spec validate_alpha(term()) :: {:ok, float() | :unset} | {:error, String.t()}
  def validate_alpha(:unset), do: {:ok, :unset}

  def validate_alpha(alpha) when is_number(alpha) and alpha >= 0 and alpha <= 1,
    do: {:ok, alpha / 1}

  def validate_alpha(alpha), do: {:error, "expected a number from 0 to 1, got: #{inspect(alpha)}"}

  # The struct fields the points' options take, each `:unset` until given.
  @doc false
  @spec point_fields() :: keyword()
  def point_fields,
    do:
      for(
        name <-
          [:point_shape, :point_size, :point_stroke, :point_color, :point_colour] ++
            [:point_fill, :point_alpha],
        do: {name, :unset}
      )

  # The options setting the jittered points' style, as ggridges' `point_*` set it: each `:unset`,
  # the default or the ridge's, unless given. `point_colour:` is `point_color:` spelled as R spells
  # it.
  @doc false
  @spec point_options() :: keyword()
  def point_options do
    color = [
      type: {:custom, LineStyle, :validate_color, []},
      default: :unset,
      doc: "The points' colour, over the ridge's: a CSS colour name or a hex colour."
    ]

    [
      point_shape: [
        type: {:custom, __MODULE__, :validate_shape, []},
        default: :unset,
        doc:
          "The points' shape, by R's number, 0 to 25, or Giggly's name; 19, a circle, unless given."
      ],
      point_size: [
        type: {:custom, __MODULE__, :validate_size, []},
        default: :unset,
        doc: "The points' size in millimetres, 0 or more; 1.5 unless given."
      ],
      point_stroke: [
        type: {:custom, __MODULE__, :validate_stroke, []},
        default: :unset,
        doc: "The points' outline's width in millimetres, 0 or more, or :none; 0.5 unless given."
      ],
      point_color: color,
      point_colour: Keyword.put(color, :doc, "`point_color:`, spelled as R spells it."),
      point_fill: Keyword.put(color, :doc, "The points' fill, over the ridge's."),
      point_alpha: [
        type: {:custom, __MODULE__, :validate_alpha, []},
        default: :unset,
        doc: "The points' alpha, from 0 to 1, over the ridge's."
      ]
    ]
  end

  # The option's two spellings given at once, refused as Giggly refuses `colour:` beside `color:`.
  @doc false
  @spec point_conflicts(keyword()) :: [String.t()]
  def point_conflicts(options) do
    if Keyword.get(options, :point_color, :unset) != :unset and
         Keyword.get(options, :point_colour, :unset) != :unset,
       do: ["takes point_color: or point_colour:, not both, since each sets the points' colour"],
       else: []
  end

  # The points' style: their shape, size and stroke, the options' or ggridges' defaults, and the
  # colour, fill and alpha the options set, each column over the ridge's.
  @doc false
  @spec point_style(map()) :: keyword()
  def point_style(options) do
    color = if options.point_color != :unset, do: options.point_color, else: options.point_colour

    [
      shape: given(options.point_shape, @default_shape),
      size: given(options.point_size, @default_size),
      stroke: given(options.point_stroke, @default_stroke),
      color: color,
      fill: options.point_fill,
      alpha: options.point_alpha
    ]
    |> Enum.reject(fn {_column, value} -> value == :unset end)
  end

  defp given(:unset, default), do: default
  defp given(value, _default), do: value
end
