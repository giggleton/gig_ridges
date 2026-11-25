defmodule GigRidgesTest do
  use ExUnit.Case, async: true

  doctest GigRidges

  alias Giggly.{DataFrame, Plot}

  @ridges %{
    "x" => [1, 2, 3, 1, 2, 3],
    "y" => [0, 0, 0, 1, 1, 1],
    "h" => [0.2, 0.9, 0.3, 0.5, 0.4, 0.1]
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

    test "leaves out a point below the cut-off, min_height or rel_min_height of the greatest" do
      plot = Plot.new(@ridges, %{x: :x, y: :y, height: :h, group: :y})

      by_height = plot |> GigRidges.geom_ridgeline(min_height: 0.3) |> Giggly.layer_data()
      assert DataFrame.pull(by_height, :ymax) == [nil, 0.9, 0.3, 1.5, 1.4, nil]

      by_share = plot |> GigRidges.geom_ridgeline(rel_min_height: 0.5) |> Giggly.layer_data()
      assert DataFrame.pull(by_share, :ymax) == [nil, 0.9, nil, 1.5, nil, nil]
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

    test "takes the ridgeline's options as given, every ridge's", %{plot: plot} do
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
end
