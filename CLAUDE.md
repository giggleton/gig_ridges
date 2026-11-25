# gig_ridges

Ridgeline plots for Giggly, as a Giggly plugin: a density-ridges stat, a ridgeline geom and a
density-ridgeline geom, with layer functions on `GigRidges` (README says what each draws). It
takes Giggly by path from the worktree that holds Giggly's plugin API (`mix.exs`); Giggly is worked
on in its own session, never edited from here.

## Working here

- **Only in a session opened in this repository.** Its own `.claude/settings.json` wires its commit
  gate; a commit made from another repository's session is judged by that repository's gate, not
  this one.
- **Run `mix quality` bare before every commit** — never piped or filtered, so its failure is
  seen. It stops at the first failing step: format check, `hex.audit`, compile and test with
  warnings as errors, `credo --strict`.
- **The passes, and when:**
  - before a commit touching `test/`: the `elixir-code-review` skill, then `docs-sync`;
  - after every commit that changes `lib/` code: the `mutation-testing` skill, over that commit,
    before anything else is committed.

  Each skill's last step records its mark under `.git/claude-skill-marks/`, in a call of its own;
  `.claude/hooks/commit-gate.sh` denies the commit until the marks are current. A mark is made only
  by finishing its skill, never to get past the gate.
- **Commit only on Steve's word, and never push.**

## ggridges

ggridges is GPL-2. Its numbers may be observed by running it — the Docker image
`giggly-r:ggplot2-4.0.3-ggridges` — and pinned as labeled goldens; its code, text and data are
never read, copied or paraphrased here.
