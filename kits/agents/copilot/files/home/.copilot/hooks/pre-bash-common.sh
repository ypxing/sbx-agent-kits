# pre-bash-common.sh — shared Bash-tool guardrail checks for the claude/codex/copilot/cursor
# PreToolUse hooks (hooks/pre-bash.sh in each agent's home dir). This file is
# identical across kits/agents/{claude,codex,copilot,cursor}/files/home/<agent-dir>/hooks/ —
# each agent's pre-bash.sh sources it and only handles its own stdin-parsing and
# output format (their PreToolUse contracts differ on both).
#
# Not executable / has no shebang on purpose — this is a library, always sourced.

# Split $1 on separators and strip, per segment, leading env assignments, sudo and
# transparent wrappers, which would otherwise hide anchored patterns (e.g. `env rm
# -rf /`) from the checks below.
normalize_segments() {
  printf '%s\n' "$1" \
  | sed -E 's/(\&\&|\|\||[;|&])/\n/g' \
  | sed -E '
      :w
      s/^[[:space:]]+//
      s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)+//
      s/^(sudo|command|exec|time|nice|ionice|stdbuf|env)([[:space:]]+-[^[:space:]]+)*[[:space:]]+//
      tw'
}

# --- aws: allow read-only operations, block anything that can mutate ---------
# Returns 0 (true) if the command contains an aws invocation that is NOT read-only.
# Reads $cmd and $segments, set by pre_bash_command_blocked below.
aws_write_detected() {
  local seg tok svc op saw_aws=0
  while IFS= read -r seg; do
    case "$seg" in
      aws|aws[[:space:]]*) ;;
      *) continue ;;
    esac
    saw_aws=1
    # first two non-flag tokens after `aws` == service + operation
    svc=""; op=""
    for tok in $seg; do
      [ "$tok" = "aws" ] && continue
      case "$tok" in -*) continue ;; esac
      if [ -z "$svc" ]; then svc="$tok"
      elif [ -z "$op" ]; then op="$tok"; break
      fi
    done
    # `aws`, `aws help`, `aws s3` (no operation) -> harmless usage output
    [ -z "$svc" ] && continue
    case "$svc" in
      sso|configure|help) continue ;;   # auth/config plumbing needed by the sandbox
    esac
    [ -z "$op" ] && continue
    case "$op" in
      describe-*|list-*|get-*|head-*|lookup-*|search-*|batch-get-*|select-*|check-*|validate-*|test-*|estimate-*|preview-*) continue ;;
      query|scan|tail|ls|help|wait) continue ;;
    esac
    return 0
  done <<< "$segments"
  # fail closed: `aws` appears together with an indirection construct we cannot
  # parse (eval / bash -c / xargs / command substitution) -> treat as a write
  if [ "$saw_aws" = 0 ] \
     && printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])aws([[:space:]]|$)' \
     && printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_-])(eval|xargs|source|\.)([[:space:]]|$)|(ba|z|k|da)?sh[[:space:]]+(-[[:alnum:]]*c)|\$\(|`'; then
    return 0
  fi
  return 1
}

