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
      -u HERDR_TAB_ID -u HERDR_SOCKET_PATH -u HERDR_BIN_PATH -u HERDR_FIX \
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
# path as $1 and the remaining arguments after that. Candidate pane IDs are
# supplied by the fake herdr below.
run_herdr() {
  local file="$1" snippet="$2"
  shift 2
  clean_env PATH="$TMP/bin:$PATH" HERDR_FIX="$TMP/herdr" \
    CDD_FILE="$file" TERM_PROGRAM=herdr HERDR_ENV=1 \
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

mkdir -p "$TMP/bin" "$TMP/herdr"

printf '#!/bin/sh\necho main,1.0\n' >"$TMP/bin/tmux"
chmod +x "$TMP/bin/tmux"

# Fake "herdr pane list". Positions are intentionally different from the
# stable pane numbers so tests catch ID/position mixups.
cat >"$TMP/herdr/current.json" <<'__EOT__'
{"id":"cli:pane:list","result":{"panes":[
{"cwd":"/tmp/a","focused":false,"pane_id":"w1:p2","tab_id":"w1:t1","workspace_id":"w1"},
{"cwd":"/tmp/b","focused":true,"pane_id":"w1:p5","tab_id":"w1:t1","workspace_id":"w1"},
{"cwd":"/tmp/c","focused":false,"pane_id":"w1:pA","tab_id":"w1:t2","workspace_id":"w1"},
{"cwd":"/tmp/d","focused":false,"pane_id":"w9:p3","tab_id":"w9:t1","workspace_id":"w9"}
],"type":"pane_list"}}
__EOT__

cat >"$TMP/herdr/sub.json" <<'__EOT__'
{"id":"cli:pane:list","result":{"panes":[
{"cwd":"/tmp/s","focused":false,"pane_id":"w4:p4","tab_id":"w4:t4","workspace_id":"w4"},
{"cwd":"/tmp/t","focused":true,"pane_id":"w4:p5","tab_id":"w4:t5","workspace_id":"w4"}
],"type":"pane_list"}}
__EOT__

# A pane list that the parser cannot read reliably (a "},{` inside a cwd
# value splits the pane object before pane_id).
cat >"$TMP/herdr/broken.json" <<'__EOT__'
{"id":"cli:pane:list","result":{"panes":[
{"workspace_id":"w1","cwd":"/tmp/a},{x","pane_id":"w1:p2","tab_id":"w1:t1","focused":true},
{"workspace_id":"w1","cwd":"/tmp/b","pane_id":"w1:p5","tab_id":"w1:t1","focused":false}
],"type":"pane_list"}}
__EOT__

cat >"$TMP/bin/herdr" <<'__EOT__'
#!/bin/sh
case "$*" in
  "pane list") cat "$HERDR_FIX/current.json" ;;
  "--session main pane list") cat "$HERDR_FIX/current.json" ;;
  "--session sub pane list") cat "$HERDR_FIX/sub.json" ;;
  "--session broken pane list") cat "$HERDR_FIX/broken.json" ;;
  "--session down pane list")
    echo '{"id":"cli:pane:list","error":{"code":"server_not_running","message":"no herdr server is running"}}'
    ;;
  *)
    echo "herdr stub: unexpected arguments: $*" >&2
    exit 1
    ;;
esac
__EOT__
chmod +x "$TMP/bin/herdr"

dir1="$TMP/dir one"
dir2="$TMP/dir two"
dir3="$TMP/dir:three"
dir4="$TMP/plain"
dir5="$TMP/dir five"
dir6="$TMP/dir six"
mkdir -p "$dir1" "$dir2" "$dir3" "$dir4" "$dir5" "$dir6"

# --- herdr: detection and stable keys --------------------------------------

