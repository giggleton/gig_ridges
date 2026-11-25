#!/usr/bin/env bash
# The commit gate: hard-blocks `git commit` until the last code commit's mutation pass is recorded,
# and, on a diff touching `test/`, until the review and docs passes are recorded for the EXACT
# current working tree.
#
# Why this exists: CLAUDE.md requires the elixir-code-review and docs-sync skills before a commit
# touching `test/`, and the mutation-testing skill after every commit that changes code — and those
# rules get skipped under wrap-up pressure. A memory is advisory; this hook is enforced by the
# harness, the same reasoning that gives the repo `mix quality` instead of "keep the suite green"
# as discipline. Taken from Giggly's gate, less its waiver and paired-rules-file rules: gig_ridges
# has no waivers and no `.claude/rules`.
#
# The rules, checked in this order:
#   1. MUTATION — the last commit, when it changed code (`lib/**/*.ex`, a deleted file aside), must
#      have had the mutation-testing skill's pass over the lines it changed before anything else
#      is committed. A merge needs no pass of its own, nor does a root commit. The rule reads only
#      HEAD, so the last commit of a branch merged with `--no-ff` is held by the after-commit nudge
#      alone. The pass follows the commit because muex's `--since` reads committed history only;
#      this rule makes it follow every time, not only when remembered.
#   2. GATED PATHS — a diff touching test/** needs both the review and the docs mark.
#
# Protocol:
#   * `check` — the PreToolUse(Bash) hook entry point. Reads the tool-call JSON on stdin; ignores
#     anything that isn't a `git commit`.
#   * `post-commit` — the PostToolUse(Bash) hook entry point. After a `git commit`, when `HEAD`
#     needs a mutation pass and has no mark, it tells the agent to run the pass now, naming the
#     commit and its files: a nudge at the moment the pass is due, where rule 1 is what holds.
#   * `mark review` / `mark docs` / `mark mutation` — the skills' final step (and ONLY theirs —
#     see below) records the pass. Marks live under .git/claude-skill-marks/, so they can never be
#     committed or shared. The review and docs marks are per checkout. A mutation mark names a
#     commit, so it lives in the repository's common git dir, shared by every worktree: a commit
#     marked in a worktree stays marked once it is merged.
#
# A review or docs mark is a hash over EVERY changed path and its content (staged, unstaged,
# untracked, deletions included), so editing any file after a pass makes the mark stale on
# purpose: a follow-up tweak owes its own pass ("per change, not per session"). Run `mix format`
# before marking, so the recorded state is the one quality's format step will keep.
#
# Honesty note: nothing can physically stop the agent running `mark` without doing the work — it
# executes the skills too. The gate's value is that the ONLY documented path to a mark is the final
# step of the skill itself, so skipping becomes an explicit act instead of a slide.
#
# Requires `jq` and `git` on PATH.

command="${1:-check}"

# The hook entry points judge the checkout the command runs in, named by the tool-call JSON's
# `cwd`, not the directory the hook was started in: a session working in a git worktree runs its
# commands there while its hooks may start in the main checkout.
input=""
case "$command" in
  check | post-commit)
    input="$(cat)"
    command_cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
    if [ -n "$command_cwd" ]; then
      cd "$command_cwd" || exit 1
    fi
    ;;
esac

marks_dir="$(git rev-parse --git-dir)/claude-skill-marks"
mutation_marks_dir="$(git rev-parse --git-common-dir)/claude-skill-marks/mutation"

# Every changed path (staged, unstaged, untracked), rename targets resolved.
changed_paths() {
  git status --porcelain=v1 -uall | sed -e 's/^...//' -e 's/.* -> //'
}

# The subset rule 2 cares about — mirrors CLAUDE.md's elixir-code-review trigger.
gated_paths() {
  grep '^test/' || true
}

# Content hash of a path set: paths plus each file's blob hash (deletions included), so any edit to
# any file in the set after a pass invalidates the mark.
state_hash() {
  {
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      if [ -f "$path" ]; then
        printf '%s %s\n' "$path" "$(git hash-object "$path")"
      else
        printf '%s deleted\n' "$path"
      fi
    done
  } | sha256sum | cut -d' ' -f1
}

