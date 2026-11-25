# GigRidges

Ridgeline plots for [Giggly](https://github.com/giggleton/giggly), the grammar-of-graphics plotting
library for Elixir: ridges along `x`, one above each baseline, each group's distribution or series
drawn so the ridges overlap.

It is also a worked example of a Giggly plugin: a stat and a geom of its own, layer functions of
its own built on `Giggly.Plot.layer/3`, and a geom drawing by delegation to Giggly's ribbon.

## Installation

GigRidges needs Giggly's plugin API, which is not yet released. Until it is, depend on Giggly and
GigRidges by path:

```elixir
def deps do
  [
    {:giggly, path: "../giggly"},
    {:gig_ridges, path: "../gig_ridges"}
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
- `GigRidges.geom_density_ridges/3` and `GigRidges.stat_density_ridges/3` estimate each group's
  density along `x` with one bandwidth each panel's groups share, and draw it so the panel's
  greatest density reaches the next baseline at a `scale:` of 1; their `scale:` is 1.8 unless
  given or mapped, so neighbouring ridges overlap.

Each takes Giggly's options for the marks (`fill:`, `alpha:`, `colour:`, `linewidth:`,
`linetype:`, `position:`) beside its own: `scale:` for the ridges, with `min_height:` for the
ridgeline and `rel_min_height:`, a share of the layer's greatest height, for the density ridges,
each of which may be mapped instead, and `bandwidth:` and `panel_scaling:` for the density.

## Relationship to ggridges

The idea of the ridgeline plot, and the names of these functions and their options, follow R's
ggridges package, so they read familiarly to its users. GigRidges is an independent
implementation from ggridges' documented behaviour, its defaults and computed values checked
against what ggridges 0.5.7 computes: it contains none of ggridges' code, text or data.

## Licence

MIT. See `LICENSE`.