out="$(run_herdr "$TMP/t1.cdd" '
  . "$1"
  echo "$CDD_BACKEND|$CDD_SESSION|$CDD_WINDOW|$CDD_PANE|$CDD_DEFAULT_PANE|$CDD_KEY|$CDD_KEY_SCOPE"
  cd "$2" || exit 1
  _cdd_chpwd
  cat "$CDD_FILE"
' "$dir1")"
check "herdr: detection and auto registration" \
  "herdr|main|w1|p2|0|herdr/main,w1.p2|herdr/main
herdr/main,w1.p2:$(expect_dir "$dir1")
last:$(expect_dir "$dir1")" "$out"

out="$(clean_env PATH="$TMP/bin:$PATH" HERDR_FIX="$TMP/herdr" CDD_FILE="$TMP/t2.cdd" \
  TERM_PROGRAM=herdr HERDR_ENV=1 HERDR_SESSION=main \
  HERDR_WORKSPACE_ID=wA HERDR_PANE_ID=wA:pF \
  bash -c '. "$1"; echo "$CDD_KEY"' _ "$CDD")"
check "herdr: pane ids over 9 are kept as-is" "herdr/main,wA.pF" "$out"

out="$(clean_env PATH="$TMP/bin:$PATH" HERDR_FIX="$TMP/herdr" CDD_FILE="$TMP/t3.cdd" \
  TERM_PROGRAM=herdr HERDR_ENV=1 HERDR_SESSION=sub \
  HERDR_WORKSPACE_ID=w3 HERDR_PANE_ID=w3:pB \
  bash -c '. "$1"; echo "$CDD_KEY"' _ "$CDD")"
check "herdr: session and pane namespace" "herdr/sub,w3.pB" "$out"

out="$(run_herdr "$TMP/t4.cdd" '
  . "$1"
  for key in 1 1. 1.2 w1:p2 w1.p2 p2 pB wA:pF w1:p11 herdr/main,w1.p2 w1.2 p0 w1:p2:/tmp/y last foo; do
    printf "%s -> %s\n" "$key" "$(_cdd_canonicalize_key "$key")"
  done')"
check "herdr: stable key canonicalization" \
  "1 -> 1
1. -> 1.
1.2 -> 1.2
w1:p2 -> herdr/main,w1.p2
w1.p2 -> herdr/main,w1.p2
p2 -> herdr/main,w1.p2
pB -> herdr/main,w1.pB
wA:pF -> herdr/main,wA.pF
w1:p11 -> herdr/main,w1.p11
herdr/main,w1.p2 -> herdr/main,w1.p2
w1.2 -> w1.2
p0 -> herdr/main,w1.p0
w1:p2:/tmp/y -> w1:p2:/tmp/y
last -> last
foo -> foo" "$out"

# --- herdr: position keys --------------------------------------------------

out="$(run_herdr "$TMP/t5.cdd" '
  . "$1"
  for key in 1 1.2 2.1 2.1.1 sub,1 sub,2 pA w1:p5; do
    resolved="$(_cdd_expand_key "$key")" || resolved="ERROR"
    printf "%s -> %s\n" "$key" "$resolved"
  done')"
check "herdr: position key resolution" \
  "1 -> herdr/main,w1.p2
1.2 -> herdr/main,w1.p5
2.1 -> herdr/main,w1.pA
2.1.1 -> herdr/main,w9.p3
sub,1 -> herdr/sub,w4.p4
sub,2 -> herdr/sub,w4.p5
pA -> pA
w1:p5 -> w1:p5" "$out"

out="$(run_herdr "$TMP/t5b.cdd" '
  . "$1"
  printf "%s -> %s\n" "main,1.2" "$(_cdd_expand_key "main,1.2")"
')"
check "herdr: explicit current session" "main,1.2 -> herdr/main,w1.p5" "$out"

