defmodule GigRidges.Draws do
  @moduledoc false

  # The random numbers the points' positions move the jittered points by, as Giggly's own jitter
  # draws them: from `seed`, by Erlang's `exsss` algorithm, so that a change of OTP's default
  # changes no drawing, each panel drawing afresh from the seed. Each of a layer's points, its rows
  # whose `datatype` is `"point"`, in turn draws `count` numbers from 0 to 1 from its panel's
  # stream, so a point's draws depend only on the seed and its place among its panel's points.

  alias Giggly.DataFrame

  @algorithm :exsss

  @doc false
  @spec points(DataFrame.t(), integer(), pos_integer()) :: [nil | [float()]]
  def points(frame, seed, count) do
    {draws, _streams} =
      [DataFrame.pull(frame, :datatype), DataFrame.pull(frame, :panel)]
      |> Enum.zip()
      |> Enum.map_reduce(%{}, fn
        {"point", panel}, streams ->
          stream = Map.get_lazy(streams, panel, fn -> :rand.seed_s(@algorithm, seed) end)

          {draws, stream} =
            Enum.map_reduce(1..count, stream, fn _draw, s -> :rand.uniform_s(s) end)

          {draws, Map.put(streams, panel, stream)}

        {_type, _panel}, streams ->
          {nil, streams}
      end)

    draws
  end
end
