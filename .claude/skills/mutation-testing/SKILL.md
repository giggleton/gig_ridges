---
name: mutation-testing
description: Mutation-tests the lines the last commit changed, running muex's mutants in warm VMs, and triages every surviving mutant — a behavior no test pins, unreachable or redundant code, an equivalent mutant, a message's wording — then writes the fixes and reports what it found. Run it right after every commit that changes `lib/` code; an after-commit hook names the commit, and the commit gate denies the next commit until this skill's final step has marked it. Also use it when the user asks for a mutation run, or asks which of a commit's lines no test pins.
---

# Mutation testing — after a commit, over the lines it changed

muex's mutators break the code one small edit at a time (a guard replaced with `true`, `==` with
`!=`, a clause deleted), and the tests are rerun against each mutant. A mutant that survives is a
behavior no test pins — found from the code, not from the tests already written, which is the hole a
hand-picked mutant misses.

It runs after the commit, not in the review before it, and over the lines the commit changed, not
the whole files it touched: the unchanged lines had their pass when they were committed, and a
run over whole files costs many times as long for almost nothing more.

## Scope

The lines the last commit added or changed in `lib/**/*.ex`. A commit that changes only tests,
docs or configuration has nothing to mutate, and a merge has none of its own: the commits it
brings in had their passes.

Before starting, `lib/` and `test/` must match the commit. This must print nothing:

```bash
git status --porcelain -- lib test
```

The runner reads the changed line numbers from the commit but mutates and tests the files on disk,
so an uncommitted edit there shifts the lines it mutates and changes the tests it runs. If it prints
anything, stop and say so: the pass is of the commit, not of the working tree.

## Running it

`warm.sh`, beside this file, runs the pass in 8 warm VMs and writes muex's JSON report:

```bash
bash .claude/skills/mutation-testing/warm.sh <scratchpad>/mutation
```

Run it in the background, and edit nothing under `lib/` or `test/` until it finishes: a worker
compiles readers and test files from disk while it runs. How it works, and the premise it rests on
(gig_ridges keeps no state for one mutant to leave the next), is `warm.exs`'s opening comment.
What matters for reading its report:
- **The mutants are muex's**, built through its library as `mix muex --since HEAD~1 --no-optimize
  --no-filter --files <the lib/ files the commit changed>` builds them. `--since HEAD~1` keeps only
  the lines the commit added or changed, reading committed history, which is why the pass follows
  the commit; `--no-optimize`, because muex's optimizer discards most mutants and reports a
  confident false pass over the rest; `--no-filter`, because its filter skips modules it takes for
  framework code, including any declaring several `@callback`s.
- **muex is pinned `== 0.11.3`** in `mix.exs`, because the runner reaches into its library
  internals (`Muex.Config`, `Muex.Mutator.walk/3`, `Muex.GitDiff`, `Muex.Compiler`, `Muex.Tce`). A
  bump is deliberate, and is followed by checking the runner against muex's own, below.
- **Each worker checks its own baseline**: it loads the app and the tests once, runs the suite with
  no mutant, and stops if anything fails, since every mutant would then be killed by that test.
- **Every mutant meets the whole suite**, to its first failure, so none survives a test that was
  never selected for it. A test file that can no longer load because the code it calls while
  compiling raised has killed the mutant.
- **A file must compile as muex prints it**: every mutant is compiled from muex's print of the
  file's syntax tree, so each worker first compiles the unmutated print, and stops naming the file
  and the error where it fails (an escaped interpolation, `\#{...}`, in a doctest is printed
  unescaped). A lib file reading another `GigRidges` module while compiling is recompiled when a
  mutant changes what the read returns, or, for a read with arguments, for every mutant that
  reaches it — never the mutated file itself.
- **A line no test runs** is found by one `:cover` run per worker, and its mutants are reported
  `no_coverage` without running.
- **A mutant whose tests run past 60 seconds**, or whose compiling runs past ten minutes, is
  reported `timeout`, and its worker carries on in a fresh VM. The clock for its tests starts once
  it, its readers and its test files are compiled.
- **A mutant that changes a struct's fields or defaults** is reported `struct_changed`, not judged:
  every module that wrote the struct holds its defaults as they were compiled. Judge it by hand,
  applying it to the file as Findings 1 says, against the whole suite.
