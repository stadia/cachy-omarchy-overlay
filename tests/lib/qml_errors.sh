#!/usr/bin/env bash
# QML error counting for the live tests' shell journals.
#
# Qt >= 6.12 (with Quickshell 0.3.2) makes the pinned upstream shell log bursts of
# "TypeError: Cannot read property '<x>' of undefined" scene warnings (location
# column -1) for bindings on the Color/Style singletons (Color.tooltip.background,
# ...) while the shell starts and as panels first open. The surfaces still render.
# It reproduces with the upstream tree verbatim, so it is not ours to fix.
#
# The exclusion is exactly: Qt >= 6.12, a `scene` warning at a `.qml[N:-1]`
# location, and a property from the measured colour-token set below. It is NOT
# limited to startup or to particular files (the burst spans Ui/, Commons/ and
# several plugins), so the property set is what keeps it narrow: a TypeError on
# any other property, any other error kind, or any other location still counts,
# and on older Qt nothing is excluded. Revisit when upstream or Quickshell stops
# emitting it; re-measure the set from a live journal if a new token appears.
COO_QML_ERROR_RE='ReferenceError|TypeError|is not a type|Cannot assign|unavailable'
COO_QML_BURST_PROPS='border|background|text|scrim|selectedText|selectedBackground|placeholder|selectedBorder|selection|borderActive|active|borderError|accent|unselectedBorder|countdown|[a-z]+\.(selected-)?border-alpha'
COO_QML_STARTUP_UNDEFINED_RE="scene.*\\.qml\\[[0-9]+:-1\\]: TypeError: Cannot read property '($COO_QML_BURST_PROPS)' of undefined\$"

coo_qt_version() {
  if [[ -n ${COO_QT_VERSION:-} ]]; then
    printf '%s\n' "$COO_QT_VERSION"
    return
  fi
  pacman -Q qt6-declarative 2>/dev/null | awk '{sub(/-[0-9.]+$/, "", $2); print $2}'
}

# True when the installed Qt is >= 6.12.
coo_qt_has_startup_undefined_burst() {
  local v major minor
  v=$(coo_qt_version)
  major=${v%%.*}
  minor=${v#*.}; minor=${minor%%.*}
  [[ $major =~ ^[0-9]+$ && $minor =~ ^[0-9]+$ ]] || return 1
  (( major > 6 || (major == 6 && minor >= 12) ))
}

# coo_count_qml_errors FILE — prints the number of QML error lines in FILE.
coo_count_qml_errors() {
  local file=$1 total known=0
  total=$(grep -ciE "$COO_QML_ERROR_RE" "$file")
  if coo_qt_has_startup_undefined_burst; then
    known=$(sed 's/\x1b\[[0-9;]*m//g' "$file" | grep -E "$COO_QML_STARTUP_UNDEFINED_RE" | grep -ciE "$COO_QML_ERROR_RE")
  fi
  printf '%s\n' "$((total - known))"
}

# coo_report_known_qml_burst FILE — evidence line so a green run shows what was excluded.
coo_report_known_qml_burst() {
  local file=$1 total
  total=$(coo_count_qml_errors "$file")
  if coo_qt_has_startup_undefined_burst; then
    printf '      FINDING: Qt %s 시작 경고 %s줄 제외 (undefined 읽기 TypeError), 그 밖의 오류 %s줄\n' \
      "$(coo_qt_version)" "$(( $(grep -ciE "$COO_QML_ERROR_RE" "$file") - total ))" "$total"
  fi
}
