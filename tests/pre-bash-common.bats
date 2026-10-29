#!/usr/bin/env bats
# Guardrail checks shared by the claude/codex/copilot pre-bash hooks.
# Run: bats tests/

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  HOOK="$REPO/kits/agents/claude/files/home/.claude/hooks/pre-bash-common.sh"
  # a throwaway repo so "unspecified refspec" cases resolve a current branch
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q -b feature "$WORK"
  cd "$WORK"
}

blocked() { bash -c 'source "$1"; pre_bash_command_blocked "$2"' _ "$HOOK" "$1"; }

# `! blocked ...` would never fail a test (errexit ignores negated commands),
# so assert the hook's "not blocked" status explicitly.
allowed() {
  run blocked "$1"
  if [ "$status" -ne 1 ]; then
    echo "expected allowed (status 1), got $status: $1"
    return 1
  fi
}

@test "hook library is identical across agents" {
  cmp "$HOOK" "$REPO/kits/agents/codex/files/home/.codex/hooks/pre-bash-common.sh"
  cmp "$HOOK" "$REPO/kits/agents/copilot/files/home/.copilot/hooks/pre-bash-common.sh"
}

@test "blocks plain push to main/master" {
  blocked "git push origin main"
  blocked "git push origin master"
  blocked "git push origin HEAD:refs/heads/main"
}

@test "blocks push to main hidden behind git global options" {
  blocked "git -c x=y push origin main"
  blocked "git -C . push origin main"
  blocked "git --no-pager push origin main"
  blocked "git --git-dir=.git --work-tree=. push origin main"
  blocked "git -c a=b -C . --no-pager push origin main"
}

@test "blocks push to main via a path to the git binary" {
  blocked "/usr/bin/git push origin main"
  blocked "sudo /usr/bin/git -C . push origin main"
}

@test "blocks force refspec and main among several refspecs" {
  blocked "git push origin +main"
  blocked "git push origin main feature"
  blocked "git push --all origin"
}

@test "blocks push to main when a git option value is quoted" {
  blocked "git -c 'user.name=CI Bot' push origin main"
  blocked 'git -c "user.name=CI Bot" push origin main'
  blocked "git -C '$WORK' push origin main"
}

@test "blocks unparseable quoting next to git push (fails closed)" {
  blocked "git -c 'user.name=CI push origin main"
}

@test "resolves the current branch through every repository-selection option" {
  MAINREPO="$BATS_TEST_TMPDIR/mainrepo"
  git init -q -b main "$MAINREPO"
  blocked "git -C $MAINREPO -C . push origin"
  blocked "git -C $BATS_TEST_TMPDIR -C mainrepo push origin"
  blocked "git --git-dir=$MAINREPO/.git push origin"
  blocked "git --git-dir $MAINREPO/.git --work-tree $MAINREPO push origin"
  blocked "git --work-tree=$WORK --git-dir=$MAINREPO/.git push origin HEAD"
  allowed "git -C $MAINREPO -C $WORK push origin"
}

@test "blocks unspecified refspec while on main, including via -C" {
  git checkout -q -b main
  blocked "git push"
  blocked "git push origin HEAD"
  cd "$BATS_TEST_TMPDIR"
  blocked "git -C $WORK push origin"
}

@test "allows pushing feature branches" {
  allowed "git push origin feature"
  allowed "git -c x=y push -u origin feature"
  allowed "git -C . push origin HEAD"
  allowed "git push"
  allowed "git push origin maintenance"
}

@test "ignores non-push git commands" {
  allowed "git -C . status"
  allowed "git log main"
  allowed "git -c 'user.name=CI Bot' commit -m 'push to main'"
}
