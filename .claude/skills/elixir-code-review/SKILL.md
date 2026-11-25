---
name: elixir-code-review
description: Reviews gig_ridges' Elixir code for the problems this library cares about — logic in the wrong module, a module's internals reached past the API, reaching into Giggly past its plugin API, and test quality (brittle, duplicative, or valueless tests). Use this whenever the user asks for a code review, asks you to look over a diff or branch, asks where some logic should live, asks whether tests are worth keeping or are brittle/duplicative, or is about to commit changes touching `test/`. Also use it proactively after you yourself write or modify tests, before reporting the work as done.
---

# Elixir Code Review

Reviews changed Elixir code against the rules that matter in gig_ridges. Each rule lives in its
own reference file so the review stays focused.

## Available checks

| Check | Reference file | Applies to |
|---|---|---|
| Module boundaries | `references/module-boundaries.md` | `lib/**/*.ex` |
| Test quality | `references/test-quality.md` | `test/**/*.exs`, `test/support/**` |

Read only the reference files whose "Applies to" pattern matches files in scope. Reading rules
that can't apply wastes context and tends to produce stretched findings.

Mutation testing is not part of this review: the `mutation-testing` skill runs it after the
commit, over the lines the commit changed.

## Scope

Default to reviewing **changed code only** — what the branch has committed since it left
`main`, plus everything uncommitted or untracked, since review usually runs before the commit:

```bash
base=$(git merge-base HEAD main) && { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u
```

On `main` itself the merge base is `HEAD`, so the list is the working tree's changes; on a
branch it adds the branch's commits. A failed `git merge-base` prints its error and stops the
command with a non-zero status, so an empty list means there are no changes, never that the
command broke.

Reviewing whole files, or the whole repo, only happens when the user explicitly asks for it.
Pre-existing violations are usually known and deliberate; flagging them on every unrelated change
is how a review gets ignored. If a changed function sits next to an obvious violation the author
didn't touch, mention it once at the end under "Pre-existing, not from this change".

## Process

1. **Determine scope.** Get the changed files with the command under Scope. Filter to
   `.ex`/`.exs` files. If nothing matches any check's file pattern, say so and stop — a clean
   "nothing in scope here" is a useful answer, not a failure.

2. **Load the relevant rules.** Read the reference files for the checks that apply.

3. **Read the code with its context.** For a module under review, also open the modules it
   calls, `lib/gig_ridges.ex` (the API), and the Giggly behaviour it adopts (`Giggly.Stat`,
   `Giggly.Geom`, under `deps/giggly/lib/`). Most judgments depend on what the API already
   offers. For a test file under review, also open the module under test and any other test
   covering the same behavior — the layer and duplication judgments depend on both.

4. **Judge each candidate.** Every reference file has a "not a finding" section. Work through it
   honestly before writing anything up. Precision is worth more than recall — a review with one
   real finding and zero noise gets acted on; one buried in six quibbles gets skimmed.

5. **Deduplicate.** When one piece of code trips both rules, report it **once**, under the check
   whose suggested fix actually applies.

6. **Report** using the format below.

7. **If findings led to code changes**, run the `docs-sync` skill before finishing — a fix that
   moves or renames logic invalidates docs the same way any change does.

8. **Record the pass for the commit gate.** Run `mix format` (so the recorded state is the one
   quality's format step will keep), then, in a call of its own:

   ```bash
   bash .claude/hooks/commit-gate.sh mark review
   ```

   A PreToolUse hook denies `git commit` on any diff touching `test/` until this mark matches the
   working tree — and the mark is a hash over every changed file, so it goes stale if anything
   changes after it, because a follow-up change owes its own pass. This step is the **only**
   sanctioned way to produce the mark: running it without having done the review above is
   falsifying the record, not passing the gate.

## Report format

Order findings by severity, highest first. If there are no findings, say that in one line and
stop — don't pad the report with things that are fine.

```markdown
## Review: <branch or file list>

### <severity>: <one-line description>
**`lib/gig_ridges/ridgeline.ex:42`**

<2-4 lines: what the code does, and why it belongs elsewhere or what bug the test misses. Point
at the specific consequence — testable only through the whole plot, duplicated in a second
caller, a test that passes with the behavior broken — not "separation of concerns" in the
abstract.>

**Suggested shape:**
```elixir
# a sketch, not a patch
```
```

Severity levels:

- **High** — an invariant made unenforceable: a test that passes with the behavior broken,
  reliance on a Giggly internal that a Giggly release can break silently, a pure function that
  reads the outside world.
- **Medium** — logic in the wrong home but contained: reachable from one caller only, or
  duplicated across two; brittle assertions.
- **Low** — small leaks and hygiene worth noting.

Suggested code is a sketch, not a patch. Don't rewrite the module unless asked. If the right fix
genuinely isn't obvious, say that and name the options rather than inventing a module.
