#!/bin/sh
# Mechanical duplication index for slop-hunt. Read-only; POSIX sh, grep and awk only.
#
# Usage: dup-index.sh [path] [min-files]
#   path       directory to index (default: .)
#   min-files  how many files a literal or line must appear in (default: 3)
#
# Environment (optional):
#   DUP_INDEX_EXCLUDE  extra extended regex of paths to leave out
#   DUP_INDEX_SKIP     extra space-separated function names to ignore
#
# Prints LEADS, not findings: every row must be read and proven before it is reported.
set -eu

case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

ROOT=${1:-.}
MIN=${2:-3}
case "$MIN" in ''|*[!0-9]*) echo "min-files must be a number" >&2; exit 2 ;; esac
cd "$ROOT"

EXT='php|js|jsx|mjs|cjs|ts|tsx|mts|py|rb|go|rs|java|kt|kts|scala|groovy|cs|fs|swift|m|mm|c|h|cc|cpp|cxx|hpp|dart|ex|exs|erl|clj|cljs|lua|pl|pm|r|jl|hs|ml|vue|svelte|astro'
EXCLUDE_DIRS='(^|/)(vendor|node_modules|dist|build|out|target|coverage|\.next|\.nuxt|\.svelte-kit|\.venv|venv|__pycache__|\.tox|Pods|Carthage|\.gradle|\.dart_tool|_build|deps|__generated__|generated|migrations)/'
EXCLUDE_FILES='\.(lock|map|snap)$|\.min\.|\.gen\.|\.generated\.|_pb2\.py$|\.pb\.go$|\.g\.dart$|\.freezed\.dart$|(^|/)package-lock\.json$'
TEST_RE='(^|/)(tests?|__tests__|specs?|testing)/|\.(test|spec)\.[A-Za-z]+$|_(test|spec)\.[A-Za-z]+$|(^|/)test_[^/]*\.py$|Tests?\.[A-Za-z]+$|Spec\.[A-Za-z]+$'

source_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files
  else
    find . -type f | sed 's|^\./||'
  fi |
    grep -Ev "$EXCLUDE_DIRS" |
    grep -Ev "$EXCLUDE_FILES" |
    { if [ -n "${DUP_INDEX_EXCLUDE:-}" ]; then grep -Ev "$DUP_INDEX_EXCLUDE"; else cat; fi; } |
    grep -E "\.($EXT)\$" || true
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dup-index.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT TERM
source_files > "$TMP/all"
grep -Ev "$TEST_RE" "$TMP/all" > "$TMP/files" || true
grep -E "$TEST_RE" "$TMP/all" > "$TMP/tests" || true
COUNT=$(wc -l < "$TMP/files" | tr -d ' ')
TCOUNT=$(wc -l < "$TMP/tests" | tr -d ' ')
echo "# Duplication index: $COUNT source files and $TCOUNT test files under $(pwd)"
echo "(leads only; prove each one before it becomes a finding)"

# Run a command over the files listed in $1; prints nothing for an empty list.
each() {
  LIST=$1; shift
  [ -s "$LIST" ] || return 0
  tr '\n' '\0' < "$LIST" | xargs -0 "$@"
}

each "$TMP/files" wc -l | grep -v ' total$' | sort -rn > "$TMP/sizes" || true

# Names too conventional to signal duplication (constructors, lifecycle hooks, CRUD actions).
SKIP="__construct __init__ __invoke constructor init new main run handle execute call apply"
SKIP="$SKIP setUp tearDown setup teardown beforeEach afterEach render toString toArray toJSON"
SKIP="$SKIP equals hashCode String Error get set index show store update destroy create edit"
SKIP="$SKIP delete up down boot register map default ${DUP_INDEX_SKIP:-}"