# Rule 1's subject: the code files a commit changed, deletions left out — the files its mutation
# pass mutates. Empty for a root commit or a merge, which need no pass of their own. A git
# pathspec's `*` crosses `/`, so `lib/*.ex` reaches every depth.
mutation_files() {
  local commit="$1"
  git rev-parse --verify --quiet "$commit^" >/dev/null || return 0
  git rev-parse --verify --quiet "$commit^2" >/dev/null && return 0
  git diff --name-only --diff-filter=d "$commit^" "$commit" -- 'lib/*.ex'
}

# HEAD's mutation files when it has no mutation mark; nothing when it has one or needs none.
unmarked_mutation_files() {
  local head
  head="$(git rev-parse --verify --quiet HEAD)" || return 0
  [ -f "$mutation_marks_dir/$head" ] && return 0
  mutation_files "$head"
}

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

mark_status() {
  local mark_file="$1" current="$2"
  if [ ! -f "$mark_file" ]; then
    echo "missing"
  elif [ "$(cat "$mark_file")" = "$current" ]; then
    echo "ok"
  else
    echo "stale"
  fi
}

case "$command" in
  mark)
    kind="${2:?usage: commit-gate.sh mark review|docs|mutation}"
    case "$kind" in
      review | docs)
        mkdir -p "$marks_dir"
        changed_paths | sort -u | state_hash >"$marks_dir/$kind"
        echo "marked $kind for the current working tree"
        ;;
      mutation)
        mkdir -p "$mutation_marks_dir"
        : >"$mutation_marks_dir/$(git rev-parse HEAD)"
        echo "marked mutation for commit $(git rev-parse --short HEAD)"
        ;;
      *) echo "unknown mark kind: $kind" >&2 && exit 1 ;;
    esac
    ;;

  check)
    tool_command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

    # Only gate actual commits; a compound command like `git add -A && git commit` still
    # contains the literal substring. Everything else passes untouched.
    case "$tool_command" in
      *"git commit"*) ;;
      *) exit 0 ;;
    esac

    # Rule 1.
    unmarked="$(unmarked_mutation_files)"
    if [ -n "$unmarked" ]; then
      deny "MUTATION GATE: the last commit, $(git log -1 --format='%h "%s"'), changed code and its mutation pass is not recorded. Run the mutation-testing skill over it before committing anything else — its final step runs 'bash .claude/hooks/commit-gate.sh mark mutation'. Files it changed:
$unmarked"
    fi

    changed="$(changed_paths | sort -u)"
    [ -z "$changed" ] && exit 0

    # Rule 2.
    gated="$(printf '%s\n' "$changed" | gated_paths)"
    [ -z "$gated" ] && exit 0

    current="$(printf '%s\n' "$changed" | state_hash)"
    review_state="$(mark_status "$marks_dir/review" "$current")"
    docs_state="$(mark_status "$marks_dir/docs" "$current")"

    if [ "$review_state" = "ok" ] && [ "$docs_state" = "ok" ]; then
      exit 0
    fi

    deny "COMMIT GATE: this diff touches 'test/' and the skill passes are not recorded for its current state (review: $review_state, docs: $docs_state). Run the elixir-code-review skill, then the docs-sync skill, for THIS diff — each ends by running 'bash .claude/hooks/commit-gate.sh mark review' / 'mark docs'. A stale mark means a file changed after the pass: run 'mix format' and re-run the skill for the delta. Gated paths:
$gated"
    ;;

  post-commit)
    tool_command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

    case "$tool_command" in
      *"git commit"*) ;;
      *) exit 0 ;;
    esac

    unmarked="$(unmarked_mutation_files)"
    [ -z "$unmarked" ] && exit 0

    jq -n --arg context "MUTATION PASS DUE: commit $(git log -1 --format='%h "%s"') changed code. Run the mutation-testing skill over it now, before other work: the commit gate denies the next commit until its pass is marked. Files it changed:
$unmarked" \
      '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
    ;;

  *)
    echo "usage: commit-gate.sh check|post-commit|mark review|docs|mutation" >&2
    exit 1
    ;;
esac