file="$TMP/t6.cdd"
{
  printf 'herdr/main,w1.p2:%s\n' "$dir1"
  printf 'herdr/main,w1.p5:%s\n' "$dir2"
  printf 'herdr/main,w1.pA:%s\n' "$dir3"
  printf 'herdr/main,w9.p3:%s\n' "$dir4"
  printf 'herdr/sub,w4.p5:%s\n' "$dir5"
  printf 'main,1.0:%s\n' "$dir6"
} >"$file"
out="$(run_herdr "$file" '
  . "$1"
  cd /
  cdd 1.2; pwd
  cdd 1; pwd
  cdd 2.1; pwd
  cdd 2.1.1; pwd
  cdd sub,2; pwd
  cdd main,1.0; pwd
  cdd w1:p5; pwd
  cdd p2; pwd
' 2>/dev/null)"
check "herdr: cd by position, stable and literal keys" \
  "cd $dir2
$dir2
cd $dir1
$dir1
cd $dir3
$dir3
cd $dir4
$dir4
cd $dir5
$dir5
cd $dir6
$dir6
cd $dir2
$dir2
cd $dir1
$dir1" "$out"

out="$(run_herdr "$TMP/t7.cdd" '
  . "$1"
  for key in 1.3 3.1.1 sub,3 down,1; do
    _cdd_expand_key "$key" 2>&1 >/dev/null
  done')"
check "herdr: position key errors" \
  "cdd: 1.3: no pane at tab 1, pane 3
cdd: 3.1.1: no pane at workspace 3, tab 1, pane 1
cdd: sub,3: no pane at tab 3, pane 1
cdd: down,1: herdr session 'down' is not running" "$out"

out="$(run_herdr "$TMP/t7.cdd" '. "$1"; cdd 1.3 >/dev/null 2>&1; echo $?')"
check "herdr: position error exit status" "3" "$out"

out="$(run_herdr "$TMP/t7c.cdd" '. "$1"; cdd "w1:p2:/tmp/y" >/dev/null 2>&1; echo $?')"
check "herdr: pane id with a trailing path is not trimmed" "3" "$out"

out="$(run_herdr "$TMP/t7b.cdd" '
  . "$1"
  _cdd_expand_key broken,1
' 2>&1)"
check "herdr: unreadable pane list is an error" \
  "cdd: broken,1: could not read panes from herdr" "$out"

# --- herdr: add / delete ---------------------------------------------------

out="$(run_herdr "$TMP/t8.cdd" '
  . "$1"
  cdd add 1.2 "$2"
  grep "^herdr/main,w1.p5:" "$CDD_FILE"
  cdd add w1:pB "$3"
  grep "^herdr/main,w1.pB:" "$CDD_FILE"
  cdd delete 1.2
  grep -c "^herdr/main,w1.p5:" "$CDD_FILE" || true
  cdd delete w1:pB
  grep -c "^herdr/main,w1.pB:" "$CDD_FILE" || true
' "$dir1" "$dir2")"
check "herdr: add/delete with position and stable keys" \
  "herdr/main,w1.p5:$(expect_dir "$dir1")
herdr/main,w1.pB:$(expect_dir "$dir2")
0
0" "$out"

out="$(run_herdr "$TMP/t9.cdd" '
  . "$1"
  cdd add w1:p2 "$2"
  cdd add w1:pB "$3"
  cdd delete w1:p2
  grep -c "^herdr/main,w1.pB:" "$CDD_FILE" || true
  grep -c "^herdr/main,w1.p2:" "$CDD_FILE" || true
' "$dir1" "$dir2")"
check "herdr: key removal matches exactly" \
  "1
0" "$out"

out="$(run_herdr "$TMP/t9b.cdd" '
  . "$1"
  cdd add "w1:p2:$2"
  grep "^herdr/main,w1.p2:" "$CDD_FILE"
  cdd add "herdr/main,w1.p5:$3"
  grep "^herdr/main,w1.p5:" "$CDD_FILE"
  cd "$3" || exit 1
  cdd add w1:pB
  grep "^herdr/main,w1.pB:" "$CDD_FILE"