analyze() {
  LIST=$1
  LABEL=$2
  echo
  echo "## 2. Function names defined in 2+ files [$LABEL]"
  echo "Columns: files  private  name  (first locations)"
  echo "(private = private/protected/local by the language's convention)"
  each "$LIST" awk '
    function emit(name, line) {
      if (name ~ /^(if|for|while|switch|catch|return|new|class|function|else)$/) return
      priv = (line ~ /(^|[^A-Za-z])(private|protected|fileprivate|defp)[ \t]/ || name ~ /^_[^_]/ ||
              (FILENAME ~ /\.go$/ && name ~ /^[a-z]/)) ? 1 : 0
      print name "\t" FILENAME "\t" priv
    }
    {
      line = $0; s = line
      # keyword-led definitions: function, def, defp, fn, func, fun, sub
      while (match(s, /(^|[^A-Za-z0-9_])(function|defp|def|fn|func|fun|sub)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^[^A-Za-z]*[a-z]+[ \t]+/, "", t); emit(t, line)
      }
      # Go methods: func (r *T) Name(
      if (match(line, /func[ \t]*\([^)]*\)[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
        t = substr(line, RSTART, RLENGTH); sub(/^.*\)[ \t]*/, "", t); emit(t, line)
      }
      # modifier-led methods: public/private/protected/internal ... name(
      if (line !~ /(function|def|fn|fun)[ \t]/ &&
          match(line, /(public|private|protected|internal)[ \t][^=;(]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) {
        t = substr(line, RSTART, RLENGTH); sub(/[ \t]*\($/, "", t); sub(/^.*[^A-Za-z0-9_]/, "", t); emit(t, line)
      }
      # JS/TS arrow and function-expression bindings
      if (match(line, /(const|let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*(:[^=]+)?=[ \t]*(async[ \t]*)?(\(|function)/)) {
        t = substr(line, RSTART, RLENGTH); sub(/^(const|let|var)[ \t]+/, "", t); sub(/[^A-Za-z0-9_].*$/, "", t); emit(t, line)
      }
    }' | sort -u > "$TMP/fn"
  awk -F'\t' -v skip="$SKIP" '
    BEGIN { n = split(skip, w, /[ \t]+/); for (i = 1; i <= n; i++) if (w[i] != "") bad[w[i]] = 1 }
    $1 !~ /^(test|it|describe)/ && !($1 in bad) { c[$1]++; p[$1] += $3; if (c[$1] <= 3) loc[$1] = loc[$1] " " $2 }
    END { for (k in c) if (c[k] >= 2) printf "%d\t%d\t%s\t%s\n", c[k], p[k], k, loc[k] }' "$TMP/fn" |
    sort -t "$(printf '\t')" -k2,2nr -k1,1nr | head -50

  echo
  echo "## 3. String literals repeated across files (>= $MIN files, >= 6 uses) [$LABEL]"
  echo "Columns: uses  files  literal"
  each "$LIST" awk -v q="'" -v min="$MIN" '
    BEGIN { re = q "[^" q "\\\\]+" q "|\"[^\"\\\\]+\"" }
    /^[ \t]*(import|use|require|from|export .* from|#|\/\/|\*|--)/ { next }
    {
      s = $0
      while (match(s, re)) {
        lit = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        if (length(lit) < 6 || length(lit) > 62) continue
        if (lit ~ /^.(\.|\/|@|#|[a-z]+:\/\/)/ || lit !~ /[A-Za-z]/) continue
        n[lit]++; if (!((lit, FILENAME) in seen)) { seen[lit, FILENAME] = 1; f[lit]++ }
      }
    }
    END { for (k in n) if (n[k] >= 6 && f[k] >= min) printf "%d\t%d\t%s\n", n[k], f[k], k }' |
    sort -t "$(printf '\t')" -k1,1nr | head -40

  echo
  echo "## 4. Identical code lines repeated across files (>= $MIN files; clone signal) [$LABEL]"
  echo "Columns: files  uses  line"
  each "$LIST" awk -v min="$MIN" '
    {
      l = $0; gsub(/^[ \t]+|[ \t]+$/, "", l)
      if (length(l) < 45 || l ~ /^(import|use|require|from|#|\/\/|\*|\/\*|--)/ || l ~ /^[})\];,]+$/) next
      n[l]++; if (!((l, FILENAME) in seen)) { seen[l, FILENAME] = 1; f[l]++ }
    }
    END { for (k in n) if (f[k] >= min) printf "%d\t%d\t%s\n", f[k], n[k], k }' |
    sort -t "$(printf '\t')" -k1,1nr -k2,2nr | head -40
}

echo
echo "## 1. Largest source files (god-unit candidates)"
head -25 "$TMP/sizes"

analyze "$TMP/files" source
analyze "$TMP/tests" tests

echo
echo "## 5. Same file name in different directories (parallel versions, copied components)"
awk -F/ '{ n = $NF; if (n ~ /^(index|mod|main|__init__|types|utils|routes|page|layout|README)\./) next; c[n]++; p[n] = p[n] " " $0 }
  END { for (k in c) if (c[k] >= 2) printf "%d\t%s\t%s\n", c[k], k, p[k] }' "$TMP/files" | sort -rn | head -25

echo
echo "## 6. Files with the most catch-all style handlers"
each "$TMP/files" grep -cE 'catch[ \t]*[({]|except[ \t:]|rescue([ \t]|$)|recover\(\)|catch_unwind' /dev/null |
  awk -F: '$NF > 0' | sort -t: -k2,2nr | head -15 || true

echo
echo "## 7. Lock, transaction, retry, rate-limit and cache hot spots (files per concept)"
for pat in \
  'for update|lockforupdate|select_for_update|with_for_update|lock table|mutex|synchronized|flock|advisory' \
  'transaction|@transactional|atomic\(' \
  'retry|backoff|sleep\(|time\.sleep' \
  'rate.?limit|throttle|[^0-9]429[^0-9]' \
  'cache|memoi[sz]e|lru_cache|localstorage'; do
  n=$(each "$TMP/files" grep -liE "$pat" | wc -l | tr -d ' ')
  printf '%s files  %s\n' "$n" "$pat"
done

echo
echo "End of index. Hand sections 2-4 to the scouts as leads for categories 1 and 13-15."
