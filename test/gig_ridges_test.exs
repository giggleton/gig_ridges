defmodule GigRidgesTest do
  use ExUnit.Case, async: true

  doctest GigRidges

  alias Giggly.{DataFrame, Plot}

  @ridges %{
    "x" => [1, 2, 3, 1, 2, 3],
    "y" => [0, 0, 0, 1, 1, 1],
    "h" => [0.2, 0.9, 0.3, 0.5, 0.4, 0.1]
  }

  # A tight group a and a wide group b, whose densities ggridges' goldens are read over.
  @spread %{
    "v" => [-1, -0.5, 0, 0, 0.5, 1, -9, -6, -3, 0, 3, 6, 9],
    "g" => List.duplicate("a", 6) ++ List.duplicate("b", 7)
  }

  describe "geom_ridgeline/3" do
    test "reaches scale times each height above its baseline" do
      frame =
        @ridges
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :y})
        |> GigRidges.geom_ridgeline()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :ymin) == [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
      assert DataFrame.pull(frame, :ymax) == [0.2, 0.9, 0.3, 1.5, 1.4, 1.1]
    end

    test "leaves out a point below its min_height" do
      frame =
        @ridges
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :y})
        |> GigRidges.geom_ridgeline(min_height: 0.3)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :ymax) == [nil, 0.9, 0.3, 1.5, 1.4, nil]
    end

    # ggridges 0.5.7 on ggplot2 4.0.3: `geom_ridgeline()` has no `rel_min_height`; given, it is
    # "Ignoring unknown parameters", and mapped it leaves out nothing it draws. Departure: given, it
    # is refused, as Giggly refuses an option a layer does not take.
    test "takes no rel_min_height, refusing it given and ignoring it mapped" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:rel_min_height\]/, fn ->
        @ridges
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :y})
        |> GigRidges.geom_ridgeline(rel_min_height: 0.5)
      end

      frame =
        @ridges
        |> Map.put("r", List.duplicate(0.5, 6))
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :y, rel_min_height: :r})
        |> GigRidges.geom_ridgeline()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :ymax) == [0.2, 0.9, 0.3, 1.5, 1.4, 1.1]
    end

    test "draws the highest baseline first, so a lower ridge is drawn over the one above" do
      svg =
        @ridges
        |> Plot.new(%{x: :x, y: :y, height: :h, fill: {:factor, [:y]}})
        |> GigRidges.geom_ridgeline()
        |> Plot.theme_void()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      [first, second] =
        ~r/<polygon [^>]*fill: (#[0-9A-F]{6})/
        |> Regex.scan(svg)
        |> Enum.map(fn [_polygon, fill] -> fill end)
        |> Enum.take(2)

      # The baseline of 1 takes the second hue, #00BFC4, and is drawn first.
      assert {first, second} == {"#00BFC4", "#F8766D"}
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `layer_data()` of `geom_ridgeline(aes(scale = s))`
    # over these rows, s 1, 2, 3 and 0.5 three times: each point reaches its own scale times its
    # height; `scale = 2` given beside the mapping is every point's.
    test "takes each point's scale from a mapped column, a scale given over it" do
      plot =
        Plot.new(Map.put(@ridges, "s", [1, 2, 3, 0.5, 0.5, 0.5]), %{
          x: :x,
          y: :y,
          height: :h,
          group: :y,
          scale: :s
        })

      reaches =
        Enum.map([[], [scale: 2]], fn options ->
          plot
          |> GigRidges.geom_ridgeline(options)
          |> Giggly.layer_data()
          |> DataFrame.pull(:ymax)
          |> Enum.map(fn reach -> Float.round(reach, 12) end)
        end)

      assert reaches == [[0.2, 1.8, 0.9, 1.25, 1.2, 1.05], [0.4, 1.8, 0.6, 2.0, 1.8, 1.2]]
    end

    # ggridges 0.5.7 on ggplot2 4.0.3 draws `geom_ridgeline(aes(min_height = m))`, m 0.25 for the
    # first ridge and 0.45 for the second, as the lines of its points above their ridge's own.
    test "takes each point's min_height from a mapped column" do
      ymax =
        @ridges
        |> Map.put("m", [0.25, 0.25, 0.25, 0.45, 0.45, 0.45])
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :y, min_height: :m})
        |> GigRidges.geom_ridgeline()
        |> Giggly.layer_data()
        |> DataFrame.pull(:ymax)

      assert ymax == [nil, 0.9, 0.3, 1.5, nil, nil]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_ridgeline(aes(min_height = m))` over heights
    # 0.2, 0.9, 1, 0.9, 0.3 on two ridges, m 0.5 on the first and NA on the second, draws 3 points
    # of the first ridge and all 5 of the second; over heights 0.2, -0.5, 1, 0.9, 0.3 with m NA, all
    # 5, the one below 0 too, which an unmapped min_height leaves out.
    test "never cuts off a point whose mapped min_height is missing" do
      kept = fn heights, cut_offs ->
        %{"x" => [1, 2, 3, 4, 5, 1, 2, 3, 4, 5], "h" => heights, "m" => cut_offs}
        |> Map.put("y", [0, 0, 0, 0, 0, 1, 1, 1, 1, 1])
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :y, min_height: :m})
        |> GigRidges.geom_ridgeline()
        |> Giggly.layer_data()
        |> DataFrame.split(:group)
        |> Enum.sort()
        |> Enum.map(fn {_group, rows} ->
          rows |> DataFrame.pull(:ymax) |> Enum.count(&is_number/1)
        end)
      end

      heights = [0.2, 0.9, 1, 0.9, 0.3]
      assert kept.(heights ++ heights, List.duplicate(0.5, 5) ++ List.duplicate(nil, 5)) == [3, 5]

      below = [0.2, -0.5, 1, 0.9, 0.3]
      assert kept.(below ++ below, List.duplicate(nil, 10)) == [5, 5]
    end

    test "takes its aesthetics mapped in its own mapping, as in the plot's" do
      ymax =
        @ridges
        |> Map.merge(%{"s" => List.duplicate(2, 6), "m" => List.duplicate(0.3, 6)})
        |> Plot.new(%{})
        |> GigRidges.geom_ridgeline(%{
          x: :x,
          y: :y,
          height: :h,
          group: :y,
          scale: :s,
          min_height: :m
        })
        |> Giggly.layer_data()
        |> DataFrame.pull(:ymax)

      assert ymax == [nil, 1.8, 0.6, 2.0, 1.8, nil]
    end

    test "takes a colour, line width and line type set for every ridge" do
      plot = Plot.new(@ridges, %{x: :x, y: :y, height: :h, group: :y})

      looks = fn options ->
        frame = plot |> GigRidges.geom_ridgeline(options) |> Giggly.layer_data()
        for column <- [:color, :linewidth, :linetype], do: frame |> DataFrame.pull(column) |> hd()
      end

      [_color, _width, solid] = looks.([])
      [color, width, dashed] = looks.(colour: "#FF0000", linewidth: 2, linetype: :dashed)

      assert {color, width} == {"#FF0000", 2.0}
      assert dashed != solid
    end

    test "refuses options it does not take and mistakes, naming itself" do
      plot = Plot.new(@ridges, %{x: :x, y: :y, height: :h})

      assert_raise NimbleOptions.ValidationError, ~r/expected a number above 0/, fn ->
        GigRidges.geom_ridgeline(plot, scale: 0)
      end

      assert_raise ArgumentError, ~r/^GigRidges.geom_ridgeline\/3 sets :shape/, fn ->
        GigRidges.geom_ridgeline(plot, shape: 1)
      end

      unheighted =
        @ridges
        |> Plot.new(%{x: :x, y: :y})
        |> GigRidges.geom_ridgeline()

      assert_raise ArgumentError, ~r/^GigRidges.geom_ridgeline\/3 needs :height/, fn ->
        Giggly.layer_data(unheighted)
      end
    end

    test "leaves out a point with no height, and one below 0 where no cut-off is given" do
      ymax =
        %{"x" => [1, 2, 3, 4], "y" => [0, 0, 0, 0], "h" => [0.2, nil, -0.1, 0.4]}
        |> Plot.new(%{x: :x, y: :y, height: :h})
        |> GigRidges.geom_ridgeline()
        |> Giggly.layer_data()
        |> DataFrame.pull(:ymax)

      assert ymax == [0.2, nil, nil, 0.4]
    end

    test "refuses a height mapped to a column of text, naming the aesthetic" do
      unnumbered =
        %{"x" => [1, 2], "y" => [0, 0], "h" => ["a", "b"]}
        |> Plot.new(%{x: :x, y: :y, height: :h})
        |> GigRidges.geom_ridgeline()

      assert_raise ArgumentError, ~r/^GigRidges.geom_ridgeline\/3 maps :height to "h"/, fn ->
        Giggly.layer_data(unnumbered)
      end
    end
  end

  describe "geom_density_ridges/3" do
    setup do
      %{plot: Plot.new(GigDatasets.mpg(), %{x: :hwy, y: :class})}
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `layer_data()` of `ggplot(mpg, aes(hwy, class)) +
    # geom_density_ridges()`: the compact class's density, its bandwidth the joint one, 0.966, the
    # mean of every class's `bw.nrd0()`, read from three bandwidths below the least to three above
    # the greatest at 512 places: its greatest 0.13744463038596, at 26.0398123901504, and its 1st,
    # 100th, 256th, 400th and 512th values.
    test "estimates each group's density with the mean of the groups' bandwidths", %{plot: plot} do
      frame = plot |> GigRidges.geom_density_ridges() |> Giggly.layer_data()
      groups = DataFrame.split(frame, :group)
      assert map_size(groups) == 7
      assert Enum.all?(groups, fn {_group, rows} -> DataFrame.row_count(rows) == 512 end)

      compact =
        groups
        |> Enum.find(fn {_group, rows} -> rows |> DataFrame.pull(:y) |> hd() == 2 end)
        |> elem(1)

      densities = DataFrame.pull(compact, :density)
      peak = Enum.max(densities)
      place = Enum.at(DataFrame.pull(compact, :x), Enum.find_index(densities, &(&1 == peak)))

      assert_in_delta peak, 0.13744463038596, 1.0e-12
      assert_in_delta place, 26.0398123901504, 1.0e-9

      expected = [
        0.0,
        8.44785898127544e-13,
        0.115952498607505,
        0.00219958550813068,
        9.86211922274186e-05
      ]

      got = Enum.map([0, 99, 255, 399, 511], fn index -> Enum.at(densities, index) end)

      Enum.zip_with(got, expected, fn value, wanted -> assert_in_delta value, wanted, 1.0e-12 end)
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `ggplot(mpg, aes(hwy, class)) +
    # geom_density_ridges(panel_scaling = ) + facet_wrap(~drv)`, each panel's tallest ridge, its
    # `ymax - ymin`: every panel's 1.8, the default scale, or under `panel_scaling = FALSE` the
    # layer's greatest density's alone, the others lower; a class of fewer than three cars in a
    # panel is left out of it, 5, 4 and 3 classes drawn.
    test "scales each panel's greatest density to the scale, or the layer's under panel_scaling: false",
         %{plot: plot} do
      tallest =
        Enum.map([true, false], fn panel_scaling ->
          frame =
            plot
            |> Plot.facet_wrap(:drv)
            |> GigRidges.geom_density_ridges(panel_scaling: panel_scaling)
            |> Giggly.layer_data()

          frame
          |> DataFrame.split(:panel)
          |> Enum.sort()
          |> Enum.map(fn {_panel, rows} ->
            reach =
              Enum.zip_with(DataFrame.pull(rows, :ymax), DataFrame.pull(rows, :ymin), fn high,
                                                                                         low ->
                high - low
              end)

            {Float.round(Enum.max(reach), 12), map_size(DataFrame.split(rows, :group))}
          end)
        end)

      assert tallest == [
               [{1.8, 5}, {1.8, 4}, {1.8, 3}],
               [{0.628663213718, 5}, {1.377454120158, 4}, {1.8, 3}]
             ]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `layer_data()` of `geom_density_ridges()` over x 1, 2,
    # 4, 7 in group a and 20, 21 in group b: b, of two values, is left out, but its `bw.nrd0()`
    # counts towards the joint bandwidth and its values towards the places, which run from
    # -1.729065 to 23.729065.
    test "leaves out a group of fewer than three values, which still counts towards the places" do
      frame =
        %{"x" => [1, 2, 4, 7, 20, 21], "g" => ["a", "a", "a", "a", "b", "b"]}
        |> Plot.new(%{x: :x, y: :g})
        |> GigRidges.geom_density_ridges()
        |> Giggly.layer_data()

      places = DataFrame.pull(frame, :x)
      baselines = frame |> DataFrame.pull(:y) |> Enum.uniq()
      ends = {Float.round(Enum.min(places), 6), Float.round(Enum.max(places), 6)}

      assert {baselines, ends} == {[1], {-1.729065, 23.729065}}
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_density_ridges(aes(scale = ss))`, ss 3 for the
    # suv class and 1 for the rest: each class's tallest reach, `ymax - ymin`, by baseline, the
    # mapping over the default 1.8; and `aes(rel_min_height = rr)`, rr 0.5 for suv alone, leaves
    # suv 44 of its 512 places, the rest every one.
    test "takes each ridge's scale and rel_min_height from a mapped column" do
      suv = fn wanted, other ->
        {fn class -> if class == "suv", do: wanted, else: other end, [:class]}
      end

      scaled =
        GigDatasets.mpg()
        |> Plot.new(%{x: :hwy, y: :class, scale: suv.(3, 1)})
        |> GigRidges.geom_density_ridges()
        |> Giggly.layer_data()

      reach =
        scaled
        |> DataFrame.split(:y)
        |> Enum.sort()
        |> Enum.map(fn {_baseline, rows} ->
          rows
          |> DataFrame.pull(:ymax)
          |> Enum.zip_with(DataFrame.pull(rows, :ymin), fn high, low -> high - low end)
          |> Enum.max()
          |> Float.round(12)
        end)

      assert reach == [
               1.0,
               0.561962452764,
               0.822774440896,
               0.960214469775,
               0.831407103507,
               0.479064215831,
               2.244942813493
             ]

      cut =
        GigDatasets.mpg()
        |> Plot.new(%{x: :hwy, y: :class, rel_min_height: suv.(0.5, 0)})
        |> GigRidges.geom_density_ridges()
        |> Giggly.layer_data()

      kept =
        cut
        |> DataFrame.split(:group)
        |> Enum.sort()
        |> Enum.map(fn {_baseline, rows} ->
          rows
          |> DataFrame.pull(:ymax)
          |> Enum.count(&is_number/1)
        end)

      assert kept == [512, 512, 512, 512, 512, 512, 44]
    end

    # ggridges 0.5.7's ridges are filled grey70 and outlined in black half a millimetre wide,
    # whatever the theme's ink. Departure: a theme's geom fill and colour replace them, as they do
    # every Giggly geom's and ggplot2's own geoms', where ggridges 0.5.7 keeps grey70 and black.
    test "fills its ridges grey70 and outlines them in black, but in a theme's geom fill and colour",
         %{plot: plot} do
      themes = [
        plot,
        Plot.theme_dark(plot, ink: "white", paper: "#333333"),
        Plot.theme(plot, geom: [fill: "#FF0000", colour: "#0000FF"])
      ]

      looks =
        Enum.map(themes, fn themed ->
          frame = themed |> GigRidges.geom_density_ridges() |> Giggly.layer_data()

          Enum.map([:fill, :color, :linewidth], fn column ->
            frame |> DataFrame.pull(column) |> Enum.uniq()
          end)
        end)

      own = [["#B3B3B3"], ["#000000"], [0.5]]
      assert looks == [own, own, [["#FF0000"], ["#0000FF"], [0.5]]]
    end

    test "takes a bandwidth given, every group estimated with it", %{plot: plot} do
      narrow = plot |> GigRidges.geom_density_ridges(bandwidth: 0.5) |> Giggly.layer_data()
      wide = plot |> GigRidges.geom_density_ridges(bandwidth: 5) |> Giggly.layer_data()

      assert Enum.max(DataFrame.pull(narrow, :density)) >
               Enum.max(DataFrame.pull(wide, :density))

      assert_raise NimbleOptions.ValidationError, ~r/expected a number above 0 or :nrd0/, fn ->
        GigRidges.geom_density_ridges(plot, bandwidth: -1)
      end
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `stat_density_ridges(bandwidth = 1, from = -5,
    # to = 5, n = 7)` over a tight group a (x -1, -0.5, 0, 0, 0.5, 1) and a wide group b (x -9, -6,
    # -3, 0, 3, 6, 9): seven places from -5 to 5, each density R's `density(x, bw = 1, from = -5,
    # to = 5, n = 7)`; and at `n = 1000`, past the 512 its grid starts from, a's 500th place reads
    # 0.3309387554618286; and at `n = 2`, the least taken, b reads 6.3591540636271239e-4 at both
    # -12 and 12; moved by the estimate, never by Giggly.
    test "reads each density at n places from from to to" do
      frame =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_density_ridges(bandwidth: 1, from: -5, to: 5, n: 7)
        |> Giggly.layer_data()

      [a, b] = by_group(frame, [:x, :density])

      places = [-5.0, -10 / 3, -5 / 3, 0.0, 5 / 3, 10 / 3, 5.0]

      for [read_at, _densities] <- [a, b] do
        assert Enum.all?(Enum.zip_with(read_at, places, &abs(&1 - &2)), &(&1 < 1.0e-12))
      end

      a_golden = [2.55727512038e-5, 6.13932727728e-3, 1.28344860885e-1, 3.30926116421e-1]
      b_golden = [4.23062784328e-2, 5.57523951582e-2, 3.76573815680e-2, 5.82433062703e-2]

      for {[_x, densities], golden} <- [{a, a_golden}, {b, b_golden}] do
        mirrored = golden ++ (golden |> Enum.reverse() |> tl())
        assert Enum.all?(Enum.zip_with(densities, mirrored, &abs(&1 - &2)), &(&1 < 1.0e-12))
      end

      [[many] | _b] =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_density_ridges(bandwidth: 1, n: 1000)
        |> Giggly.layer_data()
        |> by_group([:density])

      assert length(many) == 1000
      assert abs(Enum.at(many, 499) - 0.3309387554618286) < 1.0e-12

      [_a, [ends, two]] =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_density_ridges(bandwidth: 1, n: 2)
        |> Giggly.layer_data()
        |> by_group([:x, :density])

      assert ends == [-12.0, 12.0]
      assert Enum.all?(two, &(abs(&1 - 6.3591540636271239e-4) < 1.0e-12))
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, over groups a and b above at `bandwidth = 1`:
    # `from = -5` alone reads 512 places from -5 to 12, three bandwidths past the greatest value,
    # and `to = 5` alone from -12; `from = 8, to = 12, n = 3` reads b at 0.042282525236001067,
    # 0.034586405217207537 and 0.000633539421405289, its values past four bandwidths below 8 adding
    # nothing, and a, every value of it there, at 0; and `from = 20` alone, above where `to` falls,
    # fails its computation and draws no ridge, as does `from = 12` alone, just where `to` falls.
    test "takes either end alone, and reads no ridge where the places would run backwards" do
      read = fn options, columns ->
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_density_ridges([bandwidth: 1] ++ options)
        |> Giggly.layer_data()
        |> by_group(columns)
      end

      ends = fn [[places]] -> {hd(places), List.last(places), length(places)} end
      assert ends.(read.([from: -5], [:x]) |> Enum.take(1)) == {-5.0, 12.0, 512}
      assert ends.(read.([to: 5], [:x]) |> Enum.take(1)) == {-12.0, 5.0, 512}

      [[a], [b]] = read.([from: 8, to: 12, n: 3], [:density])
      assert a == [0.0, 0.0, 0.0]
      golden = [0.042282525236001067, 0.034586405217207537, 0.000633539421405289]
      assert Enum.all?(Enum.zip_with(b, golden, &abs(&1 - &2)), &(&1 < 1.0e-12))

      assert read.([from: 20], [:x]) == []
      assert read.([from: 12], [:x]) == []
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `stat_density_ridges(aes(weight = w), bandwidth = 1,
    # from = -5, to = 5, n = 5)` over groups a and b, a weighed 1 to 6 and b 1 but 10 at its 0:
    # each density R's `density(x, bw = 1, weights = w / sum(w))`, the group's own weights; a
    # zero weight at a's -0.5 reads a as though the row were gone; the weights over 100 read the
    # same, totalling under 1; the joint bandwidth, 2.15, the same weighted or not, reading the
    # same places; and a weight of 2 for a and 3 for b kept in `layer_data()`, one varying not.
    test "weighs each group's density by its rows' weights, the bandwidth unweighted" do
      weighed = fn weights, options ->
        @spread
        |> Map.put("w", weights)
        |> Plot.new(%{x: :v, y: :g, weight: :w})
        |> GigRidges.stat_density_ridges(options)
        |> Giggly.layer_data()
        |> by_group([:x, :density])
      end

      close? = fn read, golden ->
        Enum.all?(Enum.zip_with(read, golden, &abs(&1 - &2)), &(&1 < 1.0e-12))
      end

      weights = [1, 2, 3, 4, 5, 6, 1, 1, 1, 10, 1, 1, 1]
      [[_, a], [_, b]] = weighed.(weights, bandwidth: 1, from: -5, to: 5, n: 5)

      a_golden = [
        8.4505047118059456e-6,
        1.8475417785424206e-2,
        3.3092611642087810e-1,
        5.6198022741306114e-2,
        4.2694997695806398e-5
      ]

      assert close?.(a, a_golden)

      [[_, hundredths] | _b] =
        weighed.(Enum.map(weights, &(&1 / 100)), bandwidth: 1, from: -5, to: 5, n: 5)

      assert close?.(hundredths, a_golden)

      assert close?.(b, [
               1.8509839275899817e-2,
               3.3026930357241489e-2,
               2.4981689013830774e-1,
               3.3026930357241482e-2,
               1.8509839275899831e-2
             ])

      [[_, gone] | _b] =
        weighed.(List.replace_at(weights, 1, 0), bandwidth: 1, from: -5, to: 5, n: 5)

      assert close?.(gone, [
               7.6483978807405603e-6,
               1.4732067003518817e-2,
               3.2870893524466399e-1,
               6.1646020743792905e-2,
               4.7177776012724504e-5
             ])

      unweighted = @spread |> Plot.new(%{x: :v, y: :g}) |> GigRidges.stat_density_ridges()
      places = unweighted |> Giggly.layer_data() |> by_group([:x])
      assert Enum.map(weighed.(weights, []), &Enum.take(&1, 1)) == places

      kept = fn weights ->
        frame =
          @spread
          |> Map.put("w", weights)
          |> Plot.new(%{x: :v, y: :g, weight: :w})
          |> GigRidges.stat_density_ridges(bandwidth: 1)
          |> Giggly.layer_data()

        if :weight in DataFrame.names(frame),
          do: frame |> by_group([:weight]) |> Enum.map(fn [w] -> Enum.uniq(w) end)
      end

      assert kept.(List.duplicate(2, 6) ++ List.duplicate(3, 7)) == [[2], [3]]
      assert kept.(weights) == nil
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, groups a and b weighed as above: a's weight at -0.5
    # missing, or -1, or all of a's 0, fails the computation and draws nothing; faceted by group,
    # it draws b's panel alone; and a third group c of two values, too few to estimate, a weight
    # of it missing, draws a and b. Departure: Giggly, which cannot warn, draws as ggridges does
    # without the warning. A weight of text is refused, naming the aesthetic.
    test "draws no ridge in a panel whose estimated weights R's density() refuses" do
      weights = [1, 2, 3, 4, 5, 6, 1, 1, 1, 10, 1, 1, 1]

      rows = fn data, weights, faceted? ->
        data
        |> Map.put("w", weights)
        |> Map.put("p", data["g"])
        |> Plot.new(%{x: :v, y: :g, weight: :w})
        |> GigRidges.stat_density_ridges(bandwidth: 1)
        |> then(fn plot -> if faceted?, do: Plot.facet_wrap(plot, :p), else: plot end)
        |> Giggly.layer_data()
        |> DataFrame.row_count()
      end

      for bad <- [List.replace_at(weights, 1, nil), List.replace_at(weights, 1, -1)] do
        assert rows.(@spread, bad, false) == 0
        assert rows.(@spread, bad, true) == 512
      end

      assert rows.(@spread, List.duplicate(0, 6) ++ Enum.drop(weights, 6), false) == 0

      small =
        @spread
        |> Map.update!("v", &(&1 ++ [4, 5]))
        |> Map.update!("g", &(&1 ++ ["c", "c"]))

      assert rows.(small, weights ++ [nil, 1], false) == 1024

      assert_raise ArgumentError, ~r/maps :weight to "w", a :string column/, fn ->
        @spread
        |> Map.put("w", Enum.map(weights, &Integer.to_string/1))
        |> Plot.new(%{x: :v, y: :g, weight: :w})
        |> GigRidges.stat_density_ridges()
        |> Giggly.layer_data()
      end
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_density_ridges(stat = "identity")` over heights
    # given on baselines 0, 1 and 3, greatest 0.4, 0.2 and 0.8: the tallest reaches 1.35, 0.675 and
    # 2.7, at 1.8 times the heights over the greatest, 0.8, times the baselines' spacing, their
    # span over one fewer than how many, 1.5; at `scale = 1`, 0.75, 0.375 and 1.5; faceted, 0 and 1
    # in one panel and 3 in another, each panel's greatest 1.5, the spacing still the layer's,
    # 1.5, 0.75 and 1.5, and under `panel_scaling = FALSE` the layer's, 0.75, 0.375 and 1.5; one
    # ridge, at 3, its heights as they are, 0.4; heights all 0 no point; and a missing height,
    # baselines 0 and 2, reaches 2 and 1, the greatest the rest's.
    test "scales whatever height it is given so the tallest reaches the next baseline" do
      given = %{
        "x" => Enum.flat_map(1..3, fn _ridge -> [1, 2, 3, 4, 5] end),
        "y" => Enum.flat_map([0, 1, 3], &List.duplicate(&1, 5)),
        "d" => [0.1, 0.3, 0.4, 0.3, 0.1, 0.05, 0.1, 0.2, 0.1, 0.05, 0.1, 0.2, 0.8, 0.2, 0.1],
        "f" => Enum.flat_map(~w(p p q), &List.duplicate(&1, 5))
      }

      reaches = fn data, options, faceted? ->
        data
        |> Plot.new(%{x: :x, y: :y, height: :d, group: :y})
        |> Plot.layer(%{}, [stat: :identity, geom: GigRidges.DensityRidgeline] ++ options)
        |> then(fn plot -> if faceted?, do: Plot.facet_wrap(plot, :f), else: plot end)
        |> Giggly.layer_data()
        |> by_group([:ymin, :ymax])
        |> Enum.map(fn [lows, highs] ->
          highs
          |> Enum.zip_with(lows, fn
            nil, _low -> nil
            high, low -> Float.round(high - low, 9)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.max(fn -> nil end)
        end)
      end

      assert reaches.(given, [], false) == [1.35, 0.675, 2.7]
      assert reaches.(given, [scale: 1], false) == [0.75, 0.375, 1.5]
      assert reaches.(given, [scale: 1], true) == [1.5, 0.75, 1.5]
      assert reaches.(given, [scale: 1, panel_scaling: false], true) == [0.75, 0.375, 1.5]

      one = %{
        "x" => [1, 2, 3, 4, 5],
        "y" => List.duplicate(3, 5),
        "d" => [0.05, 0.1, 0.4, 0.1, 0.05]
      }

      assert reaches.(one, [scale: 1], false) == [0.4]

      flat = %{"x" => [1, 2, 3, 1, 2, 3], "y" => [0, 0, 0, 1, 1, 1], "d" => List.duplicate(0, 6)}
      assert reaches.(flat, [], false) == [nil, nil]

      missing = %{
        "x" => [1, 2, 3, 4, 5, 1, 2, 3, 4, 5],
        "y" => [0, 0, 0, 0, 0, 2, 2, 2, 2, 2],
        "d" => [0.1, 0.3, 0.4, 0.3, nil, 0.05, 0.1, 0.2, 0.1, 0.05]
      }

      assert reaches.(missing, [scale: 1], false) == [2.0, 1.0]
    end

    # Departure: ggridges 0.5.7 on ggplot2 4.0.3, `geom_density_ridges(stat = "identity")` over
    # heights on baselines 0 and 2 and one more with its baseline missing, gives every point a
    # missing `iscale` and draws nothing, one missing baseline blanking the layer. gig_ridges
    # leaves that point out, as ggplot2 leaves out a row missing an aesthetic it needs, and
    # scales the rest by the spacing of the baselines given, 2, over the greatest height, 0.3.
    test "leaves out a point with no baseline, the others scaled by the baselines given" do
      ymax =
        %{
          "x" => [1, 2, 3, 4, 5, 6],
          "y" => [0, 0, 0, 2, 2, nil],
          "d" => [0.1, 0.3, 0.2, 0.1, 0.2, 0.1]
        }
        |> Plot.new(%{x: :x, y: :y, height: :d})
        |> Plot.layer(%{}, stat: :identity, geom: GigRidges.DensityRidgeline, scale: 1)
        |> Giggly.layer_data()
        |> DataFrame.pull(:ymax)
        |> Enum.map(&(&1 && Float.round(&1, 9)))

      assert ymax == [0.666666667, 2.0, 1.333333333, 2.666666667, 3.333333333, nil]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, groups a and b of @spread on baselines 0 and 3,
    # `bandwidth = 1`: `layer_data()` keeps `height` the density, greatest 0.3307764, beside
    # `iscale`, 9.06957, the tallest reaching 5.4; `aes(height = after_stat(ndensity))` reaches 5.4
    # on each ridge; and the stat drawn by the plain ridgeline, unscaled, 0.3307764.
    test "keeps the density its height and writes the scale it draws it at, iscale" do
      data = Map.put(@spread, "y", List.duplicate(0, 6) ++ List.duplicate(3, 7))

      tallest = fn frame ->
        frame
        |> by_group([:ymin, :ymax])
        |> Enum.map(fn [lows, highs] ->
          highs |> Enum.zip_with(lows, &(&1 - &2)) |> Enum.max() |> Float.round(6)
        end)
      end

      frame =
        data
        |> Plot.new(%{x: :v, y: :y, group: :y})
        |> GigRidges.geom_density_ridges(bandwidth: 1)
        |> Giggly.layer_data()

      assert frame |> DataFrame.pull(:height) |> Enum.max() |> Float.round(7) == 0.3307764

      assert frame |> DataFrame.pull(:iscale) |> Enum.uniq() |> Enum.map(&Float.round(&1, 5)) == [
               9.06957
             ]

      assert tallest.(frame) |> Enum.max() == 5.4

      by_share =
        data
        |> Plot.new(%{x: :v, y: :y, group: :y, height: {:after_stat, [:ndensity]}})
        |> GigRidges.geom_density_ridges(bandwidth: 1)
        |> Giggly.layer_data()

      assert tallest.(by_share) == [5.4, 5.4]

      unscaled =
        data
        |> Plot.new(%{x: :v, y: :y, group: :y})
        |> Plot.layer(%{}, stat: GigRidges.DensityRidges, geom: GigRidges.Ridgeline, bandwidth: 1)
        |> Giggly.layer_data()

      assert tallest.(unscaled) |> Enum.max() |> Float.round(6) == 0.330776
    end

    test "refuses a from not below its to, and n below 2 or not whole, naming the function" do
      plot = Plot.new(@spread, %{x: :v, y: :g})

      for {from, to} <- [{5, -5}, {1, 1}] do
        assert_raise ArgumentError,
                     ~r/^GigRidges.stat_density_ridges\/3 takes a from: below its to:.*from: #{from}/,
                     fn -> GigRidges.stat_density_ridges(plot, from: from, to: to) end
      end

      for {option, value} <- [n: 1, n: 7.5, from: :low] do
        assert_raise NimbleOptions.ValidationError, ~r/:#{option}.*got: #{inspect(value)}/, fn ->
          GigRidges.stat_density_ridges(plot, [{option, value}])
        end
      end
    end

    test "takes a scale and rel_min_height given, every ridge's", %{plot: plot} do
      frame =
        plot
        |> GigRidges.geom_density_ridges(scale: 1, rel_min_height: 0.5)
        |> Giggly.layer_data()

      reaches =
        frame
        |> DataFrame.pull(:ymax)
        |> Enum.zip_with(DataFrame.pull(frame, :ymin), fn
          nil, _low -> nil
          high, low -> high - low
        end)

      kept = Enum.filter(reaches, &is_number/1)

      # At a scale of 1 the panel's greatest density reaches the next baseline, 1 above; a point
      # below half of it is left out.
      assert Float.round(Enum.max(kept), 12) == 1.0
      assert Enum.min(kept) >= 0.5
      assert length(kept) < length(reaches)
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_density_ridges(bandwidth = 1,
    # rel_min_height = 0.5)` over a tight group a (x -1, -0.5, 0, 0, 0.5, 1) and a wide group b
    # (x -9, -6, -3, 0, 3, 6, 9), counting the places of each ridge's drawn top line: in one
    # panel a keeps 60 of its 512 and b none, b's peak under half of a's, so the cut-off is not
    # each group's own; faceted by group with `panel_scaling = FALSE`, a keeps 182 of the 512 its
    # narrower panel spans and b still none, so it is not each panel's either, but the layer's.
    test "cuts off by rel_min_height of the layer's greatest height, every panel's" do
      frame = %{
        "v" => [-1, -0.5, 0, 0, 0.5, 1, -9, -6, -3, 0, 3, 6, 9],
        "g" => List.duplicate("a", 6) ++ List.duplicate("b", 7)
      }

      plot = Plot.new(frame, %{x: :v, y: :g})

      kept = fn layered ->
        layered
        |> Giggly.layer_data()
        |> DataFrame.split(:group)
        |> Enum.sort()
        |> Enum.map(fn {_group, rows} ->
          rows |> DataFrame.pull(:ymax) |> Enum.count(&is_number/1)
        end)
      end

      one_panel = GigRidges.geom_density_ridges(plot, bandwidth: 1, rel_min_height: 0.5)
      assert kept.(one_panel) == [60, 0]

      faceted =
        plot
        |> GigRidges.geom_density_ridges(bandwidth: 1, rel_min_height: 0.5, panel_scaling: false)
        |> Plot.facet_wrap(:g)

      assert kept.(faceted) == [182, 0]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, groups a and b of the test above on baselines 0 and
    # 3, `geom_density_ridges(aes(group = y), bandwidth = 1, rel_min_height = 0.5)`: a keeps 60 of
    # its 512 places and b none, as 1 apart, the cut-off a share of the greatest height whatever
    # the ridges' spacing; and `aes(rel_min_height = r)`, r 0.5 for a and NA for b, mapped in the
    # layer's own mapping, keeps 60 of a's and every one of b's.
    test "cuts off by a share of the greatest height whatever the spacing, none where missing" do
      frame = %{
        "v" => [-1, -0.5, 0, 0, 0.5, 1, -9, -6, -3, 0, 3, 6, 9],
        "y" => List.duplicate(0, 6) ++ List.duplicate(3, 7),
        "r" => List.duplicate(0.5, 6) ++ List.duplicate(nil, 7)
      }

      kept = fn layered ->
        layered
        |> Giggly.layer_data()
        |> DataFrame.split(:group)
        |> Enum.sort()
        |> Enum.map(fn {_group, rows} ->
          rows |> DataFrame.pull(:ymax) |> Enum.count(&is_number/1)
        end)
      end

      given =
        frame
        |> Plot.new(%{x: :v, y: :y, group: :y})
        |> GigRidges.geom_density_ridges(bandwidth: 1, rel_min_height: 0.5)

      assert kept.(given) == [60, 0]

      mapped =
        frame
        |> Plot.new(%{})
        |> GigRidges.geom_density_ridges(%{x: :v, y: :y, group: :y, rel_min_height: :r},
          bandwidth: 1
        )

      assert kept.(mapped) == [60, 512]
    end

    test "takes a rel_min_height from 0 to 1 and refuses one outside", %{plot: plot} do
      kept = fn share ->
        plot
        |> GigRidges.geom_density_ridges(rel_min_height: share)
        |> Giggly.layer_data()
        |> DataFrame.pull(:ymax)
        |> Enum.count(&is_number/1)
      end

      # 0 leaves out no place of the 7 classes' ridges; 1, all but those at the greatest height.
      assert kept.(0) == 7 * 512
      assert kept.(1) in 1..511

      for share <- [1.5, -0.1, :half] do
        assert_raise NimbleOptions.ValidationError, ~r/got: #{inspect(share)}/, fn ->
          GigRidges.geom_density_ridges(plot, rel_min_height: share)
        end
      end
    end

    # ggridges 0.5.7 on ggplot2 4.0.3: `geom_density_ridges()` has no `min_height`; given, it is
    # "Ignoring unknown parameters". Departure: given, it is refused, as Giggly refuses an option a
    # layer does not take; mapped, it is ignored, every place kept.
    test "takes no min_height, refusing it given and ignoring it mapped", %{plot: plot} do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:min_height\]/, fn ->
        GigRidges.geom_density_ridges(plot, min_height: 0.01)
      end

      frame =
        GigDatasets.mpg()
        |> Plot.new(%{x: :hwy, y: :class, min_height: {fn _class -> 1.0e6 end, [:class]}})
        |> GigRidges.geom_density_ridges()
        |> Giggly.layer_data()

      assert Enum.all?(DataFrame.pull(frame, :ymax), &is_number/1)
    end

    test "gives each density as a share of its group's greatest, its ndensity", %{plot: plot} do
      frame = plot |> GigRidges.geom_density_ridges() |> Giggly.layer_data()

      shares =
        frame
        |> DataFrame.split(:group)
        |> Enum.map(fn {_group, rows} ->
          densities = DataFrame.pull(rows, :density)
          peak = Enum.max(densities)
          DataFrame.pull(rows, :ndensity) == Enum.map(densities, fn density -> density / peak end)
        end)

      assert shares == List.duplicate(true, 7)
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `layer_data()` of `geom_density_ridges()` over x 1, 2,
    # 4, 7 in group a, 20, 21, 22 in b and 50 in c: c, of one value, is left out and adds nothing to
    # the joint bandwidth, but its value counts towards the places, which run from -2.09927399669
    # to 53.0992739967; a's greatest density is 0.17729721223.
    test "leaves a group of one value out of the joint bandwidth" do
      frame =
        %{"x" => [1, 2, 4, 7, 20, 21, 22, 50], "g" => ~w(a a a a b b b c)}
        |> Plot.new(%{x: :x, y: :g})
        |> GigRidges.geom_density_ridges()
        |> Giggly.layer_data()

      {_group, first} =
        frame
        |> DataFrame.split(:group)
        |> Enum.find(fn {_group, rows} -> rows |> DataFrame.pull(:y) |> hd() == 1 end)

      places = DataFrame.pull(frame, :x)

      assert map_size(DataFrame.split(frame, :group)) == 2
      assert_in_delta Enum.max(DataFrame.pull(first, :density)), 0.17729721223, 1.0e-11
      assert_in_delta Enum.min(places), -2.09927399669, 1.0e-10
      assert_in_delta Enum.max(places), 53.0992739967, 1.0e-9
    end

    test "draws no ridge where every group has fewer than three values" do
      frame =
        %{"x" => [1, 2, 5, 6], "g" => ["a", "a", "b", "b"]}
        |> Plot.new(%{x: :x, y: :g})
        |> GigRidges.geom_density_ridges()
        |> Giggly.layer_data()

      assert DataFrame.row_count(frame) == 0
    end

    test "names the function called in its refusals", %{plot: plot} do
      assert_raise ArgumentError, ~r/^GigRidges.geom_density_ridges\/3 sets :shape/, fn ->
        GigRidges.geom_density_ridges(plot, shape: 1)
      end

      assert_raise ArgumentError, ~r/^GigRidges.stat_density_ridges\/3 sets :shape/, fn ->
        GigRidges.stat_density_ridges(plot, shape: 1)
      end

      assert_raise ArgumentError,
                   ~r/^GigRidges.geom_density_ridges\/3 maps :scale to "model"/,
                   fn ->
                     plot
                     |> Plot.aes(%{scale: :model})
                     |> GigRidges.geom_density_ridges()
                     |> Giggly.layer_data()
                   end
    end

    test "needs a height under a stat that writes none" do
      unheighted =
        %{"x" => [1, 2], "y" => [0, 0]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.layer(%{}, stat: :identity, geom: GigRidges.DensityRidgeline)

      assert_raise ArgumentError, ~r/needs :height/, fn -> Giggly.layer_data(unheighted) end
    end

    test "draws each class's legend key filled as its ridge is, outlined in black", %{plot: plot} do
      svg =
        plot
        |> Plot.aes(%{fill: :class})
        |> GigRidges.geom_density_ridges()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      keys = Regex.scan(~r/<rect [^>]*stroke: #000000;[^>]*fill: (#[0-9A-F]{6})/, svg)

      assert length(Enum.uniq_by(keys, fn [_rect, fill] -> fill end)) == 7
    end

    test "draws through Giggly as any layer does", %{plot: plot} do
      svg =
        plot
        |> GigRidges.stat_density_ridges(alpha: 0.6)
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert length(Regex.scan(~r/<polygon /, svg)) >= 7
    end
  end

  describe "geom_density_ridges2/3" do
    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_density_ridges2(bandwidth = 1)` over groups a
    # and b of @spread: each ridge one polygon of 1024 points, its 512 places along its top and
    # back along its baseline, filled grey70 and outlined black 0.5 mm wide round its whole
    # border, with no line apart, where `geom_density_ridges()` draws a polygon unoutlined and its
    # top a line; its rows, defaults and legend keys those of `geom_density_ridges()`.
    test "draws each ridge as one polygon outlined round its whole border" do
      plot = Plot.new(@spread, %{x: :v, y: :g})
      closed = GigRidges.geom_density_ridges2(plot, bandwidth: 1)

      polygons =
        closed
        |> Plot.theme_void()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()
        |> then(&Regex.scan(~r/<(polygon|polyline) points=.([^"']*)["'] style=.([^"']*)/, &1))

      assert [[_, "polygon", first, style], [_, "polygon", second, style]] = polygons
      assert Enum.map([first, second], &length(String.split(&1, " ", trim: true))) == [1024, 1024]
      assert style =~ "stroke-width: 1.07; stroke: #000000"
      assert style =~ "fill: #B3B3B3"

      open = GigRidges.geom_density_ridges(plot, bandwidth: 1)

      for column <- [:x, :ymin, :ymax, :fill, :color, :linewidth] do
        assert DataFrame.pull(Giggly.layer_data(closed), column) ==
                 DataFrame.pull(Giggly.layer_data(open), column)
      end
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, the legend keys of `geom_ridgeline()`,
    # `geom_density_ridges()` and `geom_density_ridges2()` at a `linewidth` of 6, 7, 10 and 20:
    # 17.345, the theme's least, then 19.917, 28.453 and 56.906 TeX points, a square as wide as the
    # line, where ggplot2's ribbon keys take twice that; in Giggly's points 17.28, 19.84, 28.35
    # and 56.69.
    test "gives each legend key room as wide as its line, as ggridges does" do
      ridges = Plot.new(@spread, %{x: :v, y: :g, fill: :g})

      ridgeline =
        @ridges
        |> Map.put("g", ~w(a a a b b b))
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :g, fill: :g})

      layers = [
        fn width -> GigRidges.geom_ridgeline(ridgeline, linewidth: width) end,
        fn width -> GigRidges.geom_density_ridges(ridges, bandwidth: 1, linewidth: width) end,
        fn width -> GigRidges.geom_density_ridges2(ridges, bandwidth: 1, linewidth: width) end
      ]

      for layer <- layers do
        sides =
          for width <- [6, 7, 10, 20] do
            width
            |> layer.()
            |> Giggly.to_svg()
            |> IO.iodata_to_binary()
            |> then(
              &Regex.scan(
                ~r/width='([0-9.]+)' height='([0-9.]+)' style='[^']*fill: #EBEBEB;'/,
                &1
              )
            )
            |> Enum.flat_map(fn
              [_key, side, side] -> [side]
              [_panel, _width, _height] -> []
            end)
            |> Enum.uniq()
          end

        assert sides == [["17.28"], ["19.84"], ["28.35"], ["56.69"]]

        glyphs = 6 |> layer.() |> Giggly.to_svg() |> IO.iodata_to_binary()

        assert length(
                 Regex.scan(~r/<rect [^>]*stroke: #000000[^>]*fill: #(F8766D|00BFC4)/, glyphs)
               ) == 2
      end
    end

    test "takes its mapping in its own call or the plot's, and no options" do
      plot = Plot.new(@spread, %{})

      plain = plot |> Plot.aes(%{x: :v, y: :g}) |> GigRidges.geom_density_ridges2()

      assert DataFrame.row_count(Giggly.layer_data(plain)) == 1024

      cut =
        @spread
        |> Map.put("r", List.duplicate(0.5, 13))
        |> Plot.new(%{})
        |> GigRidges.geom_density_ridges2(%{x: :v, y: :g, rel_min_height: :r})
        |> Giggly.layer_data()
        |> DataFrame.pull(:ymax)
        |> Enum.count(&is_number/1)

      assert cut < 1024
    end

    test "refuses what the density ridges' geom refuses, naming itself" do
      assert_raise ArgumentError, ~r/^GigRidges.geom_density_ridges2\/3 maps :scale to "g"/, fn ->
        @spread
        |> Plot.new(%{x: :v, y: :g, scale: :g})
        |> GigRidges.geom_density_ridges2()
        |> Giggly.layer_data()
      end

      assert_raise ArgumentError, ~r/height/, fn ->
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> Plot.layer(%{}, stat: :identity, geom: GigRidges.DensityRidgeline2)
        |> Giggly.layer_data()
      end
    end

    test "takes the density ridges' options and names itself in its refusals" do
      plot = Plot.new(@spread, %{x: :v, y: :g})

      frame =
        plot
        |> GigRidges.geom_density_ridges2(%{}, bandwidth: 1, scale: 1, panel_scaling: false)
        |> Giggly.layer_data()

      reach =
        frame
        |> DataFrame.pull(:ymax)
        |> Enum.zip_with(DataFrame.pull(frame, :ymin), &(&1 - &2))
        |> Enum.max()

      assert Float.round(reach, 9) == 1.0

      assert_raise ArgumentError, ~r/^GigRidges.geom_density_ridges2\/3 sets :shape/, fn ->
        GigRidges.geom_density_ridges2(plot, shape: 1)
      end
    end
  end

  # Each group's `columns`, the groups in order.
  defp by_group(frame, columns) do
    frame
    |> DataFrame.split(:group)
    |> Enum.sort()
    |> Enum.map(fn {_group, rows} -> Enum.map(columns, &DataFrame.pull(rows, &1)) end)
  end
end
