#!/usr/bin/env bash
# Minimal assertion helpers. Sourced by every tests/**/test_*.sh.
ASSERT_FAILURES=${ASSERT_FAILURES:-0}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok:   %s\n' "$label"
  else
    printf 'FAIL: %s\n      expected: %q\n      actual:   %q\n' "$label" "$expected" "$actual"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'ok:   %s\n' "$label"
  else
    printf 'FAIL: %s\n      missing: %q\n      in:      %q\n' "$label" "$needle" "$haystack"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}

assert_file_exists() {
  local path="$1" label="$2"
  if [[ -e "$path" ]]; then
    printf 'ok:   %s\n' "$label"
  else
    printf 'FAIL: %s\n      no such path: %s\n' "$label" "$path"
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}

assert_exit() {
  local expected="$1"; shift
  local label="$1"; shift
  local code=0
  "$@" >/dev/null 2>&1 || code=$?
  assert_eq "$code" "$expected" "$label (exit)"
}
