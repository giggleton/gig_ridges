# gig_ridges

Ridgeline plots for Giggly, as a Giggly plugin: the density-ridges and binline stats; the
ridgeline, density-ridgeline, outlined, gradient, vertical and density-line geoms; the jittered
points' sina, jitter and raincloud positions; cyclical scales and a ridges theme, all on
`GigRidges` (README says what each draws). It takes Giggly from Hex (`mix.exs`); Giggly is worked
on in its own session, never edited from here.

## Working here

- The commit gate and its hooks are wired by this repository's own `.claude/settings.json`, so
  they fire only for a session whose working directory is this repository; a commit made from
  another repository's session is judged by that repository's gate, not this one.
- **Run `mix quality` bare before every commit** — never piped or filtered, so its failure is
  seen. It stops at the first failing step: format check, `hex.audit`, compile and test with
  warnings as errors, `credo --strict`. CI (`.github/workflows/ci.yml`) runs the same alias.
- **The passes, and when:**
  - before a commit touching `test/`: the `elixir-code-review` skill, then `docs-sync`;
  - after every commit that changes `lib/` code: the `mutation-testing` skill, over that commit,
    before anything else is committed.

  Each skill's last step records its mark under `.git/claude-skill-marks/`, in a call of its own;
  `.claude/hooks/commit-gate.sh` denies the commit until the marks are current. A mark is made only
  by finishing its skill, never to get past the gate.
- **Commit only on Steve's word, and never push.** A release goes in the order `RELEASE.md`
  gives; publishing to Hex is Steve's alone.

## ggridges

ggridges is GPL-2. Its numbers may be observed by running it — the Docker image
`giggly-r:ggplot2-4.0.3-ggridges` — and pinned as labeled goldens; its code, text and data are
never read, copied or paraphrased here.
