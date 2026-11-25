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

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_ridgeline(aes(linewidth = w))`, w "thin",
    # "wide" and NA on three ridges: three keys, the missing one's line too, each the theme's least,
    # 17.345 TeX points, 17.28 in Giggly's.
    test "gives a key whose line width is missing the theme's least room" do
      ridges = %{
        "x" => [1, 2, 3, 1, 2, 3, 1, 2, 3],
        "y" => [0, 0, 0, 1, 1, 1, 2, 2, 2],
        "h" => [0.2, 0.9, 0.3, 0.5, 0.4, 0.1, 0.3, 0.3, 0.3],
        "w" => ["thin", "thin", "thin", "wide", "wide", "wide", nil, nil, nil]
      }

      sides =
        ridges
        |> Plot.new(%{x: :x, y: :y, height: :h, group: :y, linewidth: :w})
        |> GigRidges.geom_ridgeline()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()
        |> then(
          &Regex.scan(~r/width='([0-9.]+)' height='([0-9.]+)' style='[^']*fill: #EBEBEB;'/, &1)
        )
        |> Enum.flat_map(fn
          [_key, side, side] -> [side]
          [_panel, _width, _height] -> []
        end)

      assert sides == ["17.28", "17.28", "17.28"]
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

  describe "geom_vridgeline/3" do
    # Ridges up y: two on baselines x 0 and 1, five points each, one width below 0.
    @upright %{
      "x" => List.duplicate(0, 5) ++ List.duplicate(1, 5),
      "y" => [1, 2, 3, 4, 5, 1, 2, 3, 4, 5],
      "w" => [0.2, -0.5, 1, 0.9, 0.3, 0.5, 0.4, 0.1, 0.3, 0.6]
    }

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_vridgeline()` over widths 0.2, 0.9 and 0.3 on
    # x 0 and 0.5, 0.4 and 0.1 on x 1: `xmin` each point's x and `xmax` x plus its width; filled
    # grey80, where its other ridgelines are grey70, outlined black 0.5 mm wide along the outer edge
    # alone, each ridge a polygon of 6 points unoutlined and a line of 3, the ridge of the greater
    # baseline drawn first.
    test "reaches each width beyond its baseline x, drawing the farthest baseline first" do
      plot =
        %{
          "x" => [0, 0, 0, 1, 1, 1],
          "y" => [1, 2, 3, 1, 2, 3],
          "w" => [0.2, 0.9, 0.3, 0.5, 0.4, 0.1]
        }
        |> Plot.new(%{x: :x, y: :y, width: :w, group: :x})
        |> GigRidges.geom_vridgeline()

      frame = Giggly.layer_data(plot)
      assert DataFrame.pull(frame, :xmin) == [0, 0, 0, 1, 1, 1]
      assert DataFrame.pull(frame, :xmax) == [0.2, 0.9, 0.3, 1.5, 1.4, 1.1]

      looks =
        for column <- [:fill, :color, :linewidth],
            do: frame |> DataFrame.pull(column) |> Enum.uniq()

      assert looks == [["#CCCCCC"], ["#000000"], [0.5]]

      drawn =
        plot
        |> Plot.theme_void()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()
        |> then(&Regex.scan(~r/<(polygon|polyline) points='([^']*)' style='([^']*)'/, &1))
        |> Enum.map(fn [_element, tag, points, style] ->
          places = String.split(points, " ", trim: true)

          {tag, length(places), places |> hd() |> String.split(",") |> hd() |> String.to_float(),
           style}
        end)

      assert [
               {"polygon", 6, _, unoutlined},
               {"polyline", 3, farther, line},
               {"polygon", 6, _, unoutlined},
               {"polyline", 3, nearer, line}
             ] = drawn

      assert unoutlined =~ "stroke: none" and line =~ "stroke-width: 1.07; stroke: #000000"
      assert farther > nearer
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, over @upright, counting each ridge's drawn points
    # from x 0: unmapped, 4 and 5, the width below 0 left out; `min_width = 0.3`, 3 and 4; and
    # `aes(min_width = m)`, 0.5 on x 0 and NA on x 1, 2 and 5, a missing cut-off none; and
    # `aes(scale = s)`, NA at x 1's first point and 2 for the rest, leaves that point out.
    test "leaves out a point below its min_width, given or mapped, and one of no scale" do
      kept = fn data, mapping, options ->
        data
        |> Plot.new(Map.merge(%{x: :x, y: :y, width: :w, group: :x}, mapping))
        |> GigRidges.geom_vridgeline(options)
        |> Giggly.layer_data()
        |> by_group([:xmax])
        |> Enum.map(fn [xmax] -> Enum.count(xmax, &is_number/1) end)
      end

      assert kept.(@upright, %{}, []) == [4, 5]
      assert kept.(@upright, %{}, min_width: 0.3) == [3, 4]

      cut = Map.put(@upright, "m", List.duplicate(0.5, 5) ++ List.duplicate(nil, 5))
      assert kept.(cut, %{min_width: :m}, []) == [2, 5]

      scaled = Map.put(@upright, "s", [1, 1, 1, 1, 1, nil, 2, 2, 2, 2])

      xmax =
        scaled
        |> Plot.new(%{x: :x, y: :y, width: :w, group: :x, scale: :s})
        |> GigRidges.geom_vridgeline()
        |> Giggly.layer_data()
        |> DataFrame.pull(:xmax)

      assert xmax == [0.2, nil, 1.0, 0.9, 0.3, nil, 1.8, 1.2, 1.6, 2.2]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_vridgeline(aes(fill = f))`: its legend keys
    # drawn as its other ridgelines' are, but taking the ribbon's room, twice as wide as their
    # line, 56.906 TeX points at a `linewidth` of 10, 56.69 in Giggly's, where its other
    # ridgelines' take 28.453; at 0.5, the theme's least, 17.28.
    test "gives each legend key the ribbon's room, twice as wide as its line" do
      plot =
        @upright
        |> Map.put("f", List.duplicate("a", 5) ++ List.duplicate("b", 5))
        |> Plot.new(%{x: :x, y: :y, width: :w, group: :x, fill: :f})

      svg = fn width ->
        plot
        |> GigRidges.geom_vridgeline(linewidth: width)
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()
      end

      sides = fn width ->
        width
        |> svg.()
        |> then(
          &Regex.scan(~r/width='([0-9.]+)' height='([0-9.]+)' style='[^']*fill: #EBEBEB;'/, &1)
        )
        |> Enum.flat_map(fn
          [_key, side, side] -> [side]
          [_panel, _width, _height] -> []
        end)
        |> Enum.uniq()
      end

      assert {sides.(0.5), sides.(10)} == {["17.28"], ["56.69"]}

      assert length(
               Regex.scan(~r/<rect [^>]*stroke: #000000[^>]*fill: #(F8766D|00BFC4)/, svg.(0.5))
             ) == 2
    end

    test "needs a width, and refuses one of text and the ridgeline's min_height, naming itself" do
      plot = Plot.new(@upright, %{x: :x, y: :y, group: :x})

      assert_raise ArgumentError, ~r/^GigRidges.geom_vridgeline\/3.*width/, fn ->
        plot |> GigRidges.geom_vridgeline() |> Giggly.layer_data()
      end

      assert_raise ArgumentError, ~r/^GigRidges.geom_vridgeline\/3 maps :width to "f"/, fn ->
        @upright
        |> Map.put("f", List.duplicate("a", 10))
        |> Plot.new(%{x: :x, y: :y, width: :f})
        |> GigRidges.geom_vridgeline()
        |> Giggly.layer_data()
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:min_height\]/, fn ->
        GigRidges.geom_vridgeline(plot, min_height: 0.1)
      end
    end
  end

  describe "geom_density_line/3" do
    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_density_line(bw = 1, n = 5)` over @spread's
    # values: ggplot2's density, `y` and `ymax` 0.031011684, 0.020018223, 0.184055119, 0.020018223
    # and 0.031011684 at x -9 to 9, `ymin` 0; filled grey70 and outlined black 0.5 mm wide along
    # its top alone, a polygon of 10 points unoutlined and a line of 5, where ggplot2's
    # `geom_density()` is filled with nothing; and grouped by `fill`, a's peak 0.330854 and b's
    # 0.0582277.
    test "draws a density over a baseline of 0 the way the ridges are drawn" do
      close? = fn read, golden ->
        Enum.all?(Enum.zip_with(read, golden, &abs(&1 - &2)), &(&1 < 1.0e-8))
      end

      plot = Plot.new(@spread, %{x: :v})
      frame = plot |> GigRidges.geom_density_line(bw: 1, n: 5) |> Giggly.layer_data()

      golden = [0.031011684, 0.020018223, 0.184055119, 0.020018223, 0.031011684]
      assert DataFrame.pull(frame, :x) == [-9.0, -4.5, 0.0, 4.5, 9.0]

      assert close?.(DataFrame.pull(frame, :y), golden) and
               close?.(DataFrame.pull(frame, :ymax), golden)

      assert DataFrame.pull(frame, :ymin) == List.duplicate(0, 5)

      looks =
        for column <- [:fill, :color, :linewidth],
            do: frame |> DataFrame.pull(column) |> Enum.uniq()

      assert looks == [["#B3B3B3"], ["#000000"], [0.5]]

      drawn =
        plot
        |> GigRidges.geom_density_line(bw: 1, n: 5)
        |> Plot.theme_void()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()
        |> then(&Regex.scan(~r/<(polygon|polyline) points='([^']*)' style='([^']*)'/, &1))
        |> Enum.map(fn [_element, tag, points, style] ->
          {tag, length(String.split(points, " ", trim: true)), style}
        end)

      assert [{"polygon", 10, unoutlined}, {"polyline", 5, line}] = drawn
      assert unoutlined =~ "stroke: none" and unoutlined =~ "fill: #B3B3B3"
      assert line =~ "stroke-width: 1.07; stroke: #000000"

      peaks =
        @spread
        |> Plot.new(%{x: :v, fill: :g})
        |> GigRidges.geom_density_line(bw: 1, n: 5)
        |> Giggly.layer_data()
        |> by_group([:ymax])
        |> Enum.map(fn [ymax] -> ymax |> Enum.max() |> Float.round(6) end)

      assert peaks == [0.330854, 0.058228]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3: `aes(y = after_stat(count))`, `n = 3`, reaches
    # 0.403152, 2.392717 and 0.403152; and its legend keys the ridgelines', room as wide as their
    # line, 28.453 TeX points at a `linewidth` of 10, 28.35 in Giggly's, the theme's least, 17.28,
    # at 0.5. Departure: ggridges lists `scale` and `min_height` among its aesthetics, but neither
    # changes what it draws; given, they are refused.
    test "reads another of the stat's variables, keys as the ridges, and takes no scale" do
      ymax =
        @spread
        |> Plot.new(%{x: :v, y: {:after_stat, [:count]}})
        |> GigRidges.geom_density_line(bw: 1, n: 3)
        |> Giggly.layer_data()
        |> DataFrame.pull(:ymax)
        |> Enum.map(&Float.round(&1, 6))

      assert ymax == [0.403152, 2.392717, 0.403152]

      plot = Plot.new(@spread, %{x: :v, fill: :g})

      sides = fn width ->
        plot
        |> GigRidges.geom_density_line(bw: 1, linewidth: width)
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()
        |> then(
          &Regex.scan(~r/width='([0-9.]+)' height='([0-9.]+)' style='[^']*fill: #EBEBEB;'/, &1)
        )
        |> Enum.flat_map(fn
          [_key, side, side] -> [side]
          [_panel, _width, _height] -> []
        end)
        |> Enum.uniq()
      end

      assert {sides.(0.5), sides.(10)} == {["17.28"], ["28.35"]}

      glyphs =
        plot |> GigRidges.geom_density_line(bw: 1) |> Giggly.to_svg() |> IO.iodata_to_binary()

      assert length(Regex.scan(~r/<rect [^>]*stroke: #000000[^>]*fill: #(F8766D|00BFC4)/, glyphs)) ==
               2

      for {option, value} <- [scale: 2, min_height: 0.1] do
        assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:#{option}\]/, fn ->
          GigRidges.geom_density_line(plot, [{option, value}])
        end
      end
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `geom_density_line(alpha = 0.5, colour = "red",
    # linetype = "dashed")`: each set for every point, and `layer_data()` holding no `height`, the
    # density in `y`.
    test "takes an alpha, colour and line type set for every point, and keeps no height" do
      plot = Plot.new(@spread, %{x: :v})
      looks = [:alpha, :color, :linetype]

      read = fn options ->
        frame =
          plot |> GigRidges.geom_density_line([bw: 1, n: 5] ++ options) |> Giggly.layer_data()

        {Enum.map(looks, &(frame |> DataFrame.pull(&1) |> Enum.uniq())), DataFrame.names(frame)}
      end

      {[_alpha, _color, [solid]], _names} = read.([])
      {[alpha, color, [dashed]], names} = read.(alpha: 0.5, colour: "red", linetype: :dashed)

      assert {alpha, color} == {[0.5], ["#FF0000"]}
      assert dashed != solid
      refute :height in names
    end

    test "takes its mapping in its own call, names itself in its refusals, and needs an x" do
      own =
        @spread
        |> Plot.new(%{})
        |> GigRidges.geom_density_line(%{x: :v}, n: 7)
        |> Giggly.layer_data()

      assert DataFrame.row_count(own) == 7

      assert_raise ArgumentError, ~r/^GigRidges.geom_density_line\/3 sets :shape/, fn ->
        GigRidges.geom_density_line(Plot.new(@spread, %{x: :v}), shape: 1)
      end

      assert_raise ArgumentError, ~r/^GigRidges.geom_density_line\/3.*:x/, fn ->
        @spread |> Plot.new(%{}) |> GigRidges.geom_density_line() |> Giggly.layer_data()
      end
    end
  end

  describe "stat_binline/3" do
    # Group a of @spread's binned ridges, each column's values, its places rounded.
    defp binned(options, columns \\ [:x, :count]) do
      [a | _b] =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(options)
        |> Giggly.layer_data()
        |> by_group(columns)

      Enum.map(a, fn values -> Enum.map(values, &((is_float(&1) && Float.round(&1, 5)) || &1)) end)
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `stat_binline(bins = 4)` over @spread: every group
    # in the panel's bins, 6 wide over -9 to 9, edged half a width off, padded with an empty bin
    # either side, each bin two ends, its lower edge and a hundred-thousandth of its width short of
    # its upper; group a counting 4 in (-6, 0] and 2 in (0, 6], its density the count over the
    # width and 6 values; drawn by the density ridges' geom, b reaching 2.77143 and 2.38571.
    test "counts each group in the panel's bins, a step at each, padded either side" do
      assert binned(bins: 4) == [
               [
                 -18.0,
                 -12.00006,
                 -12.0,
                 -6.00006,
                 -6.0,
                 -6.0e-5,
                 0.0,
                 5.99994,
                 6.0,
                 11.99994,
                 12.0,
                 17.99994
               ],
               [0, 0, 0, 0, 4, 4, 2, 2, 0, 0, 0, 0]
             ]

      [density, ncount, ndensity] = binned([bins: 4], [:density, :ncount, :ndensity])

      assert density == [
               0.0,
               0.0,
               0.0,
               0.0,
               0.11111,
               0.11111,
               0.05556,
               0.05556,
               0.0,
               0.0,
               0.0,
               0.0
             ]

      assert ncount == [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0]
      assert ndensity == ncount

      [_a, [b_ymax]] =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(bins: 4)
        |> Giggly.layer_data()
        |> by_group([:ymax])

      assert Enum.map(b_ymax, &Float.round(&1, 5)) ==
               [
                 2.0,
                 2.0,
                 2.77143,
                 2.77143,
                 2.77143,
                 2.77143,
                 2.77143,
                 2.77143,
                 2.38571,
                 2.38571,
                 2.0,
                 2.0
               ]

      assert @spread
             |> Plot.new(%{x: :v, y: :g})
             |> GigRidges.stat_binline()
             |> Giggly.layer_data()
             |> DataFrame.row_count() ==
               2 * 64
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, group a of @spread under `bins = 4`: `pad = FALSE`
    # drops the empty bins either side; `draw_baseline = FALSE` leaves the ends before the first
    # counted bin's, but the one beside it, and after the last's, but the one beside it, with no
    # count, density or height, their ncount 0.
    test "pads either side unless pad: false, and runs no baseline under draw_baseline: false" do
      assert binned(bins: 4, pad: false) ==
               [
                 [-12.0, -6.00006, -6.0, -6.0e-5, 0.0, 5.99994, 6.0, 11.99994],
                 [0, 0, 4, 4, 2, 2, 0, 0]
               ]

      [count, height, ncount] =
        binned([bins: 4, draw_baseline: false], [:count, :height, :ncount])

      assert count == [nil, nil, nil, 0, 4, 4, 2, 2, 0, nil, nil, nil]
      assert Enum.map(height, &is_nil/1) == Enum.map(count, &is_nil/1)
      assert Enum.all?(ncount, &is_number/1)

      assert binned(bins: 4, pad: false, draw_baseline: false) |> List.last() ==
               [nil, 0, 4, 4, 2, 2, 0, nil]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, group a of @spread: `binwidth = 5, closed = "left"`
    # and `binwidth = 5, center = 0` each bin from -17.5 to 17.5, 6 in [-2.5, 2.5); `boundary = 1`
    # from -14 to 16, 6 in (-4, 1]; `breaks = c(-10, -2, 2, 10)` 6 in (-2, 2], padded by bins as
    # wide as the first and the last, 8; and `breaks = c(-2, 0, 2)` counts a value outside none,
    # b's 1 in (-2, 0] its density 0.5, the count over its width and the one value counted.
    test "places bins by binwidth, center, boundary or breaks, closed either side" do
      quarters = [-17.5, -12.50005, -12.5, -7.50005, -7.5, -2.50005, -2.5, 2.49995, 2.5, 7.49995]
      wide = quarters ++ [7.5, 12.49995, 12.5, 17.49995]
      six = [0, 0, 0, 0, 0, 0, 6, 6, 0, 0, 0, 0, 0, 0]

      assert binned(binwidth: 5, closed: :left) == [wide, six]
      assert binned(binwidth: 5, center: 0) == [wide, six]

      assert binned(binwidth: 5, boundary: 1) == [
               [
                 -14.0,
                 -9.00005,
                 -9.0,
                 -4.00005,
                 -4.0,
                 0.99995,
                 1.0,
                 5.99995,
                 6.0,
                 10.99995,
                 11.0,
                 15.99995
               ],
               [0, 0, 0, 0, 6, 6, 0, 0, 0, 0, 0, 0]
             ]

      assert binned(breaks: [-10, -2, 2, 10]) == [
               [-18.0, -10.00008, -10.0, -2.00008, -2.0, 1.99996, 2.0, 9.99992, 10.0, 17.99992],
               [0, 0, 0, 0, 6, 6, 0, 0, 0, 0]
             ]

      [_a, [count, density]] =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(breaks: [-2, 0, 2])
        |> Giggly.layer_data()
        |> by_group([:count, :density])

      assert {count, density} ==
               {[0, 0, 1, 1, 0, 0, 0, 0], [0.0, 0.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0]}
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, `stat_binline(bins = 4) + facet_wrap(~g, scales =
    # "free_x")` over @spread: each panel binned across its own x, a's from -2 to 1.99999 and b's
    # from -18 to 17.99994, 12 ends each; under fixed scales both from -18.
    test "bins each panel across its own x" do
      spans = fn scales ->
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(bins: 4)
        |> Plot.facet_wrap(:g, scales: scales)
        |> Giggly.layer_data()
        |> DataFrame.split(:panel)
        |> Enum.sort()
        |> Enum.map(fn {_panel, rows} ->
          {low, high} = rows |> DataFrame.pull(:x) |> Enum.min_max()
          {Float.round(low, 5), Float.round(high, 5), DataFrame.row_count(rows)}
        end)
      end

      assert spans.(:free_x) == [{-2.0, 1.99999, 12}, {-18.0, 17.99994, 12}]
      assert spans.(:fixed) == [{-18.0, 17.99994, 12}, {-18.0, 17.99994, 12}]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, group a of @spread, `breaks = c(-2, 0, 2)`: its 0s,
    # on a break, in (-2, 0] closed on the right, 4 there and 2 in (0, 2], and in [0, 2) closed
    # on the left, 2 in [-2, 0) and 4 there; under `breaks = c(-2, 0, 1)` closed on the left its
    # 1, on the last break, in the last bin, [0, 1], 4 there; the breaks given out of order binned
    # as sorted.
    test "puts a value on a break in the bin closed on its side" do
      places = [-4.0, -2.00002, -2.0, -2.0e-5, 0.0, 1.99998, 2.0, 3.99998]

      assert binned(breaks: [-2, 0, 2], closed: :right) == [places, [0, 0, 4, 4, 2, 2, 0, 0]]
      assert binned(breaks: [-2, 0, 2], closed: :left) == [places, [0, 0, 2, 2, 4, 4, 0, 0]]
      assert binned(breaks: [2, -2, 0]) == [places, [0, 0, 4, 4, 2, 2, 0, 0]]
      assert binned(breaks: [-2, 0, 1], closed: :left) |> List.last() == [0, 0, 2, 2, 4, 4, 0, 0]
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, group a of @spread: `bins = 4, center = 0` bins 6
    # wide from -15, 6 in (-3, 3]; `boundary = 0` from -18, 4 and 2 either side of 0; `boundary = 1`,
    # on which neither limit falls, from -17; `bins = 1` one bin 18 wide over -9 to 9; `binwidth =
    # 5, center = 1` from -16.5; b under `bins = 4, boundary = 3`, both limits on the boundary, bins
    # 4.5 wide from -15; b under `binwidth = 3, boundary = 0`, its 9 on a break, its last
    # bin (6, 9]; six values all 2 under `bins = 4`, bins 0.1 wide, and with `boundary = 2` one bin
    # from 2, the one break the limits reach given a second; and over `scale_x_log10()`,
    # values 1 to 100, `breaks = c(1, 10, 100)` put through the scale, bins edged at 0, 1 and 2,
    # and `breaks = c(-1, 10)`, one break left, no bins and nothing drawn.
    test "places bins by bins and center or boundary, over any axis" do
      assert binned(bins: 4, center: 0) == [
               [-15.0, -9.00006, -9.0, -3.00006, -3.0, 2.99994, 3.0, 8.99994, 9.0, 14.99994],
               [0, 0, 0, 0, 6, 6, 0, 0, 0, 0]
             ]

      assert binned(bins: 4, boundary: 0) |> List.last() == [0, 0, 0, 0, 4, 4, 2, 2, 0, 0, 0, 0]

      assert binned(bins: 4, boundary: 1) |> hd() == [
               -17.0,
               -11.00006,
               -11.0,
               -5.00006,
               -5.0,
               0.99994,
               1.0,
               6.99994,
               7.0,
               12.99994,
               13.0,
               18.99994
             ]

      assert binned(bins: 1) == [
               [-27.0, -9.00018, -9.0, 8.99982, 9.0, 26.99982],
               [0, 0, 6, 6, 0, 0]
             ]

      [_a, [on_x, on_count]] =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(bins: 4, boundary: 3)
        |> Giggly.layer_data()
        |> by_group([:x, :count])

      edges = Enum.flat_map([-15, -10.5, -6, -1.5, 3, 7.5, 12], &[&1, &1 + 4.5 - 4.5e-5])
      assert Enum.all?(Enum.zip_with(on_x, edges, &abs(&1 - &2)), &(&1 < 1.0e-9))
      assert on_count == [0, 0, 2, 2, 1, 1, 2, 2, 1, 1, 1, 1, 0, 0]

      assert binned(binwidth: 5, center: 1) |> hd() |> hd() == -16.5

      [_a, [b_x, b_count]] =
        @spread
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(binwidth: 3, boundary: 0)
        |> Giggly.layer_data()
        |> by_group([:x, :count])

      assert {hd(b_x), b_x |> List.last() |> Float.round(5)} == {-12.0, 11.99997}
      assert b_count == [0, 0, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0]

      [[narrow, count]] =
        %{"v" => List.duplicate(2, 6), "g" => List.duplicate("a", 6)}
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(bins: 4)
        |> Giggly.layer_data()
        |> by_group([:x, :count])

      assert {Enum.map(narrow, &Float.round(&1, 5)), count} ==
               {[1.85, 1.95, 1.95, 2.05, 2.05, 2.15], [0, 0, 6, 6, 0, 0]}

      [[edged, edged_count]] =
        %{"v" => List.duplicate(2, 6), "g" => List.duplicate("a", 6)}
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(bins: 4, boundary: 2)
        |> Giggly.layer_data()
        |> by_group([:x, :count])

      assert {Enum.map(edged, &Float.round(&1, 6)), edged_count} ==
               {[1.9, 1.999999, 2.0, 2.099999, 2.1, 2.199999], [0, 0, 6, 6, 0, 0]}

      [[logged, logged_count]] =
        %{"v" => [1, 2, 3, 10, 20, 30, 100], "g" => List.duplicate("a", 7)}
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(breaks: [1, 10, 100])
        |> Plot.scale_x_log10()
        |> Giggly.layer_data()
        |> by_group([:x, :count])

      assert {Enum.map(logged, &Float.round(&1, 5)), logged_count} ==
               {[-1.0, -1.0e-5, 0.0, 0.99999, 1.0, 1.99999, 2.0, 2.99999],
                [0, 0, 4, 4, 3, 3, 0, 0]}

      none =
        %{"v" => [1, 2, 3, 10, 20, 30, 100], "g" => List.duplicate("a", 7)}
        |> Plot.new(%{x: :v, y: :g})
        |> GigRidges.stat_binline(breaks: [-1, 10])
        |> Plot.scale_x_log10()
        |> Giggly.layer_data()

      assert DataFrame.row_count(none) == 0
    end

    # Golden: ggridges 0.5.7 on ggplot2 4.0.3, b of @spread under `breaks = c(-2, -1.5)`, none of
    # its values counted: its counts 0, its density, shares and height NaN, so it draws nothing;
    # under `draw_baseline = FALSE` its counts NA too.
    test "draws no ridge for a group with nothing counted" do
      b = fn options ->
        [_a, [count, density, ncount, height]] =
          @spread
          |> Plot.new(%{x: :v, y: :g})
          |> GigRidges.stat_binline(options)
          |> Giggly.layer_data()
          |> by_group([:count, :density, :ncount, :height])

        Enum.map([count, density, ncount, height], &Enum.uniq/1)
      end

      assert b.(breaks: [-2, -1.5]) == [[0], [nil], [nil], [nil]]
      assert b.(breaks: [-2, -1.5], draw_baseline: false) == [[nil], [nil], [nil], [nil]]
    end

    test "maps a height to any of its variables, and keeps none of its gathering" do
      for variable <- [:count, :density, :ncount, :ndensity, :height, :xmin, :xmax, :width] do
        frame =
          @spread
          |> Plot.new(%{x: :v, y: :g, height: {:after_stat, [variable]}})
          |> GigRidges.stat_binline(bins: 4)
          |> Giggly.layer_data()

        assert DataFrame.pull(frame, :height) == DataFrame.pull(frame, variable)
      end

      for layered <- [&GigRidges.stat_binline(&1, bins: 4), &GigRidges.stat_density_ridges/1] do
        names =
          @spread
          |> Plot.new(%{x: :v, y: :g})
          |> layered.()
          |> Giggly.layer_data()
          |> DataFrame.names()

        refute :xs in names or :ws in names
      end
    end

    test "draws no rows for a layer of no values, in the columns it would have" do
      empty = %{"v" => [nil, nil, nil], "g" => ~w(a a a)}

      for {layered, computed} <- [
            {&GigRidges.stat_binline/1,
             [:xmin, :xmax, :width, :count, :density, :ncount, :ndensity]},
            {&GigRidges.stat_density_ridges/1, [:density, :ndensity]}
          ] do
        frame = empty |> Plot.new(%{x: :v, y: :g}) |> layered.() |> Giggly.layer_data()
        assert DataFrame.row_count(frame) == 0
        assert Enum.all?([:x, :height | computed], &(&1 in DataFrame.names(frame)))
      end
    end

    test "refuses a center beside a boundary, and bins it cannot cut, naming itself" do
      plot = Plot.new(@spread, %{x: :v, y: :g})

      assert_raise ArgumentError, ~r/^GigRidges.stat_binline\/3 takes center: or boundary:/, fn ->
        GigRidges.stat_binline(plot, center: 0, boundary: 1)
      end

      refusals = [
        binwidth: -1,
        binwidth: 0,
        bins: 0,
        breaks: [1],
        breaks: [1, 1],
        breaks: [1, :b],
        center: :middle,
        closed: :middle
      ]

      for {option, value} <- refusals do
        assert_raise NimbleOptions.ValidationError, ~r/:#{option}/, fn ->
          GigRidges.stat_binline(plot, [{option, value}])
        end
      end

      assert_raise ArgumentError, ~r/more than 1,000,000 bins/, fn ->
        plot |> GigRidges.stat_binline(binwidth: 1.0e-6) |> Giggly.layer_data()
      end

      assert_raise ArgumentError, ~r/^GigRidges.stat_binline\/3 maps :x to "g"/, fn ->
        @spread |> Plot.new(%{x: :g, y: :g}) |> GigRidges.stat_binline() |> Giggly.layer_data()
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
