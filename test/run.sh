#!/usr/bin/env bash
# Test suite for cdd. Usage: ./test/run.sh

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CDD="$ROOT/cdd"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cdd-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf 'ok   - %s\n' "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL - %s\n' "$1"
    printf '  expected: %s\n' "$2"
    printf '  actual:   %s\n' "$3"
  fi
}

# Run without multiplexer variables inherited from the caller.
clean_env() {
  env -u HERDR_ENV -u HERDR_SESSION -u HERDR_WORKSPACE_ID -u HERDR_PANE_ID \
      -u HERDR_TAB_ID -u HERDR_SOCKET_PATH -u HERDR_BIN_PATH \
      -u TMUX -u TMUX_PANE -u STY -u WINDOW -u CDD_MULTIPLEXER "$@"
}

# How cdd stores a directory ($HOME is written as ~).
expect_dir() {
  case "$1" in
    "$HOME") printf '~' ;;
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Run a bash snippet in a herdr pane context. The snippet receives the cdd
# path as $1 and the remaining arguments after that.
run_herdr() {
  local file="$1" snippet="$2"
  shift 2
  clean_env CDD_FILE="$file" TERM_PROGRAM=herdr HERDR_ENV=1 \
    HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    bash -c "$snippet" _ "$CDD" "$@"
}

# Same for a tmux pane, using a fake tmux that reports main,1.0.
run_tmux() {
  local file="$1" snippet="$2"
  shift 2
  clean_env PATH="$TMP/bin:$PATH" CDD_FILE="$file" TERM_PROGRAM=tmux \
    TMUX="$TMP/fake-tmux" bash -c "$snippet" _ "$CDD" "$@"
}

mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho main,1.0\n' >"$TMP/bin/tmux"
chmod +x "$TMP/bin/tmux"

dir1="$TMP/dir one"
dir2="$TMP/dir two"
dir3="$TMP/dir:three"
dir4="$TMP/plain"
mkdir -p "$dir1" "$dir2" "$dir3" "$dir4"

# --- herdr -----------------------------------------------------------------

out="$(run_herdr "$TMP/t1.cdd" '
  . "$1"
  echo "$CDD_BACKEND|$CDD_SESSION|$CDD_WINDOW|$CDD_PANE|$CDD_DEFAULT_PANE|$CDD_KEY|$CDD_KEY_SCOPE"
  cd "$2" || exit 1
  _cdd_chpwd
  cat "$CDD_FILE"
' "$dir1")"
check "herdr: detection and auto registration" \
  "herdr|main|1|2|1|herdr/main,1.2|herdr/main
herdr/main,1.2:$(expect_dir "$dir1")
last:$(expect_dir "$dir1")" "$out"

out="$(clean_env CDD_FILE="$TMP/t2.cdd" TERM_PROGRAM=herdr HERDR_ENV=1 \
  HERDR_SESSION=sub HERDR_WORKSPACE_ID=w3 HERDR_PANE_ID=w3:p11 \
  bash -c '. "$1"; echo "$CDD_KEY"' _ "$CDD")"
check "herdr: session and pane namespace" "herdr/sub,3.11" "$out"

out="$(run_herdr "$TMP/t3.cdd" '
  . "$1"
  for key in 1 1. 1.2 w1:p2 w1.p2 p2 p11 herdr/main,1.2 last foo; do
    printf "%s -> %s\n" "$key" "$(_cdd_canonicalize_key "$key")"
  done')"
check "herdr: key canonicalization" \
  "1 -> herdr/main,1.1
1. -> herdr/main,1.1
1.2 -> herdr/main,1.2
w1:p2 -> herdr/main,1.2
w1.p2 -> herdr/main,1.2
p2 -> herdr/main,1.2
p11 -> herdr/main,1.11
herdr/main,1.2 -> herdr/main,1.2
last -> last
foo -> foo" "$out"

# --- tmux ------------------------------------------------------------------

out="$(run_tmux "$TMP/t4.cdd" '
  . "$1"
  echo "$CDD_BACKEND|$CDD_SESSION|$CDD_WINDOW|$CDD_PANE|$CDD_KEY"
  printf "%s -> %s\n" 1 "$(_cdd_canonicalize_key 1)"
  printf "%s -> %s\n" 1.2 "$(_cdd_canonicalize_key 1.2)"
  cd "$2" || exit 1
  _cdd_chpwd
  cat "$CDD_FILE"
