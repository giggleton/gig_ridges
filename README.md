# GigRidges

Ridgeline plots for [Giggly](https://github.com/giggleton/giggly), the grammar-of-graphics plotting
library for Elixir: ridges along `x`, one above each baseline, each group's distribution or series
drawn so the ridges overlap.

It is also a worked example of a Giggly plugin: stats, geoms and positions of its own, layer
functions built on `Giggly.Plot.layer/3`, geoms drawing by delegation to Giggly's ribbon, segment
and point geoms, and scales and a theme built from Giggly's public scale and theme functions.

## Installation

Add Giggly and GigRidges to your dependencies:

```elixir
def deps do
  [
    {:giggly, "~> 0.2.0"},
    {:gig_ridges, "~> 0.1.0"}
  ]
end
```

## Use

```elixir
GigDatasets.mpg()
|> Giggly.Plot.new(%{x: :hwy, y: :class, fill: :class})
|> GigRidges.geom_density_ridges(alpha: 0.7, rel_min_height: 0.01)
|> Giggly.to_svg()
```

- `GigRidges.geom_ridgeline/3` draws ridges of the heights a table gives: each group's ridge
  reaches `scale` times its `height` above its baseline `y`.
- `GigRidges.geom_vridgeline/3` draws them turned, up `y`: each ridge reaches `scale` times its
  `width` beyond its baseline `x`, cut off by `min_width:`.
- `GigRidges.geom_density_ridges/3` and `GigRidges.stat_density_ridges/3` estimate each group's
  density along `x` with one bandwidth each panel's groups share, and draw it so the panel's
  greatest density reaches the next baseline at a `scale:` of 1; their `scale:` is 1.8 unless
  given or mapped, so neighbouring ridges overlap.
- `GigRidges.geom_density_ridges2/3` draws the same ridges, each outlined round its whole border,
  its baseline too, not along its top alone.
- `GigRidges.geom_ridgeline_gradient/3` and `GigRidges.geom_density_ridges_gradient/3` draw
  those ridges with a fill that varies along each, as `%{fill: :x}` or
  `%{fill: {:after_stat, [:x]}}` maps one, in pieces of one fill each, outlined in it
  `gradient_lwd:` wide so the seams do not show.
- `GigRidges.stat_binline/3` counts each group in bins along `x` and draws the histogram's
  outline as a ridge, taking `binwidth:`, `bins:`, `center:`, `boundary:`, `breaks:`, `closed:`,
  `pad:` and `draw_baseline:`.
- `GigRidges.geom_density_line/3` draws a density over a baseline of 0 the way the ridges are
  drawn, filled grey70 and outlined along its top, taking Giggly's density options (`bw:`,
  `adjust:`, `kernel:`, `n:`, `trim:`, `bounds:`).

Each takes Giggly's options for the marks (`fill:`, `alpha:`, `colour:`, `linewidth:`,
`linetype:`, `position:`) beside its own: `scale:` for the ridges, with `min_height:` for the
ridgeline and `rel_min_height:`, a share of the layer's greatest height, for the density ridges,
each of which may be mapped instead, and `panel_scaling:` for the density ridges' heights; and
`bandwidth:`, `from:`, `to:` and `n:` for the density, whose rows a mapped `weight` weighs, with
`quantile_lines:`, `quantiles:` and `quantile_fun:` drawing a line up each ridge at each of its
group's quantiles, in the ridge's look or the `vline_color:`, `vline_width:` and `vline_linetype:`
given, `calc_ecdf:` writing each place's `ecdf` and quantile band without the lines, and
`jittered_points:` drawing each value as a point under its ridge, in the `point_shape:`,
`point_size:`, `point_stroke:`, `point_color:`, `point_fill:` and `point_alpha:` given. The
density ridges' geoms set each point up its ridge by a random share of its height there,
`GigRidges.PointsSina`, ggridges' `position_points_sina()`, from `rel_min:` to `rel_max:`, drawn
from `seed:`, unless given another `position:`, where `stat_density_ridges/3` leaves them on their
baselines; `position: {GigRidges.PointsJitter, ...}`, ggridges' `position_points_jitter()`, moves
each up to `width:` across and `height:` up or down from `yoffset:` above its baseline, with
`adjust_vlines:` running the quantile lines across that band; and `position:
{GigRidges.PointsRaincloud, ...}`, ggridges' `position_raincloud()`, drops each into a band
`height:` deep, `ygap:` below its baseline, as rain below a cloud.

`GigRidges.cyclical_scale/3`, `scale_fill_cyclical/2`, `scale_colour_cyclical/2` (or
`scale_color_cyclical/2`), `scale_alpha_cyclical/2`, `scale_linetype_cyclical/2`,
`scale_linewidth_cyclical/2` and `scale_size_cyclical/2` hand their `values:` to the ridges in
turn, starting again once they run out, as `scale_fill_cyclical(values: ["red", "blue"])` fills
them alternately, with no legend unless `guide: :legend` asks for one, its keys chosen by
`breaks:` and labelled by `labels:`. They are Giggly's manual scales, their values repeated.

`GigRidges.theme_ridges/2` draws everything but the marks as ggridges' `theme_ridges()` does:
nothing behind the marks, light grey grid lines and ticks, black text, the axes' titles at the
far ends of their axes and each ridge's name on its baseline, taking `font_size:`,
`font_family:`, `line_size:`, `grid:` and `center_axis_labels:`. Given a plot it replaces its
theme, and given its options alone it returns the theme, as Giggly's complete themes do.

## Relationship to ggridges

The idea of the ridgeline plot, and the names of these functions and their options, follow R's
ggridges package, so they read familiarly to its users. GigRidges is an independent
implementation from ggridges' documented behaviour, its defaults and computed values checked
against what ggridges 0.5.7 computes: it contains none of ggridges' code, text or data.

## License

MIT. See `LICENSE`.
