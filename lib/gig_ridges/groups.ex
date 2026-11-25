defmodule GigRidges.Groups do
  @moduledoc false

  # A layer's rows gathered by panel and group, as the ridges' stats compute from them, and the
  # rows each group's results are written back as: a group's columns holding one value within
  # it, which Giggly's `Giggly.Stat.Carry` finds, carried onto every row written for it.

  alias Giggly.DataFrame
  alias Giggly.Stat.Carry

  # The layer's rows with a finite `x` and `y` gathered one row a group, its `x` values listed in
  # `:xs` and each other column of `lists`, `{gathered, column}`, listed where the layer has it,
  # beside the columns carried; and the columns carried, every one holding one value within each
  # group.
  @doc false
  @spec gather(DataFrame.t(), keyword(atom())) :: {DataFrame.t(), [atom()]}
  def gather(frame, lists \\ []) do
    finite = DataFrame.filter(frame, {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})
    names = DataFrame.names(finite)
    carried = Carry.constant_columns(finite, names -- [:x])
    listed = for {gathered, column} <- lists, column in names, do: {gathered, {:list, [column]}}

    groups =
      DataFrame.summarise(
        finite,
        [:panel, :group],
        [
          {:xs, {:list, [:x]}}
          | listed ++ for(name <- carried -- [:panel, :group], do: {name, {:first, [name]}})
        ]
      )

    {groups, carried}
  end

  # A group's rows: the carried columns of its row of `groups`, at `index`, repeated `count`
  # times, beside the columns computed for it.
  @doc false
  @spec rows(DataFrame.t(), non_neg_integer(), non_neg_integer(), [atom()], keyword(list())) ::
          DataFrame.t()
  def rows(groups, index, count, carried, computed),
    do: written(groups, List.duplicate(index, count), carried, computed)

  # The groups' rows end to end; a layer of no groups has none, in the columns it would have,
  # those carried and `computed`.
  @doc false
  @spec joined([DataFrame.t()], DataFrame.t(), [atom()], [atom()]) :: DataFrame.t()
  def joined([], groups, carried, computed),
    do: written(groups, [], carried, Enum.map(computed, &{&1, []}))

  def joined(frames, _groups, _carried, _computed), do: DataFrame.concat_rows(frames)

  defp written(groups, indices, carried, computed) do
    groups
    |> DataFrame.slice(indices)
    |> DataFrame.select(Enum.map(carried, fn name -> {name, name} end))
    |> then(fn frame ->
      Enum.reduce(computed, frame, fn {name, values}, built ->
        DataFrame.put(built, name, values)
      end)
    end)
  end
end