' "$dir2")"
check "tmux: regression" \
  "tmux|main|1|0|main,1.0
1 -> main,1.0
1.2 -> main,1.2
main,1.0:$(expect_dir "$dir2")
last:$(expect_dir "$dir2")" "$out"

# --- nested multiplexers ---------------------------------------------------

out="$(clean_env PATH="$TMP/bin:$PATH" CDD_FILE="$TMP/t5.cdd" \
  TERM_PROGRAM=herdr HERDR_ENV=1 TMUX="$TMP/fake-tmux" \
  HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
  bash -c '. "$1"; echo "$CDD_BACKEND"' _ "$CDD")"
check "nesting: herdr inside tmux" "herdr" "$out"

out="$(clean_env PATH="$TMP/bin:$PATH" CDD_FILE="$TMP/t5.cdd" \
  TERM_PROGRAM=tmux TMUX="$TMP/fake-tmux" HERDR_ENV=1 \
  HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
  bash -c '. "$1"; echo "$CDD_BACKEND"' _ "$CDD")"
check "nesting: tmux inside herdr" "tmux" "$out"

# --- CDD_MULTIPLEXER -------------------------------------------------------

out="$(clean_env CDD_FILE="$TMP/t6.cdd" CDD_MULTIPLEXER=none TERM_PROGRAM=herdr \
  HERDR_ENV=1 HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
  bash -c '. "$1"; echo "[$CDD_KEY]"; cd "$2" || exit 1; _cdd_chpwd; cat "$CDD_FILE"' \
  _ "$CDD" "$dir1")"
check "CDD_MULTIPLEXER=none: only last is registered" \
  "[]
last:$(expect_dir "$dir1")" "$out"

out="$(clean_env CDD_FILE="$TMP/t7.cdd" CDD_MULTIPLEXER=herdr TERM_PROGRAM=xterm \
  HERDR_ENV=1 HERDR_SESSION=dev HERDR_WORKSPACE_ID=w2 HERDR_PANE_ID=w2:p5 \
  bash -c '. "$1"; echo "$CDD_BACKEND|$CDD_KEY"' _ "$CDD")"
check "CDD_MULTIPLEXER=herdr: override" "herdr|herdr/dev,2.5" "$out"

# --- add / delete / cd -----------------------------------------------------

out="$(run_herdr "$TMP/t8.cdd" '
  . "$1"
  cdd add 1.2 "$2"
  cdd add w1:p3 "$3"
  echo "--- file ---"
  cat "$CDD_FILE"
  cd /
  cdd 1.2
  pwd
  cdd 1.3
  pwd
  cdd delete 1.2
  cdd 1.2
  echo "rc=$?"
' "$dir1" "$dir3" 2>/dev/null)"
check "herdr: add/delete/cd" \
  "--- file ---
herdr/main,1.2:$(expect_dir "$dir1")
herdr/main,1.3:$(expect_dir "$dir3")
cd $(expect_dir "$dir1")
$dir1
cd $(expect_dir "$dir3")
$dir3
rc=3" "$out"

out="$(run_herdr "$TMP/t9.cdd" '
  . "$1"
  cdd add 1.2 "$2"
  cdd add 1.20 "$3"
  cdd delete 1.2
  grep -c "^herdr/main,1.20:" "$CDD_FILE" || true
  grep -c "^herdr/main,1.2:" "$CDD_FILE" || true
' "$dir1" "$dir2")"
check "herdr: key removal matches exactly" \
  "1
0" "$out"

# --- shared CDD_FILE -------------------------------------------------------

file="$TMP/t10.cdd"
run_tmux "$file" '. "$1"; cd "$2" || exit 1; _cdd_chpwd' "$dir1" >/dev/null
run_herdr "$file" '. "$1"; cd "$2" || exit 1; _cdd_chpwd' "$dir2" >/dev/null

out="$({ grep -c '^main,1.0:' "$file" || true; grep -c '^herdr/main,1.2:' "$file" || true; })"
check "tmux and herdr keys coexist in one file" \
  "1
1" "$out"