- **The report** is `<out>/muex.json`: every mutant with its `status`, `location`, `test_files` (the
  failing test's file for a kill, every file for a survivor) and a `patch` of the mutated node
  `before` and `after`. A statement deletion's node is the whole enclosing block, so diff the two to
  see the line that went.

### Checking the runner against muex's own

muex's own runner builds each mutant in a sandbox copy of the project and runs a fresh `mix test`
there (f85279c's 433 mutants: 6 minutes, against the warm runner's 3½). It is the reference: after a muex bump or a change to
`warm.exs`, run both over one commit and set the reports side by side. Every kill, survivor and
uncovered line should match. muex may call a mutant invalid that the runner calls killed, when a
test file failing to load beat the first failing test in its sandbox, and may let a mutant survive
that its test selection never met. A `struct_changed` mutant is muex's to judge, and the by-hand
judgment of it should agree.

**Run muex's own runner in a throwaway clone, never in the checkout.** A plain project's sandbox
links the real `lib/`, `test/` and every dependency's build: an edit to the checkout while it runs
reaches the mutants it has yet to judge, and its compile of a path dependency (Giggly, Scales,
gig_datasets) relinks that dependency's `priv` relative to the sandbox, through the link, into the
real build, which then fails to compile Scales (2026-11-24). In the clone, each path dependency's
`priv` is made a real directory, which Mix leaves as it is:

```bash
ref=<scratchpad>/ref && rm -rf "$ref" && git clone -q . "$ref"
cp mix.exs mix.lock "$ref"/   # only if muex's pin is not committed yet
cp -R --reflink=auto --preserve=mode,timestamps deps _build "$ref"/
cd "$ref"
for p in _build/test/lib/*/priv; do
  [ -L "$p" ] && t=$(readlink -f "$p") && [ -d "$t" ] && rm "$p" && cp -R --preserve=mode,timestamps "$t" "$p"
done
MIX_ENV=test mix compile && MIX_ENV=test mix test
```

First, muex's baseline, in the clone: the whole suite in a sandbox built as muex builds one for
each mutant. It must pass; muex runs this check itself only for an umbrella:

```bash
base=<scratchpad>/muex-baseline && rm -rf "$base"
MIX_ENV=test mix run --no-start -e \
  'Muex.Sandbox.create_sandbox(hd(System.argv()), File.cwd!(), "test", ["test"], [])' \
  "$base"
rm "$base/_build/test/lib/gig_ridges" && cp -R _build/test/lib/gig_ridges "$base/_build/test/lib/gig_ridges"
(cd "$base" && MIX_ENV=test mix test)
```

Then muex over the same commit, in the clone, and the comparison, from the checkout:

```bash
mix muex --since HEAD~1 --no-optimize --no-filter --verbose --coverage-guided \
  --format json --output <scratchpad>/muex.json \
  --files "$(git diff --name-only --diff-filter=d HEAD~1 HEAD -- 'lib/*.ex' | paste -sd, -)"
MIX_ENV=test mix run --no-start .claude/skills/mutation-testing/warm.exs compare \
  <scratchpad>/muex.json <scratchpad>/mutation/muex.json
```

- **One `--files`, comma-separated**: given `--files` twice, muex keeps only the last; it splits the
  value on commas, so a brace glob (`lib/{a,b}.ex`) crashes its loader. `--verbose` prints
  `Found <n> file(s)`: check it counts every file named.
- muex runs the mutants of one file one at a time, and a run of many mutants in one file is slow:
  run it in the background.

## Findings

The output to act on is the **survivors** and the **uncovered mutants**, not the score. Each
survivor is one of three things, and the report says which; each uncovered mutant is a fourth.

### 1. A behavior no test pins

A coverage hole, and at its worst when a `@doc` promises the behavior. The fix is a test naming
the bug the mutant introduced — a doctest only on an API function. Prove the new test by applying
the survivor's `patch` by hand and watching the test fail: copy the file aside first, apply the
mutant, run the test, copy the original back, `cmp` it against the copy, then `touch` it — a
restore within the same second as the mutant's compile leaves the mutant's `.beam` in place. Never
loop `sed -i.bak`. A test that passes with the mutant applied has not closed the hole.

Every mutant met the whole suite, so a survivor is never a test that was not selected for it. A
mutant in code read only at compile time (a module attribute) met its readers too, recompiled.

A value the test pins that ggridges computes is ggridges' own output, observed by running it
(CLAUDE.md, "ggridges"), never worked out by hand from its source.

### 2. Code the mutant shows is unreachable or redundant

Such as a guard its only caller already enforces — a finding on the code, not a missing test.

### 3. Equivalent — not a finding, but named

The mutant cannot change behavior: map keys reordered, `Map.put` → `Map.put_new` where a guard
already excludes the key, a type guard whose removal only changes which exception a programmer
error raises. muex never mutates documentation or typespec attributes, so a survivor that seems to
delete a `@moduledoc` is a neighbouring statement. Named with the reason, so the call can be
checked; a survivor is never dismissed silently. Diff the `patch`'s `before` and `after` to see
what a mutant changed, never a glance at the code around it.

### 4. A line no test executes

An uncovered mutant (`status: "no_coverage"`) was skipped because no test runs its line at all,
which is a stronger finding than a survivor: nothing exercises that code. Find what the line is
before judging it. It may be a clause or default argument no caller uses yet, which wants an
example or a test; or code nothing can reach, which is a finding on the code.

## Not a finding

- **Invalid mutants** (they did not compile) need nothing.
- **Message wording.** Literal and argument-order mutants inside an error or log string, when the
  tests assert the message's datum: `elixir-code-review`'s `test-quality.md` pins the datum, not
  the sentence, so these survive by design. A mutant that drops a datum the tests assert is killed;
  one that drops a datum the message states only once and no test asserts is judged as a behavior
  no test pins. **Only messages:** a string the code produces as its output — an SVG element or
  attribute, a column name, a label — is behavior, and a literal mutant surviving there is a
  finding. No mutator's survivors are set aside as a group; each one is judged where it landed.
- **A deletion the gate catches instead of the tests.** Mutants are compiled without
  `--warnings-as-errors`, so deleting an `alias` the module still uses survives as warnings that
  `mix quality` would fail.
- **The score.** Equivalent mutants count against it, so it measures noise as well as holes; the
  survivor list is the signal. A muex run also exits non-zero when the score falls below its
  default `--fail-at` of 80; that exit status is not a failure of the pass.

## What it cannot tell you

A run stops at the first failing test, so it shows that some test catches each mutant — not that
each test catches something no other does. Duplication stays the judgment in
`elixir-code-review`'s `test-quality.md`. And it mutates only the lines the commit changed, so a
test the commit deleted or weakened that was the only pin on an unchanged line goes unseen; that
is the review's question about every deleted test, asked before the commit.

## After the triage

1. **Write the fixes:** a test for each behavior no test pins and each line no test executes, each
   new test proven against its mutant as above; a change to the code for what is unreachable or
   redundant. A fix that needs Steve's decision (a change of behavior, of the API) goes to Steve
   first.
2. **Run the gates over the fixes**, which are a change like any other: `mix quality`, then
   `elixir-code-review` when they touch `test/`, then `docs-sync`, each recording its mark.
3. **Record the pass for the commit gate**, once every survivor is triaged — when there were
   none, too — in a call of its own:

   ```bash
   bash .claude/hooks/commit-gate.sh mark mutation
   ```

   It marks `HEAD`, the commit this pass ran over. The commit gate denies every commit while the
   last commit changed code and has no mark, so the fixes cannot be committed before it. This
   step is the **only** sanctioned way to produce the mark: running it without having triaged the
   run is falsifying the record, not passing the gate.
4. **Report**, below. The fixes stay uncommitted until Steve says to commit: what the pass found
   that changed something is what Steve decides on. Once committed, a fix that changed `lib/` lines
   gets a pass of its own, like any commit.

## Report

In plain words: what each number counts, and for each change, the mutant that prompted it and
what now catches it. When nothing survived, one line says so. Message-wording survivors are
grouped, one line per message.

```markdown
## Mutation pass: <short sha> <subject>
<n> mutants on the <m> changed lines of <files>; <k> survived, <u> on lines no test runs.

### What it found that changed something
- `lib/gig_ridges/ridgeline.ex:31` guard → `true` survived: no test pinned the refusal of a
  negative scale. Added "refuses a negative scale" to `test/gig_ridges_test.exs`; it fails with
  the mutant applied.

### Survivors left as they are
- `lib/gig_ridges/ridgeline.ex:48` map keys reordered — equivalent: key order means nothing
- `lib/gig_ridges/ridgeline.ex:52` error message wording (4 mutants) — the tests assert the value
```
