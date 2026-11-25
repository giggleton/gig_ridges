defmodule GigRidges.LineStyle do
  @moduledoc false

  # The style of a line gig_ridges draws by its own options, beside Giggly's options for the marks:
  # its colour, width and line type, each checked as Giggly checks its own, a colour through
  # Scales' documented `Scales.ColorOperations.parse/1`, which Giggly's colour check is, a width in
  # millimetres, and a line type by R's name or number or as a dash pattern, held as its pattern,
  # Giggly's own table and check copied (MIT), as Giggly's line-type check is not yet plugin API;
  # and the quantile lines' options setting each.

  # The line types, by name in the order of their numbers, 0 to 6, each held as its dash pattern:
  # the lengths of its dashes and gaps in turn, `{}` for a solid line, and `:none` for a blank one,
  # as R's graphics engine reads `lty`.
  @line_types [
    blank: :none,
    solid: {},
    dashed: {4, 4},
    dotted: {1, 3},
    dotdash: {1, 3, 4, 3},
    longdash: {7, 3},
    twodash: {2, 2, 6, 2}
  ]
  @line_type_names Keyword.keys(@line_types)

  # NimbleOptions' check of an option setting a colour: a CSS colour, kept in its one spelling,
  # uppercase hex, `:none` for none, or `:unset`, the option not given.
  @doc false
  @spec validate_color(term()) :: {:ok, String.t() | :none | :unset} | {:error, String.t()}
  def validate_color(:unset), do: {:ok, :unset}

  def validate_color(color) do
    case Scales.ColorOperations.parse(color) do
      {:ok, spelling} ->
        {:ok, spelling}

      :error ->
        {:error,
         "expected a CSS colour: a name such as \"steelblue\", a hex colour such as " <>
           "\"#4682B4\", \"transparent\", or :none, got: #{inspect(color)}"}
    end
  end

  # NimbleOptions' check of an option setting a line's width: millimetres, 0 or more, a float, or
  # `:unset`.
  @doc false
  @spec validate_width(term()) :: {:ok, float() | :unset} | {:error, String.t()}
  def validate_width(:unset), do: {:ok, :unset}
  def validate_width(width) when is_number(width) and width >= 0, do: {:ok, width / 1}

  def validate_width(width),
    do: {:error, "expected a width in millimetres, 0 or more, got: #{inspect(width)}"}

  # NimbleOptions' check of an option setting a line type: one of R's line types by name or by its
  # number, 0 to 6, or a dash pattern, a tuple of 2, 4, 6 or 8 lengths from 1 to 15; each held as
  # its dash pattern, a blank line as `:none`; or `:unset`.
  @doc false
  @spec validate_linetype(term()) :: {:ok, tuple() | :none | :unset} | {:error, String.t()}
  def validate_linetype(:unset), do: {:ok, :unset}

  def validate_linetype(number) when number in 0..6 do
    {_name, pattern} = Enum.at(@line_types, number)
    {:ok, pattern}
  end

  def validate_linetype(name) when name in @line_type_names,
    do: {:ok, Keyword.fetch!(@line_types, name)}

  def validate_linetype(pattern) when tuple_size(pattern) in [2, 4, 6, 8] do
    if pattern |> Tuple.to_list() |> Enum.all?(&(&1 in 1..15)),
      do: {:ok, pattern},
      else: linetype_error(pattern)
  end

  def validate_linetype(line_type), do: linetype_error(line_type)

  defp linetype_error(line_type) do
    {:error,
     "expected a line type: one of " <>
       Enum.map_join(@line_type_names, ", ", &inspect/1) <>
       ", its number, 0 to 6, or a dash pattern, a tuple of 2, 4, 6 or 8 lengths from 1 to " <>
       "15, such as {4, 4}, got: #{inspect(line_type)}"}
  end

  # The struct fields the quantile lines' options take, each `:unset` until given.
  @doc false
  @spec vline_fields() :: keyword()
  def vline_fields,
    do: [vline_color: :unset, vline_colour: :unset, vline_width: :unset, vline_linetype: :unset]

  # The options setting the quantile lines' style over the ridge's, as ggridges'
  # `vline_colour`, `vline_width` and `vline_linetype` set it: each `:unset`, the ridge's own,
  # unless given. `vline_colour:` is `vline_color:` spelled as R spells it, as Giggly takes
  # `colour:` for `color:`.
  @doc false
  @spec vline_options() :: keyword()
  def vline_options do
    color = [
      type: {:custom, __MODULE__, :validate_color, []},
      default: :unset,
      doc: "The quantile lines' colour, over the ridge's: a CSS colour name or a hex colour."
    ]

    [
      vline_color: color,
      vline_colour: Keyword.put(color, :doc, "`vline_color:`, spelled as R spells it."),
      vline_width: [
        type: {:custom, __MODULE__, :validate_width, []},
        default: :unset,
        doc: "The quantile lines' width in millimetres, 0 or more, over the ridge's line width."
      ],
      vline_linetype: [
        type: {:custom, __MODULE__, :validate_linetype, []},
        default: :unset,
        doc:
          "The quantile lines' line type, over the ridge's: one of R's by name, " <>
            "`:dashed`, `:dotted` and the rest, by its number, 0 to 6, or a dash pattern."
      ]
    ]
  end

  # The option's two spellings given at once, refused as Giggly refuses `colour:` beside `color:`.
  @doc false
  @spec vline_conflicts(keyword()) :: [String.t()]
  def vline_conflicts(options) do
    if Keyword.get(options, :vline_color, :unset) != :unset and
         Keyword.get(options, :vline_colour, :unset) != :unset,
       do: ["takes vline_color: or vline_colour:, not both, since each sets the lines' colour"],
       else: []
  end

  # The quantile lines' style: the colour, line width and line type the options set, each column
  # over the ridge's.
  @doc false
  @spec vline_style(map()) :: keyword()
  def vline_style(options) do
    color = if options.vline_color != :unset, do: options.vline_color, else: options.vline_colour

    [color: color, linewidth: options.vline_width, linetype: options.vline_linetype]
    |> Enum.reject(fn {_column, value} -> value == :unset end)
  end
end
