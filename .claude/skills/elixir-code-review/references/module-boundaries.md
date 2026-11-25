# Module boundaries

**Applies to:** `lib/**/*.ex`.

## The rule

gig_ridges is one small library with one API module, `GigRidges`: its layer functions are what a
user calls. The stat and geom modules beneath it (`GigRidges.DensityRidges`, `GigRidges.Binline`,
`GigRidges.Ridgeline`, `GigRidges.DensityRidgeline`, `GigRidges.DensityRidgeline2`,
`GigRidges.VRidgeline`, `GigRidges.DensityLine`) are what those functions hand Giggly, with
Giggly's own stats named by atom (`:identity`, `:density`); `GigRidges.KernelDensity`,
`GigRidges.Binning` and `GigRidges.Groups` are internal (`@moduledoc false`). Toward
Giggly, gig_ridges is a plugin, and uses only Giggly's documented plugin API: the behaviours it
adopts (`Giggly.Stat`, `Giggly.Geom`), and the modules and functions Giggly documents for plugins.

Nothing checks this but the review. gig_ridges has no `use Boundary`, and Giggly's boundary
exports everything, so a call into a Giggly module or function that is `@moduledoc false` or
`@doc false` compiles cleanly and breaks on a Giggly release that changes it.

## Findings

### 1. Reaching into Giggly's internals — High

A call into a Giggly module or function that Giggly does not document — `@moduledoc false`, `@doc
false`, or a struct's fields read where Giggly offers no accessor — or a dependence on how Giggly
behaves inside a stage that its documentation does not promise.

```elixir
# in GigRidges.Ridgeline — finding
Giggly.Assembly.Internal.place(frame)
```

Before filing, open the Giggly module in the path dependency (`mix.exs` names it) and check what it
documents. If what gig_ridges needs has no documented way in, the finding says so, and the fix is
a request to Giggly's plugin API — Giggly is worked on in its own session, never patched from here
— not the call.

### 2. Logic in the wrong module — Medium

A rule that belongs to one module computed in another: a density detail worked out in the geom, a
drawing detail in the stat, or the API module's layer function doing more than naming the stat
and geom and passing options through to `Giggly.Plot.layer/3`. The consequence to point at is
the one in this library: testable only through a whole plot, or computed twice.

### 3. Circular dependencies between modules — Medium

Two gig_ridges modules each calling the other. Report once with both directions named. The fix is
usually passing data in rather than calling back.

### 4. A pure function that is no longer pure — High

Every gig_ridges function is pure: a stat or geom callback computes from its arguments, as Giggly's
plugin behaviours require, and the mutation runner rests on it (`warm.exs`'s opening comment). A
clock read, a config read (`Application.get_env`), unseeded randomness, a process, ETS or
persistent term, or IO is a finding; so is an Nx call that reads the process's default backend
instead of naming one. The fix is the same every time: take the value as an argument or an option.

## Not a finding

- **Calling Giggly's documented API.** `Giggly.Plot.layer/3`, `Giggly.DataFrame` functions, the
  callbacks of `Giggly.Stat` and `Giggly.Geom`, delegating a draw to a documented geom: this is
  the design. The most likely false positive in the file.
- **Passing Giggly's structs around.** Receiving a frame and reading it through `Giggly.DataFrame`
  is a value being used, not a boundary being crossed.
- **The stat and geom modules being public.** Each is named in its layer's `stat:`/`geom:`, so a
  user may reach them; their moduledocs say what they are.
- **Test files.** Tests legitimately reach through `Giggly.layer_data/1` and the like. Don't review
  `test/` under this rule.
- **A documented exception.** A comment explaining why an internal is used, approved by Steve, is
  a decision already made; note it in one line at most.

## Judgment calls

The question that resolves most cases: **would this still compile and pass its tests if Giggly
changed how something it does not document is implemented?** The answer should be yes.
