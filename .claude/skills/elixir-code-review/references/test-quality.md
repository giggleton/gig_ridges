# Test quality

**Applies to:** `test/**/*.exs`, `test/support/**`.

A test earns its place by **naming a bug it would catch**. If you can't say what plausible
regression would make it fail — while a correct implementation passes — it's weight, not
coverage. `mix quality` runs the suite with `--warnings-as-errors` and credo strict, which polices
the mechanical layer; this check is the judgment calls a linter can't make.

## 1. Right layer — test behavior where it lives

- A computation's matrix of cases (the density estimate, the bandwidth, the cut-offs, the scaling
  to the next baseline) is driven through the layer functions and read back with
  `Giggly.layer_data/1`, or through the internal module that owns it, with ordinary tests.
- A test through a rendered SVG asserts what only drawing can get wrong — the order ridges are
  drawn in, that a ridge is drawn at all — not a number `layer_data/1` already pins.

**Finding:** a rendered-output test re-checking, case by case, numbers a frame test pins. The fix
is usually deletion at the outer layer, not addition at the inner.

## 2. Assert the contract, not the incidentals

The question for every assertion: *would this still pass after a harmless refactor?*

- **Goldens are allowed, with a license plate.** A hardcoded computed value must be labeled
  `Golden:` and carry a comment naming what legitimately moves it and, ideally, the mutant it
  kills. An unlabeled magic number in an assertion is a finding. A value ggridges computes is
  ggridges' own output, observed by running it in Docker (the `giggly-r:ggplot2-4.0.3-ggridges`
  image), never worked out by hand from its source, which is GPL-2 and never read into this
  repository (CLAUDE.md, "ggridges"): choose inputs so each clause under test decides one example,
  and name R's and ggridges' versions in the label.
- **Match on text only where the text is the contract.** An error a caller matches on is
  contract: assert the exception and its datum, not the sentence. Never regex over a whole
  rendered SVG with layout in it — a reflow rewrites the test for nothing; find the element and
  assert its attribute.
- **A refute of text passes whenever that string is absent — so once the wording moves, it guards
  nothing.** Assert absence on the structure instead (the `nil` in a column, the empty list).

## 3. Duplication — layered on purpose vs. redundant by accident

Two tests of the same behavior are fine when each would catch a failure the other can't. They're
redundant when both fail for the same reason. Quick test: imagine one plausible bug — if it fails
both, one of them goes.

## 4. Deletion — tests must re-earn their keep after a change

When reviewing a diff that changes behavior, ask what the change *orphaned*:

- Behavior removed or moved ⇒ its tests move or die in the same diff.
- A test that would still pass with the feature deleted (run the mental mutant) is not covering
  that feature — fix it or remove it.
- A deleted or weakened test that was the only pin on an unchanged line is invisible to the
  mutation pass, which mutates only the lines a commit changed: name each deleted test's pin.
- **Never delete a test because it fails.** A red test is either a regression or a contract
  change; the review must say which, and only the latter licenses deletion.

## 5. Hygiene

- `async: true` is explicit in every file. gig_ridges has no state to share between tests, so a
  sync file needs a reason in a header comment, and a new one without is a finding.
- **Offline and self-contained.** Inputs are fabricated in the test or taken from `gig_datasets`;
  nothing reads the network, the repository's own files, or R at test time — a ggridges value is a
  golden, observed once.
- **Doctests are for the API.** A `@doc` example runs as a doctest only on an API function, where
  it is also the documentation users read. A non-API function is tested by ordinary tests; a
  `doctest` line for an internal module is a finding. An API example shows what a user sees, never
  an internal struct.
- Test names are behavioral sentences ("leaves out a point below the cut-off").

## Not a finding

- Labeled goldens with their what-moves-this comment.
- Assertions on contract text (an exception, the datum in a message).
- `assert_raise` on a documented refusal.
- A pre-existing brittle test the diff didn't touch (goes under "Pre-existing, not from this
  change").

## Overlap

If a test is hard to write because logic lives in the wrong module, that's a
**module-boundaries** finding (the fix is moving the code), not a test-quality finding.

## Severity

- **High** — false confidence: a test that passes when the behavior is broken, or a coverage
  hole on a documented promise (a `@doc`, the README).
- **Medium** — brittleness: assertions a harmless refactor breaks (wording, layout, unlabeled
  magic numbers); redundant re-testing at the wrong layer.
- **Low** — hygiene: naming, missing golden labels.