# --- git push: allow pushing feature branches, block push to main/master ---
# Returns 0 (true) if any `git push` invocation targets (or, when the
# refspec is unspecified, would push) the main/master branch. The `git`
# binary may be given by path (/usr/bin/git) and followed by global options
# (-c k=v, -C dir, --git-dir=..., --no-pager, ...) before the `push`.
# Reads $segments, set by pre_bash_command_blocked below.
git_push_protected() {
  local seg split tok next is_push positional_count last_ref unspecified cur
  local -a toks rest repo_args
  while IFS= read -r seg; do
    read -r -a toks <<< "$seg"
    [ "${#toks[@]}" -gt 0 ] || continue
    [ "${toks[0]##*/}" = "git" ] || continue
    # re-split honouring shell quotes (`-c 'user.name=CI Bot'` is one value);
    # xargs parses quotes without running anything. Unbalanced quotes we
    # can't parse -> fail closed if the segment mentions push at all.
    if ! split=$(xargs -r printf '%s\n' <<< "$seg" 2>/dev/null) || [ -z "$split" ]; then
      case " $seg " in *[[:space:]]push[[:space:]]*) return 0 ;; esac
      continue
    fi
    mapfile -t toks <<< "$split"
    # skip git's global options; -c/-C/--git-dir/--work-tree/--namespace/
    # --config-env may take their value as the next token. Repository
    # selection (-C, --git-dir, --work-tree) is kept, in order, to resolve
    # HEAD in the repo actually being pushed; -c is never replayed since a
    # config value (e.g. core.fsmonitor) can run code.
    next=""; is_push=0; rest=(); repo_args=()
    for tok in "${toks[@]:1}"; do
      if [ "$is_push" = 1 ]; then rest+=("$tok"); continue; fi
      case "$next" in
        repo) repo_args+=("$tok"); next=""; continue ;;
        skip) next=""; continue ;;
      esac
      case "$tok" in
        -C|--git-dir|--work-tree) repo_args+=("$tok"); next=repo ;;
        --git-dir=*|--work-tree=*) repo_args+=("$tok") ;;
        -c|--namespace|--config-env|--super-prefix) next=skip ;;
        -*) ;;
        push) is_push=1 ;;
        *) break ;;   # some other subcommand
      esac
    done
    [ "$is_push" = 1 ] || continue
    # --all / --mirror push every branch, including protected ones
    case " ${rest[*]} " in
      *' --all '*|*' --mirror '*) return 0 ;;
    esac
    # first positional is the remote, every later one a refspec; a leading
    # `+` (force) or `src:` doesn't change the destination's name
    positional_count=0
    last_ref=""
    for tok in "${rest[@]}"; do
      case "$tok" in -*) continue ;; esac
      positional_count=$((positional_count + 1))
      [ "$positional_count" -ge 2 ] || continue
      last_ref="$tok"
      tok=${tok#+}
      case "$tok" in
        main|master|refs/heads/main|refs/heads/master|*:main|*:master|*:refs/heads/main|*:refs/heads/master)
          return 0 ;;
      esac
    done
    # `git push`, `git push <remote>` or `git push <remote> HEAD` don't name a
    # destination branch explicitly -> they push whatever is checked out now
    # (in the repo the -C/--git-dir/--work-tree options select).
    unspecified=0
    [ "$positional_count" -le 1 ] && unspecified=1
    [ "${last_ref#+}" = "HEAD" ] && unspecified=1
    if [ "$unspecified" = 1 ]; then
      cur=$(git "${repo_args[@]}" symbolic-ref --short HEAD 2>/dev/null)
      case "$cur" in main|master) return 0 ;; esac
    fi
  done <<< "$segments"
  return 1
}

# pre_bash_command_blocked CMD — the shared deny-rule set: make *deploy*, git push
# to main/master, non-read-only aws, docker compose *deploy*, wget, reading
# .env*/.npmrc*/.yarnrc*, destructive SQL. Sets $segments/$scan as a side effect
# (used by aws_write_detected/git_push_protected above) and returns 0 (true) if the
# command should be blocked.
pre_bash_command_blocked() {
  cmd="$1"
  segments=$(normalize_segments "$cmd")
  scan=$(printf '%s\n%s' "$cmd" "$segments")

  echo "$scan" | grep -qE 'make .*(deploy)' \
  || git_push_protected \
  || aws_write_detected \
  || echo "$scan" | grep -qE 'docker compose .*(deploy)' \
  || echo "$scan" | grep -qE '(^|[;&|] *)(sudo )?wget ' \
  || echo "$scan" | grep -qE '(cat|head|tail|less|more|bat|source|\.) +(\S*/)*\.(env|npmrc|yarnrc)' \
  || echo "$scan" | grep -iqE '(UPDATE[[:space:]]+[^[:space:]]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|COLUMN)[[:space:]]|TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[^[:space:]]|ALTER[[:space:]]+TABLE[[:space:]]+[^[:space:]]+[[:space:]]+DROP[[:space:]])'
}
