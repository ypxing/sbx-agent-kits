# pre-bash-common.sh — shared Bash-tool guardrail checks for the claude/codex/copilot
# PreToolUse hooks (config/<agent>/hooks/pre-bash.sh). Copied into every agent's
# hooks/ dir by apply-config.sh; each agent's pre-bash.sh sources it and only
# handles its own stdin-parsing and output format (their PreToolUse contracts
# differ on both).
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

# Consume one "word" from the front of $1: if it starts with a quote,
# consume through the matching quote (so quoted values containing spaces,
# e.g. `-c` args, aren't split apart); otherwise consume to the next
# whitespace. Sets _tok (word, quotes included) and _rest (remainder, with
# leading whitespace trimmed).
_consume_word() {
  local s="$1"
  case "$s" in
    \"*)
      [[ "$s" =~ ^(\"[^\"]*\")[[:space:]]*(.*)$ ]] || return 1
      _tok="${BASH_REMATCH[1]}"; _rest="${BASH_REMATCH[2]}"
      ;;
    \'*)
      [[ "$s" =~ ^(\'[^\']*\')[[:space:]]*(.*)$ ]] || return 1
      _tok="${BASH_REMATCH[1]}"; _rest="${BASH_REMATCH[2]}"
      ;;
    *)
      [[ "$s" =~ ^([^[:space:]]+)[[:space:]]*(.*)$ ]] || return 1
      _tok="${BASH_REMATCH[1]}"; _rest="${BASH_REMATCH[2]}"
      ;;
  esac
}

# Consume a `key=value` style argument whose VALUE may itself be a quoted
# string containing spaces (e.g. `key='a b'`) even though the `key=` prefix
# isn't quoted -> a plain whitespace/quote split on the whole token would
# otherwise stop at the first space inside the value. Also handles the
# whole `key=value` pair being quoted as one token, and an empty value
# (e.g. `-c credential.helper=`).
_consume_kv_word() {
  local s="$1"
  if [[ "$s" =~ ^(\"|\') ]]; then
    _consume_word "$s"; return
  fi
  if [[ "$s" =~ ^([^[:space:]=]+=)(.*)$ ]]; then
    local prefix="${BASH_REMATCH[1]}" val_part="${BASH_REMATCH[2]}"
    if [ -z "$val_part" ] || [[ "$val_part" == [[:space:]]* ]]; then
      _tok="$prefix"
      [[ "$val_part" =~ ^[[:space:]]*(.*)$ ]]
      _rest="${BASH_REMATCH[1]}"
      return 0
    fi
    _consume_word "$val_part" || return 1
    _tok="${prefix}${_tok}"
    return 0
  fi
  _consume_word "$s"
}

# Strip a leading `git` plus any recognized global options (`-c key=value`,
# `-C <dir>`, `--git-dir=<path>`, `--no-pager`, ...) so callers can reliably
# find the real subcommand (e.g. `push`) even when such options are inserted
# between `git` and it (e.g. `git -c credential.helper=x push ...`, which
# would otherwise dodge a literal `git push` prefix match). Only the common,
# realistic subset of git's global options is recognized here -- anything
# else falls through to the fail-closed `-*)` case below, which is safe
# (just occasionally over-cautious) rather than silently letting an
# unrecognized option hide the real subcommand. Echoes "<subcommand>
# <rest...>" and returns 0 on success; returns 1 (echoing nothing) on an
# unrecognized/unterminated option.
git_after_global_opts() {
  local s="$1"

  [[ "$s" =~ ^git([[:space:]]+(.*))?$ ]] || return 1
  s="${BASH_REMATCH[2]:-}"

  while [ -n "$s" ]; do
    case "$s" in
      -c\ *)
        s="${s#* }"
        _consume_kv_word "$s" || return 1
        s="$_rest"
        ;;
      -C\ *|--git-dir\ *|--work-tree\ *)
        s="${s#* }"
        _consume_word "$s" || return 1
        s="$_rest"
        ;;
      --git-dir=*|--work-tree=*)
        _consume_word "$s" || return 1
        s="$_rest"
        ;;
      -p|-p\ *|--paginate|--paginate\ *|--no-pager|--no-pager\ *)
        _consume_word "$s" || return 1
        s="$_rest"
        ;;
      -*)
        # Unrecognized option -> can't safely tell if it takes a value, so
        # we can't reliably locate the subcommand. Fail closed.
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  printf '%s' "$s"
}

# --- git push: allow pushing feature branches, block push to main/master ---
# Returns 0 (true) if any `git push` invocation targets (or, when the
# refspec is unspecified, would push) the main/master branch.
# Reads $segments, set by pre_bash_command_blocked below.
git_push_protected() {
  local seg rest tok last_ref positional_count unspecified cur after
  while IFS= read -r seg; do
    case "$seg" in
      git|git[[:space:]]*) ;;
      *) continue ;;
    esac
    if ! after=$(git_after_global_opts "$seg"); then
      # Couldn't resolve global options on a `git` invocation -> might be
      # hiding a `push` to main/master. Fail closed rather than skip it.
      return 0
    fi
    case "$after" in
      push|push[[:space:]]*) ;;
      *) continue ;;
    esac
    rest=${after#push}
    # --all / --mirror push every branch, including protected ones
    case " $rest " in
      *' --all '*|*' --mirror '*) return 0 ;;
    esac
    last_ref=""
    positional_count=0
    for tok in $rest; do
      case "$tok" in -*) continue ;; esac
      positional_count=$((positional_count + 1))
      last_ref="$tok"
    done
    case "$last_ref" in
      main|master|refs/heads/main|refs/heads/master|*:main|*:master|*:refs/heads/main|*:refs/heads/master)
        return 0 ;;
    esac
    # `git push`, `git push <remote>` or `git push <remote> HEAD` don't name a
    # destination branch explicitly -> they push whatever is checked out now.
    unspecified=0
    [ "$positional_count" -le 1 ] && unspecified=1
    [ "$last_ref" = "HEAD" ] && unspecified=1
    if [ "$unspecified" = 1 ]; then
      cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
      case "$cur" in main|master) return 0 ;; esac
    fi
  done <<< "$segments"
  return 1
}

# pre_bash_command_blocked CMD — the shared deny-rule set: make *deploy*, git push
# to main/master, non-read-only aws, docker compose *deploy*, rm -rf, wget, reading
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
  || echo "$scan" | grep -qE '(^|[;&|] *)(sudo )?rm -rf ' \
  || echo "$scan" | grep -qE '(^|[;&|] *)(sudo )?wget ' \
  || echo "$scan" | grep -qE '(cat|head|tail|less|more|bat|source|\.) +(\S*/)*\.(env|npmrc|yarnrc)' \
  || echo "$scan" | grep -iqE '(UPDATE[[:space:]]+[^[:space:]]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|COLUMN)[[:space:]]|TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[^[:space:]]|ALTER[[:space:]]+TABLE[[:space:]]+[^[:space:]]+[[:space:]]+DROP[[:space:]])'
}