' "$dir1" "$dir2")"
check "herdr: add with key:dir for pane ids" \
  "herdr/main,w1.p2:$(expect_dir "$dir1")
herdr/main,w1.p5:$(expect_dir "$dir2")
herdr/main,w1.pB:$(expect_dir "$dir2")" "$out"

# --- tmux ------------------------------------------------------------------

out="$(run_tmux "$TMP/t10.cdd" '
  . "$1"
  echo "$CDD_BACKEND|$CDD_SESSION|$CDD_WINDOW|$CDD_PANE|$CDD_KEY"
  printf "%s -> %s\n" 1 "$(_cdd_canonicalize_key 1)"
  printf "%s -> %s\n" 1.2 "$(_cdd_canonicalize_key 1.2)"
  cd "$2" || exit 1
  _cdd_chpwd
  cat "$CDD_FILE"
' "$dir1")"
check "tmux: regression" \
  "tmux|main|1|0|main,1.0
1 -> main,1.0
1.2 -> main,1.2
main,1.0:$(expect_dir "$dir1")
last:$(expect_dir "$dir1")" "$out"

# --- nested multiplexers ---------------------------------------------------

out="$(clean_env PATH="$TMP/bin:$PATH" CDD_FILE="$TMP/t11.cdd" \
  TERM_PROGRAM=herdr HERDR_ENV=1 TMUX="$TMP/fake-tmux" \
  HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
  bash -c '. "$1"; echo "$CDD_BACKEND"' _ "$CDD")"
check "nesting: herdr inside tmux" "herdr" "$out"

out="$(clean_env PATH="$TMP/bin:$PATH" CDD_FILE="$TMP/t11.cdd" \
  TERM_PROGRAM=tmux TMUX="$TMP/fake-tmux" HERDR_ENV=1 \
  HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
  bash -c '. "$1"; echo "$CDD_BACKEND"' _ "$CDD")"
check "nesting: tmux inside herdr" "tmux" "$out"

# --- CDD_MULTIPLEXER -------------------------------------------------------

out="$(clean_env CDD_FILE="$TMP/t12.cdd" CDD_MULTIPLEXER=none TERM_PROGRAM=herdr \
  HERDR_ENV=1 HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
  bash -c '. "$1"; echo "[$CDD_KEY]"; cd "$2" || exit 1; _cdd_chpwd; cat "$CDD_FILE"' \
  _ "$CDD" "$dir1")"
check "CDD_MULTIPLEXER=none: only last is registered" \
  "[]
last:$(expect_dir "$dir1")" "$out"

out="$(clean_env CDD_FILE="$TMP/t13.cdd" CDD_MULTIPLEXER=herdr TERM_PROGRAM=xterm \
  HERDR_ENV=1 HERDR_SESSION=dev HERDR_WORKSPACE_ID=w2 HERDR_PANE_ID=w2:p5 \
  bash -c '. "$1"; echo "$CDD_BACKEND|$CDD_KEY"' _ "$CDD")"
check "CDD_MULTIPLEXER=herdr: override" "herdr|herdr/dev,w2.p5" "$out"

# --- shared CDD_FILE -------------------------------------------------------

file="$TMP/t14.cdd"
run_tmux "$file" '. "$1"; cd "$2" || exit 1; _cdd_chpwd' "$dir1" >/dev/null
run_herdr "$file" '. "$1"; cd "$2" || exit 1; _cdd_chpwd' "$dir2" >/dev/null

out="$({ grep -c '^main,1.0:' "$file" || true; grep -c '^herdr/main,w1.p2:' "$file" || true; })"
check "tmux and herdr keys coexist in one file" \
  "1
1" "$out"

out="$(run_herdr "$file" '. "$1"; cd /; cdd main,1.0; pwd' 2>/dev/null)"
check "cross-backend lookup with a literal key" \
  "cd $(expect_dir "$dir1")