out="$(run_herdr "$file" '. "$1"; cd /; cdd main,1.0; pwd' 2>/dev/null)"
check "cross-backend lookup with an explicit key" \
  "cd $(expect_dir "$dir1")
$dir1" "$out"

# --- zsh -------------------------------------------------------------------

if command -v zsh >/dev/null 2>&1; then
  out="$(clean_env CDD_FILE="$TMP/t11.cdd" TERM_PROGRAM=herdr HERDR_ENV=1 \
    HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -c 'autoload -U compinit; compinit -i 2>/dev/null; source "$1"; cd "$2" || exit 1; print -r -- "$CDD_KEY"; cat "$CDD_FILE"' \
    _ "$ROOT/cdd.plugin.zsh" "$dir1" 2>/dev/null)"
  check "zsh plugin: chpwd registration" \
    "herdr/main,1.2
herdr/main,1.2:$(expect_dir "$dir1")
last:$(expect_dir "$dir1")" "$out"

  file="$TMP/t11b.cdd"
  printf 'herdr/main,1.1:%s\nherdr/main,1.2:%s\nmain,1.0:%s\nlast:%s\n' \
    "$dir1" "$dir2" "$dir3" "$dir1" >"$file"
  out="$(clean_env CDD_FILE="$file" TERM_PROGRAM=herdr HERDR_ENV=1 \
    HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -c 'autoload -U compinit; compinit -i 2>/dev/null; source "$1"; _cdd_comp zsh 2 cdd; print -r -- "$_cdd_opts"' \
    _ "$CDD" 2>/dev/null)"
  check "zsh completion: scope and default pane" \
    "1:$(expect_dir "$dir1")
1.2:$(expect_dir "$dir2")
main,1.0:$(expect_dir "$dir3")
last:$(expect_dir "$dir1")" "$out"

  # Regression: zsh's noclobber option broke key replacement.
  file="$TMP/t11c.cdd"
  out="$(clean_env CDD_FILE="$file" TERM_PROGRAM=herdr HERDR_ENV=1 \
    HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -o noclobber -c '
      autoload -U compinit; compinit -i 2>/dev/null
      source "$1"
      cd "$2" || exit 1
      _cdd_chpwd
      _cdd_chpwd
      cat "$CDD_FILE"
    ' _ "$CDD" "$dir4" 2>&1)"
  check "zsh noclobber: no duplicate registration" \
    "herdr/main,1.2:$(expect_dir "$dir4")
last:$(expect_dir "$dir4")" "$out"

  # Regression: sourcing the plugin twice must not register the hook twice.
  out="$(clean_env CDD_FILE="$TMP/t11d.cdd" TERM_PROGRAM=herdr HERDR_ENV=1 \
    HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -c '
      autoload -U compinit; compinit -i 2>/dev/null
      source "$1"
      source "$1"
      print -r -- "${#chpwd_functions}"
    ' _ "$ROOT/cdd.plugin.zsh" 2>/dev/null)"
  check "zsh plugin: chpwd hook registered once" "1" "$out"
else
  echo "skip - zsh not installed"
fi

# --- bash completion -------------------------------------------------------

file="$TMP/t12.cdd"
printf 'herdr/main,1.2:%s\nlast:%s\n' "$dir4" "$dir1" >"$file"
out="$(run_herdr "$file" '
  . "$1"
  COMP_WORDS=(cdd "")
  COMP_CWORD=1
  _cdd
  printf "%s\n" "${COMPREPLY[@]}"
')"
case "$out" in
  *"1.2:$(expect_dir "$dir4")"*)
    check "bash completion: herdr key candidate" ok ok
    ;;
  *)
    check "bash completion: herdr key candidate" "contains 1.2:$(expect_dir "$dir4")" "$out"
    ;;
esac

# Regression: bash's noclobber option must not break key replacement.
out="$(run_herdr "$TMP/t12b.cdd" '
  set -o noclobber
  . "$1"
  cd "$2" || exit 1
  _cdd_chpwd
  _cdd_chpwd
  cat "$CDD_FILE"
' "$dir4" 2>&1)"
check "bash noclobber: no duplicate registration" \
  "herdr/main,1.2:$(expect_dir "$dir4")
last:$(expect_dir "$dir4")" "$out"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
