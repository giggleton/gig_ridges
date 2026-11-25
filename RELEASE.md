# Releasing GigRidges

A release goes in one order, and nothing but this file enforces it. The documentation links each
function to its source at the tag `v<version>` (`source_ref` in `mix.exs`), so the tag is pushed
before the package is published.

Publishing to Hex needs the maintainer's Hex keys; it is never done by an agent.

1. **Take the dependencies from Hex.** Hex refuses a package with path dependencies, so this waits
   until `scales` 0.2.0, `gig_datasets` 0.1.0 and `giggly` 0.2.0 are published. Then, in `mix.exs`,
   the three path dependencies become

   ```elixir
   {:giggly, "~> 0.2.0"},
   {:scales, "~> 0.2.0"},
   {:gig_datasets, "~> 0.1.0", only: [:dev, :test]},
   ```

   the comment above `deps` is rewritten to say what each is taken for, with nothing about paths
   or worktrees, and the lock is refreshed:

   ```bash
   mix deps.get
   ```

   `CLAUDE.md`'s opening paragraph says Giggly is taken by path; it is corrected in the same
   commit. CI cannot pass before this step: a runner has none of the paths.

2. **Set the version.** In `mix.exs`, set `@version` to the release, say `"0.1.0"`, and commit it.
   The README's install lines name the same version.

3. **See the gate pass**: `mix quality` locally, and CI on that commit. `mix docs` builds without
   warnings.

4. **Check the package.**

   ```bash
   mix hex.build --unpack
   ```

   The unpacked package should hold `lib/`, `mix.exs`, `.formatter.exs`, `README.md` and
   `LICENSE`, and nothing else. Remove the unpacked directory afterwards.

5. **Tag and push.**

   ```bash
   git tag v0.1.0
   git push origin main v0.1.0
   ```

6. **Publish.**

   ```bash
   mix hex.publish
   ```