$dir1" "$out"

file="$TMP/t14b.cdd"
printf 'main,1.1:%s\n' "$dir1" >"$file"
out="$(run_herdr "$file" '. "$1"; cd /; cdd main,1.1; pwd' 2>/dev/null)"
check "literal key wins when the resolved pane is unregistered" \
  "cd $(expect_dir "$dir1")
$dir1" "$out"

file="$TMP/t14c.cdd"
printf 'main,1.1:%s\nherdr/main,w1.p2:%s\n' "$dir1" "$dir2" >"$file"
out="$(run_herdr "$file" '. "$1"; cd /; cdd main,1.1; pwd' 2>/dev/null)"
check "resolved herdr pane wins when both keys are registered" \
  "cd $(expect_dir "$dir2")
$dir2" "$out"

# --- cdd list --------------------------------------------------------------

file="$TMP/t17.cdd"
{
  printf 'herdr/main,w1.p2:%s\n' "$dir1"
  printf 'herdr/main,w1.p5:%s\n' "$dir2"
  printf 'herdr/main,w1.pA:%s\n' "$dir3"
  printf 'herdr/main,w9.p3:%s\n' "$dir4"
  printf 'herdr/sub,w4.p5:%s\n' "$dir5"
  printf 'herdr/down,w1.p1:%s\n' "$dir5"
  printf 'main,1.0:%s\n' "$dir6"
  printf 'last:%s\n' "$dir1"
} >"$file"

out="$(run_herdr "$file" '. "$1"; cdd list')"
check "cdd list: position keys with stable pane IDs" \
  "herdr/down,w1.p1: $(expect_dir "$dir5")
main,1 (w1:p2): $(expect_dir "$dir1")
main,1.0: $(expect_dir "$dir6")
main,1.2 (w1:p5): $(expect_dir "$dir2")
main,2 (w1:pA): $(expect_dir "$dir3")
main,2.1.1 (w9:p3): $(expect_dir "$dir4")
sub,2 (w4:p5): $(expect_dir "$dir5")
last: $(expect_dir "$dir1")" "$out"

out="$(run_herdr "$file" '. "$1"; cdd help' 2>&1)"
case "$out" in
  *"cdd list"*"main,1 (w1:p2): $(expect_dir "$dir1")"*)
    check "cdd help: includes the friendly list" ok ok
    ;;
  *)
    check "cdd help: includes the friendly list" "usage and main,1 (w1:p2): ..." "$out"
    ;;
esac

file="$TMP/t17b.cdd"
printf 'herdr/broken,w1.p1:%s\n' "$dir1" >"$file"
out="$(run_herdr "$file" '. "$1"; cdd list')"
check "cdd list: unreadable session falls back to stored key" \
  "herdr/broken,w1.p1: $(expect_dir "$dir1")" "$out"

# --- zsh -------------------------------------------------------------------

if command -v zsh >/dev/null 2>&1; then
  out="$(clean_env CDD_FILE="$TMP/t15.cdd" TERM_PROGRAM=herdr HERDR_ENV=1 \
    HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -c 'autoload -U compinit; compinit -i 2>/dev/null; source "$1"; cd "$2" || exit 1; print -r -- "$CDD_KEY"; cat "$CDD_FILE"' \
    _ "$ROOT/cdd.plugin.zsh" "$dir1" 2>/dev/null)"
  check "zsh plugin: chpwd registration" \
    "herdr/main,w1.p2
