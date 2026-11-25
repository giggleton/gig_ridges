---
name: docs-sync
description: Keeps gig_ridges' documentation surfaces current after a change — README, the moduledocs and `@doc`s, CLAUDE.md, and the skills themselves. Run this AFTER completing any substantive change (feature, refactor, rename, option, default, decision), BEFORE reporting the work done or when the user asks to commit. Not needed for trivial fixes that change no behavior, name, or claim.
---

# Docs sync — after a change, before "done"

Documentation drifts one skipped update at a time; every stale claim traces to a change that
shipped without its doc update. The rule: **docs update in the same change** — or you say
explicitly, when reporting done, what was deferred and where. Never silent.

## Step 0 — if the change touched `test/`, review it before documenting it

If the change touched `test/`, run the **`elixir-code-review`** skill *first*, and act on what it
finds: its findings routinely change the code, and docs written before that describe a draft. If
it's already been run for this change, carry on.

**Not a loop.** `elixir-code-review`'s "If findings led to code changes" step says to run
docs-sync — that step is *this* run, continuing at Step 1. Don't re-invoke either skill from the
other a second time.

## Step 1 — grep for dead names (the highest-value check)

If the change **renamed, moved, or deleted** anything referenceable — a module, function, option,
default, aesthetic — grep the old name across every doc surface:

```bash
grep -rn 'OldName' CLAUDE.md README.md .claude/skills/
grep -rn 'OldName' lib --include='*.ex'
```

(`lib` is the second sweep because moduledoc and `@doc` *prose* names modules and options.)

**Two commands, and it must stay two — do not "tidy" them back into one.** `--include` filters
*every* path given to that `grep`, not just the one it trails. Folded together, the `*.ex` filter
excludes every `.md` surface in the list, and the command reports a confident `clean` while the
stale claims sit untouched.

**A move out of a module that survives needs one more grep: the module it left.** A sentence
saying the old module owns the moved responsibility still names a live module. Grep the source
module's name and read each hit for a claim of ownership it no longer holds.

## Step 2 — route the change to its doc surfaces

| The change | Update |
|---|---|
| A layer function, option, default or aesthetic users see | **README**'s Use section, and the `GigRidges` function's `@doc` and doctest, accurate to the *final* behavior. |
| How a stat or geom computes or draws | Its module's `@moduledoc` (`GigRidges.DensityRidges`, `GigRidges.Ridgeline`, `GigRidges.DensityRidgeline`, `GigRidges.DensityRidgeline2`); an internal module's opening comment under `@moduledoc false`. |
| A new or changed public function | Its `@doc` (with a doctest only on an API function) and a `@spec`; a non-API function's comment under `@doc false`. |
| A value now matched to ggridges | The README's "Relationship to ggridges" when the claim it makes changes (the version checked against); the test's `Golden:` label names the versions. |
| How work is done here: a gate, a pass, a rule for sessions | **CLAUDE.md**, a sentence or two; the step itself is its skill or `mix.exs`. |
| A new `mix quality` step | The `quality` alias in `mix.exs` **is** the list; CLAUDE.md gets a sentence only if the step needs explaining. |
| A dependency, or how Giggly is taken | `mix.exs`'s comment above `deps/0`, and README's Installation when a user's `deps` changes. |

gig_ridges keeps no design log: the story goes in the commit message.

## Step 3 — skills are docs too

If the change invalidates a claim in any `.claude/skills/*/SKILL.md` or reference file (a module
name, a path, a command, the gate's rules in `.claude/hooks/commit-gate.sh`), update it in the
same change. Step 1's grep already covered `.claude/skills/`.

## Step 4 — prove the doctests and references hold

`mix quality`'s test step runs the doctests, so an example that no longer matches fails there.
For a module or function a doc names in backticks, check it still exists (Step 1's grep, on the
name). gig_ridges has no ExDoc build, so nothing else resolves the references.

## Step 5 — record the pass for the commit gate

Run `mix format` if any step above edited files, then, in a call of its own:

```bash
bash .claude/hooks/commit-gate.sh mark docs
```

A PreToolUse hook denies `git commit` on any diff touching `test/` until this mark (and
elixir-code-review's) matches the working tree. The mark is a hash over every changed file, so it
goes stale when anything changes after it — a follow-up change owes its own pass. This step is the
**only** sanctioned way to produce the mark: running it without having done the routing above is
falsifying the record, not passing the gate.

## Calibration

- **Substantive** = changes behavior, a name, a shape, or a documented claim. A typo fix, a
  test-only change, or a refactor invisible outside its module needs nothing.
- When reporting the work done, name the doc updates made (or explicitly deferred) — the user
  should never discover doc drift later.
