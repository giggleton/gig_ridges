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

    test "refuses options it does not take and mistakes, naming itself" do
      plot = Plot.new(@ridges, %{x: :x, y: :y, height: :h})

      assert_raise NimbleOptions.ValidationError, ~r/expected a number above 0/, fn ->
        GigRidges.geom_ridgeline(plot, scale: 0)
      end

      assert_raise ArgumentError, ~r/^GigRidges.geom_ridgeline\/3 sets :shape/, fn ->
        GigRidges.geom_ridgeline(plot, shape: 1)
      end

      assert_raise ArgumentError, ~r/^GigRidges.geom_ridgeline\/3 needs :height/, fn ->
        GigRidges.geom_ridgeline(Plot.new(@ridges, %{x: :x, y: :y}))
      end
    end
  end

  describe "geom_density_ridges/3" do
    setup do
      %{plot: Plot.new(GigDatasets.mpg(), %{x: :hwy, y: :class})}
    end

    # R 4.6.1's `density()` of mpg's compact class, `bw.nrd0()` of every class's `hwy` together,
    # read from three bandwidths below the least to three above the greatest at 512 places: its
    # greatest density 0.120064561783484, at 27.1205568390837, and its 1st, 100th, 256th, 400th
    # and 512th values.
    test "estimates each group's density with the bandwidth of every group's rows together", %{
      plot: plot
    } do
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

      assert_in_delta peak, 0.120064561783484, 1.0e-12
      assert_in_delta place, 27.1205568390837, 1.0e-9

      expected = [
        0.0,
        2.19328222641197e-07,
        0.11741783853665,
        0.00176170874127846,
        5.27686215448223e-05
      ]

      got = Enum.map([0, 99, 255, 399, 511], fn index -> Enum.at(densities, index) end)

      Enum.zip_with(got, expected, fn value, wanted -> assert_in_delta value, wanted, 1.0e-12 end)
    end

    test "scales the layer's greatest density to the spacing between baselines", %{plot: plot} do
      frame = plot |> GigRidges.geom_density_ridges() |> Giggly.layer_data()
      assert frame |> DataFrame.pull(:height) |> Enum.max() == 1.0
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