herdr/main,w1.p2:$(expect_dir "$dir1")
last:$(expect_dir "$dir1")" "$out"

  file="$TMP/t15b.cdd"
  printf 'herdr/main,w1.p1:%s\nherdr/main,w1.p2:%s\nmain,1.0:%s\nmain,1.1:%s\nlast:%s\nherdr/sub,w4.p4:%s\n' \
    "$dir1" "$dir2" "$dir3" "$dir5" "$dir1" "$dir4" >"$file"
  out="$(clean_env CDD_FILE="$file" TERM_PROGRAM=herdr HERDR_ENV=1 \
    HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -c 'autoload -U compinit; compinit -i 2>/dev/null; source "$1"; _cdd_comp zsh 2 cdd; print -r -- "$_cdd_opts"' \
    _ "$CDD" 2>/dev/null)"
  check "zsh completion: stable IDs, scope and default pane" \
    'w1\:p1:'"$dir1"'
w1\:p2:'"$dir2"'
main,1.0:'"$dir3"'
main,1.1:'"$dir5"'
last:'"$dir1"'
herdr/sub,w4.p4:'"$dir4" "$out"

  # Regression: zsh does not split unquoted expansions, so position keys
  # must be parsed with read instead of `set -- $var`.
  out="$(clean_env PATH="$TMP/bin:$PATH" HERDR_FIX="$TMP/herdr" CDD_FILE="$TMP/t15e.cdd" \
    TERM_PROGRAM=herdr HERDR_ENV=1 HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -c 'source "$1"
      for key in 1 1.2 2.1 2.1.1 sub,1 sub,2; do
        printf "%s -> %s\n" "$key" "$(_cdd_expand_key "$key")"
      done' _ "$CDD" 2>/dev/null)"
  check "zsh: position key resolution" \
    "1 -> herdr/main,w1.p2
1.2 -> herdr/main,w1.p5
2.1 -> herdr/main,w1.pA
2.1.1 -> herdr/main,w9.p3
sub,1 -> herdr/sub,w4.p4
sub,2 -> herdr/sub,w4.p5" "$out"

  file="$TMP/t15f.cdd"
  printf 'herdr/main,w1.p5:%s\n' "$dir2" >"$file"
  out="$(clean_env PATH="$TMP/bin:$PATH" HERDR_FIX="$TMP/herdr" CDD_FILE="$file" \
    TERM_PROGRAM=herdr HERDR_ENV=1 HERDR_SESSION=main HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p2 \
    zsh -f -c 'source "$1"; cd / || exit 1; cdd 1.2; pwd' _ "$CDD" 2>/dev/null)"
  check "zsh: cd by position key" \
    "cd $(expect_dir "$dir2")
$dir2" "$out"

  # Regression: zsh's noclobber option broke key replacement.
  file="$TMP/t15c.cdd"
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
    "herdr/main,w1.p2:$(expect_dir "$dir4")
last:$(expect_dir "$dir4")" "$out"

  # Regression: sourcing the plugin twice must not register the hook twice.
  out="$(clean_env CDD_FILE="$TMP/t15d.cdd" TERM_PROGRAM=herdr HERDR_ENV=1 \
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

file="$TMP/t16.cdd"
printf 'herdr/main,w1.p2:%s\nlast:%s\n' "$dir4" "$dir1" >"$file"
expected_bash="w1:p2:$(expect_dir "$dir4")"
out="$(run_herdr "$file" '
  . "$1"
  COMP_WORDS=(cdd "")
  COMP_CWORD=1
  _cdd
  printf "%s\n" "${COMPREPLY[@]}"
')"
case "$out" in
  *"$expected_bash"*)
    check "bash completion: stable herdr ID candidate" ok ok
    ;;
  *)
    check "bash completion: stable herdr ID candidate" "contains $expected_bash" "$out"
    ;;
esac

# Regression: bash's noclobber option must not break key replacement.
out="$(run_herdr "$TMP/t16b.cdd" '
  set -o noclobber
  . "$1"
  cd "$2" || exit 1
  _cdd_chpwd
  _cdd_chpwd
  cat "$CDD_FILE"
' "$dir4" 2>&1)"
check "bash noclobber: no duplicate registration" \
  "herdr/main,w1.p2:$(expect_dir "$dir4")
last:$(expect_dir "$dir4")" "$out"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
