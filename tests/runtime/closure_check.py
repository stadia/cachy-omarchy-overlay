#!/usr/bin/env python3
"""helper -> external command -> Arch package -> depends class closure audit.

Reads an extracted install tree (not the source tree) so the audit matches
what users actually receive.  Pure analysis: no side effects beyond reading
files and read-only `pacman -Qqo` lookups.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Shell builtins/keywords never resolve to a package.
BUILTINS = {
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
    "case", "esac", "function", "select", "in", "time", "coproc",
    "echo", "cd", "pwd", "export", "local", "readonly", "declare", "typeset",
    "unset", "set", "shift", "return", "exit", "eval", "exec", "source",
    "trap", "read", "test", "true", "false", "wait", "shopt", "getopts",
    "break", "continue",
    "command", "builtin", "type", "hash", "alias", "unalias", "let", "mapfile",
    "printf_",  # placeholder guard; printf itself is mapped in the tsv
}
# Wrappers that prefix a real command; the token after them is the command.
PREFIXES = {"sudo", "setsid", "nohup", "exec", "command", "env", "uwsm-app"}

# `{`/`}` only count as command-grouping separators when not part of a
# `${VAR}` parameter expansion — a bare `[{}]` in the class matches every
# `${...}` brace too, which turns every referenced variable name into a
# fake "command" (the dominant source of noise before this fix).
CMD_RE = re.compile(
    # `}` closes a `{ cmd; }` group only when set off by whitespace/`;`
    # (bash requires that separation); bare `}` immediately after a word
    # is a parameter-expansion close (`${MINUTES}m`), not a separator.
    r"(?:^|[|;&()]|(?<!\$)\{|(?<=[\s;])\}|\$\(|`|&&|\|\||\bthen\b|\bdo\b|\belse\b)"
    r"[ \t]*([A-Za-z_][A-Za-z0-9_.-]*)"
)
# `NAME=`, `NAME+=`, `NAME[idx]=` immediately after a CMD_RE match means it
# was assignment position, not command position — checked against the raw
# line via match.end(), never embedded in CMD_RE itself. Embedding it as a
# trailing negative lookahead let the engine backtrack the greedy token
# character-by-character until some truncated prefix satisfied the
# lookahead (e.g. "action=" falsely matching as "actio"); this form runs
# once against the regex's own maximal match, so it cannot truncate it.
ASSIGN_TAIL_RE = re.compile(r"(?:\[[^\]]*\])?\+?=(?!=)")
# `exec {fd_var}>file` / `exec {fd_var}>&-` is bash's auto-assigned file
# descriptor syntax, not a `{ ...; }` command group. Its bare `{` (not
# preceded by `$`) still passes as a CMD_RE separator, so `fd_var` reads
# as a fresh command unless it's recognized here by what follows it.
FD_VAR_TAIL_RE = re.compile(r"\}\s*(?:[0-9]+)?(?:<|>)")
# re.MULTILINE is required: FUNC_RE.findall() runs against the whole file
# text (not per line, unlike CMD_RE), so a bare `^` would anchor only to
# byte 0 of the file and silently miss every function defined past line 1
# — which is most of them. Without this every local helper function name
# leaks into the external-command set as a false UNMAPPED_COMMAND.
FUNC_RE = re.compile(
    r"^[ \t]*(?:function[ \t]+)?([A-Za-z_][A-Za-z0-9_-]*)[ \t]*\(\)", re.M
)
# Segments must be non-empty so a dynamically built name like
# `"omarchy-hw-$KIND"` yields no match at all rather than the truncated,
# unresolvable literal "omarchy-hw-".
#
# The leading boundary must refuse a `cachy-`-style prefix, not just
# require *a* boundary. `\b` alone is satisfied between "-" and "o"
# (a hyphen is a non-word character), so `\bomarchy-` matched inside
# "cachy-omarchy-launcher" -- our own overlay's command, staged and
# real -- and silently stripped the "cachy-" off, reporting it as an
# unstaged upstream helper nobody had written yet.
#
# 다만 "앞 글자가 하이픈이면 무조건 거부"는 너무 넓다. 그 형태는 bash 의
# `:-` 파라미터 확장 기본값 안에 있는 진짜 호출
# (`${CUSTOM_EXEC:-omarchy-launch-webapp $APP_URL}`)까지 함께 버린다.
# 판별 기준은 하이픈 자체가 아니라 하이픈 앞에 오는 글자다 —
# 단어 문자면 그 하이픈은 더 긴 식별자의 일부이고(`cachy-omarchy-launcher`,
# 설정 파일 이름 `90-omarchy-speaker-tuning.conf`), `:` 같은 비단어
# 문자면 연산자다. 그래서 고정 폭 lookbehind 둘을 연달아 둔다: 바로 앞이
# 단어 문자인 경우와, 바로 앞 두 글자가 `단어문자 + 하이픈`인 경우만 거부.
# 진짜 omarchy-* 이름은 따옴표·슬래시·대괄호·백틱·`:-`·줄 시작 뒤에 온다.
OMARCHY_RE = re.compile(
    r"(?<![A-Za-z0-9_])(?<![A-Za-z0-9_]-)(omarchy-[a-z0-9]+(?:-[a-z0-9]+)*)"
)
# 원문에서 omarchy-* 를 수확할 때만 필요한 가드.
#
# OMARCHY_RE 의 세그먼트는 non-empty 라서 `"omarchy-hw-$KIND"` 는
# `omarchy-hw` 라는 **잘린 리터럴**로 매치된다. 전처리된 텍스트에서는
# 따옴표 블랭킹이 이 줄을 통째로 지워 문제가 드러나지 않았지만, 원문을
# 읽는 순간 그 잘린 이름이 루트 큐에 들어가 실재하지 않는
# UNSTAGED_REACHABLE 을 만든다. 매치 바로 뒤가 `-` + 확장 시작
# (`$`, `{`)이면 그 이름은 동적 조립의 접두사일 뿐이므로 버린다.
DYNAMIC_TAIL_RE = re.compile(r"-\$|-\{")
# 매치 바로 뒤가 확장자면 명령이 아니라 **파일 이름**이다
# (`omarchy-color-theme.json`, `omarchy-screenrecord.log`,
# `omarchy-1password-lock.lock`). 라운드 5 의 lookbehind 가 왼쪽에서 하는
# 판정(`90-omarchy-...` 은 파일)의 오른쪽 대칭이다. 실행 가능한 이름이
# 점 뒤 확장자를 달고 명령 위치에 오는 경우는 없다.
FILENAME_TAIL_RE = re.compile(r"\.[A-Za-z0-9]")
# `omarchy-foo()` 는 **정의**이지 호출이 아니다(bash 함수 정의 문법).
# menu/MenuModel.js 는 생성 스크립트 서두에 `omarchy-pkg-present() { ... }`
# 같은 함수를 인라인으로 정의하는데, 그 이름들이 업스트림 bin/ 에도 실재해
# 인벤토리 필터를 통과한다 — 그러나 스크립트가 스스로 정의하므로 스테이징
# 결함이 아니다. 정의는 호출이 아니라는 사실 하나로 갈라낸다.
FUNC_DEF_TAIL_RE = re.compile(r"\s*\(\s*\)")
# 매치가 속한 경로 토큰이 런타임 데이터 디렉터리를 가리키면 그것은 마커
# 파일/디렉터리 이름이지 실행 파일이 아니다
# (`"${XDG_RUNTIME_DIR:-/tmp}/omarchy-capture-region-window"`).
# `"$OMARCHY_PATH/bin/omarchy-clipboard-paste-file"` 처럼 실행 파일을
# 가리키는 경로와 구분하려면 슬래시만으로는 부족하고 경로의 뿌리를 봐야
# 한다. 토큰 경계는 공백·따옴표·`$(`·백틱·`=` 로 잡는다.
RUNTIME_PATH_ROOTS = ("/tmp/", "XDG_RUNTIME_DIR", "XDG_CACHE_HOME", "/var/tmp/")
PATH_TOKEN_BREAK = set(" \t\n\"'`=(){}[],;|&<>")


def _path_token_before(text, start):
    """매치 시작점 앞의 경로 토큰을 되짚어 돌려준다."""
    i = start
    while i > 0 and text[i - 1] not in PATH_TOKEN_BREAK:
        i -= 1
    # `${XDG_RUNTIME_DIR:-/tmp}/...` 는 `}` 에서 끊기므로 한 칸 더 넓혀
    # 파라미터 확장 본문까지 함께 본다.
    j = i
    if j > 0 and text[j - 1] == "}":
        depth = 0
        while j > 0:
            j -= 1
            if text[j] == "}":
                depth += 1
            elif text[j] == "{":
                depth -= 1
                if depth == 0:
                    break
    return text[j:start]


def omarchy_harvest_text(raw_text):
    """omarchy-* 루트 수확 전용 전처리 — 따옴표는 남기고 주석/heredoc 만 지운다.

    preprocess_bash() 를 그대로 쓰면 strip_quoted_noise() 가 큰따옴표
    payload 를 지워, 큰따옴표 안에서만 불리는 헬퍼가 그래프에서 사라진다
    (실측: 스테이징 헬퍼 137개 중 53개에 걸쳐 81개 이름). 반대로 원문을
    통째로 쓰면 주석 산문이 명령으로 새어 든다 — 실측된 최악의 예는 우리
    자신의 compat 스크립트 주석에 있는 `omarchy-dev` 로, 존재하지 않는
    명령에 대한 예외 행을 쓸 뻔했다.

    주석과 heredoc 은 정의상 명령 텍스트가 아니므로 지우고, 따옴표는
    남긴다. 줄 끝 주석은 지우지 않는다 — 따옴표를 블랭킹하지 않은
    상태에서 `#` 은 문자열 안 문자와 구분되지 않기 때문이다.
    """
    text = LINE_CONT_RE.sub(" ", raw_text)
    text = strip_comment_lines(text)
    text = strip_heredocs(text)
    return text


def omarchy_names(raw_text):
    """bash 원문에서 omarchy-* 루트를 수확한다."""
    text = omarchy_harvest_text(raw_text)
    out = set()
    for m in OMARCHY_RE.finditer(text):
        if DYNAMIC_TAIL_RE.match(text, m.end()):
            continue
        if FILENAME_TAIL_RE.match(text, m.end()):
            continue
        if FUNC_DEF_TAIL_RE.match(text, m.end()):
            continue
        before = _path_token_before(text, m.start())
        if "/" in before and any(r in before for r in RUNTIME_PATH_ROOTS):
            continue
        out.add(m.group(1))
    return out


HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
# `case` arm labels — `chromium.desktop) echo ...` or
# `chromium|chrome|brave) ...` — sit in the exact position CMD_RE treats as
# command position (line start, or right after `|`), so each pattern
# alternative reads as an invoked command. A label list ending in `)` is
# unambiguous shell syntax; strip it before scanning the rest of the line.
_CASE_ARM_WORD = r'(?:[A-Za-z0-9_.*?+@!^:/\[\]-]+|"")'  # "" = empty-string pattern
CASE_ARM_RE = re.compile(
    rf"^[ \t]*{_CASE_ARM_WORD}(?:[ \t]*\|[ \t]*{_CASE_ARM_WORD})*[ \t]*\)"
)


def strip_heredocs(text):
    """Drop heredoc bodies before scanning, idempotently.

    A heredoc body is data (jq/awk/sql/JSON payloads embedded in these
    helpers), not shell command text. Left in, it floods the scan with
    every bare word in the payload as a fake command.

    Must be safe to run twice on its own output. The original version
    left the opening line's `<<TOKEN` marker untouched while dropping the
    delimiter line; a second pass would then match that same marker
    again, fail to find the (now-deleted) delimiter, and silently
    consume the rest of the file as heredoc body (omarchy-menu was
    truncated 28 -> 21 lines this way once preprocessing ran twice).
    Blanking the `<<TOKEN` marker itself after consuming its heredoc
    means a repeat pass finds nothing left to match.
    """
    lines = text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = HEREDOC_RE.search(line)
        if m:
            delim = m.group(2)
            out.append(line[:m.start()] + " " * (m.end() - m.start()) + line[m.end():])
            i += 1
            while i < len(lines) and lines[i].strip() != delim:
                i += 1
            i += 1  # skip the delimiter line itself
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


def strip_quoted_noise(text):
    """Blank quoted content in one linear, quote-state-tracking pass.

    Single- and double-quote handling cannot be two independent regex
    passes over the whole file: an ordinary English apostrophe inside a
    *double*-quoted string ("Can't disable...") is, to a standalone
    single-quote regex, an unmatched opening `'` — it then pairs with
    whatever the next *unrelated* `'` in the file happens to be (often a
    single-quoted jq/awk program much later) and blanks every real line
    in between, including function definitions. Tracking state char by
    char instead of via `re.sub` avoids that cross-contamination.

    Single-quoted spans are blanked outright (bash never expands them, so
    no command substitution can happen inside). Double-quoted spans are
    blanked except for `$(...)`/`` ` ``-substitutions, which still run and
    must keep matching (`VAR="$(some-command)"`), and are the only reason
    this codebase's inline awk/jq programs (which need `$var`
    interpolation, so can't be single-quoted) don't leak their own
    `{ }` / `|` / `;` into CMD_RE as fake command separators.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j == -1:
                out.append(c)
                i += 1
                continue
            out.append("'")
            out.extend("\n" if ch == "\n" else " " for ch in text[i + 1:j])
            out.append("'")
            i = j + 1
            continue
        if c != '"':
            out.append(c)
            i += 1
            continue
        out.append('"')
        i += 1
        while i < n and text[i] != '"':
            if text[i] == "\\" and i + 1 < n:
                out.append("  ")
                i += 2
            elif text[i:i + 2] == "$(":
                # Recurse: a command substitution runs a nested command
                # line, which can itself contain quoted strings (the
                # `downstream="$(... | awk -v x="$y" '...')"` shape this
                # codebase uses for awk/jq pipelines). Copying the span
                # verbatim, as an earlier version of this function did,
                # left that inner single-quoted awk program fully exposed
                # to CMD_RE with none of its `{`/`;`/`|` noise removed.
                depth, j = 1, i + 2
                while j < n and depth > 0:
                    if text[j] == "(":
                        depth += 1
                    elif text[j] == ")":
                        depth -= 1
                    j += 1
                inner_end = j - 1 if depth == 0 else j
                out.append("$(")
                out.append(strip_quoted_noise(text[i + 2:inner_end]))
                out.append(text[inner_end:j])
                i = j
            elif text[i] == "`":
                j = text.find("`", i + 1)
                inner_end = j if j != -1 else n
                out.append("`")
                out.append(strip_quoted_noise(text[i + 1:inner_end]))
                if j != -1:
                    out.append("`")
                    i = j + 1
                else:
                    i = n
            else:
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
        if i < n:
            out.append('"')
            i += 1
    return "".join(out)


def strip_arithmetic(text):
    """Blank the body of `(( ... ))` / `$(( ... ))` arithmetic evaluation.

    Bash arithmetic reuses `&&`, `||`, `(` and `)` with C semantics, not
    shell command-separator semantics (`(( a && b ))` is not two chained
    commands). Left in, CMD_RE reads the second `(` of `((` as a fresh
    command-grouping separator and every operand as an invoked command.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        if text[i:i + 2] == "((":
            depth, j = 2, i + 2
            body_start = j
            while j < n and depth > 0:
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                j += 1
            body_end = j - 2 if depth == 0 else j
            out.append("((")
            out.extend("\n" if ch == "\n" else " " for ch in text[body_start:body_end])
            out.append(text[body_end:j])
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


ARRAY_LITERAL_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\+?=\(")


def strip_array_literals(text):
    """Blank the body of `NAME=(word word ...)` array-literal assignments.

    The name itself is already excluded from CMD_RE by ASSIGN_TAIL_RE, but
    the `(` that opens the literal is a fresh, unrelated CMD_RE separator,
    so its first element (`names=(black red green ...)` -> "black") still
    reads as an invoked command.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        m = ARRAY_LITERAL_RE.match(text, i)
        if m:
            depth, j = 1, m.end()
            body_start = j
            while j < n and depth > 0:
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                j += 1
            body_end = j - 1 if depth == 0 else j
            out.append(text[i:body_start])
            out.extend("\n" if ch == "\n" else " " for ch in text[body_start:body_end])
            out.append(text[body_end:j])
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def strip_comment_lines(text):
    """Blank whole-line `#` comments before any quote scanning.

    Must run first: an apostrophe in a comment ("# doesn't lose a key...")
    is a real, unpaired `'` character. If quote-stripping runs before
    comments are removed, that stray quote desyncs single-quote pairing
    for the rest of the file, and every awk/jq body after it (correctly
    paired quotes and all) stops being recognized as quoted.
    """
    return "\n".join(
        "" if line.lstrip().startswith("#") else line for line in text.splitlines()
    )


LINE_CONT_RE = re.compile(r"\\\n")
# A backslash-escaped separator (`\;`, `` \` ``, ...) is a literal character
# passed to the command, not a shell operator — common in multi-line
# `tmux foo \; bar \; baz \` invocations. Neutralize it so CMD_RE doesn't
# treat each escaped-`;`-separated word as a fresh command.
ESCAPED_SEP_RE = re.compile(r"\\([|;&(){}`])")
# `[[ $x =~ ^(a|b|c)$ ]]` — bash's own extended-regex syntax for the `=~`
# operator, written bare (no quotes needed or wanted around it). Its `(`
# and `|` read exactly like command grouping / piping to CMD_RE. Blank
# from `=~` to the closing `]]` of the enclosing `[[ ... ]]` test.
#
# A naive "first `]]`" search is not good enough: POSIX bracket
# expressions inside the pattern (`[[:space:]]`, `[0-9]`) contain their
# own `]`, and `[[:space:]]` even contains a literal `]]` of its own
# (the class token's `]` immediately followed by the bracket
# expression's own `]`) — that terminates the blank early and leaves
# the rest of the regex, `x` included, exposed to CMD_RE as command
# text. _skip_bracket_expr jumps over an entire `[...]` (POSIX class
# tokens included) as one unit so only a `]]` outside any bracket
# expression can end the span.
def _skip_bracket_expr(text, i, n):
    """`text[i]` is '['. Returns the index just past its matching ']'."""
    j = i + 1
    if j < n and text[j] == "^":
        j += 1
    if j < n and text[j] == "]":
        j += 1  # ']' right after '[' / '[^' is a literal member, not a close
    while j < n:
        if text[j:j + 2] in ("[:", "[.", "[="):
            closer = text[j + 1] + "]"
            end = text.find(closer, j + 2)
            j = end + 2 if end != -1 else n
            continue
        if text[j] == "]":
            return j + 1
        if text[j] == "\n":
            return j
        j += 1
    return j


def strip_regex_match(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        if text[i:i + 2] != "=~":
            out.append(text[i])
            i += 1
            continue
        j = i + 2
        while j < n:
            if text[j] == "[":
                j = _skip_bracket_expr(text, j, n)
                continue
            if text[j:j + 2] == "]]" or text[j] == "\n":
                break
            j += 1
        out.append("=~")
        out.extend("\n" if ch == "\n" else " " for ch in text[i + 2:j])
        i = j
    return "".join(out)


def preprocess_bash(text):
    """Strip everything that isn't real shell command text.

    Shared by bash_commands() and the omarchy-* root scan: both read
    staged helper source, and both would otherwise pick up matches from
    comments (`# omarchy:examples=omarchy-hw-display`), string/heredoc
    payloads, and dynamically-built names (`"omarchy-hw-$KIND"`) as if
    they were real invocations.
    """
    # Join backslash-newline continuations first: they make several source
    # lines one logical command line, which matters both for comment
    # detection below and so a continued line's first word isn't misread
    # as the start of a brand new command.
    text = LINE_CONT_RE.sub(" ", text)
    text = strip_comment_lines(text)
    text = strip_heredocs(text)
    text = strip_quoted_noise(text)
    text = strip_arithmetic(text)
    text = strip_array_literals(text)
    text = ESCAPED_SEP_RE.sub("  ", text)
    text = strip_regex_match(text)
    # Trailing (non-full-line) comments, now that they're safe to find: any
    # `#` still surviving at this point cannot be inside a string (those
    # were already blanked above), so a whitespace-preceded `#` here is
    # unambiguously a real comment, e.g. `... # extract value (ignores
    # inline comments)` — a case strip_comment_lines can't reach because
    # it only blanks comments that own their whole line.
    text = "\n".join(
        re.split(r"(?<=\s)#", line, maxsplit=1)[0] for line in text.splitlines()
    )
    return text


SOURCE_RE = re.compile(r"(?:^|;)[ \t]*(?:source|\.)[ \t]+([A-Za-z_][A-Za-z0-9_.-]*)", re.M)


def scan_commands(text, extra_defined=frozenset()):
    """Commands appearing in command position, minus builtins and local funcs.

    `text` must already be preprocess_bash()-clean. Kept separate from
    bash_commands() so callers that need the cleaned text for something
    else too (the omarchy-* root scan also runs OMARCHY_RE over it) can
    preprocess exactly once instead of relying on bash_commands() to do
    it again. strip_heredocs() is verified idempotent (heredoc markers
    are blanked once consumed, so a repeat pass matches nothing); this
    only relies on preprocessing running exactly once per file, which
    the split guarantees by construction rather than by idempotency of
    every step (strip_quoted_noise is not verified idempotent on all
    inputs, e.g. Python triple-quoted strings scanned as bash).

    `extra_defined` is for functions this file doesn't define itself but
    pulls in via `source omarchy-shell-config` — a single-file scan can't
    see those without help; the caller resolves `source` targets against
    the staged set and passes their function names in here (e.g.
    omarchy-bar calls `fail`/`commit`, both defined only in the
    omarchy-shell-config it sources).
    """
    defined = set(FUNC_RE.findall(text)) | set(extra_defined)
    found = set()
    for line in text.splitlines():
        m = CASE_ARM_RE.match(line)
        if m:
            line = " " * m.end() + line[m.end():]
        for m in CMD_RE.finditer(line):
            if ASSIGN_TAIL_RE.match(line, m.end()) or FD_VAR_TAIL_RE.match(line, m.end()):
                continue
            found.add(m.group(1))
        # `sudo foo` / `setsid foo`: also take the following word.
        for pref in PREFIXES:
            for m in re.finditer(
                rf"\b{re.escape(pref)}\b[ \t]+(?:--[ \t]+)?([A-Za-z_][A-Za-z0-9_.-]*)",
                line,
            ):
                found.add(m.group(1))
    return {c for c in found if c not in BUILTINS and c not in defined}


def bash_commands(text):
    """preprocess_bash() + scan_commands(), for callers with raw source text."""
    return scan_commands(preprocess_bash(text))


QML_ARRAY_RE = re.compile(r"command:\s*\[(.*?)\]", re.S)
QML_STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
# `Quickshell.execDetached([argv0, argv1, ...])` — same argv-array shape as
# a `command:` property, just spelled as a direct call instead.
EXEC_DETACHED_RE = re.compile(r"Quickshell\.execDetached\(\s*\[(.*?)\]", re.S)
# `<Bar>.run("shell command line")` — a single string that's a full shell
# command line (may itself contain `$(...)`), not an argv array.
# A command name never contains whitespace or quote characters; this
# rejects stray non-command quoted strings an array-literal scan can
# pick up as "the first quoted string" (a join() separator, an empty
# placeholder, ...) that would otherwise pass the merely-truthy check.
COMMAND_SHAPE_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*$")
RUN_CALL_RE = re.compile(r'\.run\(\s*"((?:[^"\\]|\\.)*)"')
# `someProc.command = ["omarchy-foo", ...]` — the JS-field-assignment
# spelling of the same argv array a `command:` QML property declares.
# Process helpers in this codebase use this form almost exclusively
# (Service.qml files especially), and several roots have *no other* call
# site — losing this form doesn't just drop sub-arguments off an
# already-found command, it drops whole omarchy-* helpers out of the
# reachable set entirely (confirmed: omarchy-network-qr,
# omarchy-network-password, omarchy-weather-location,
# omarchy-display-text-size, omarchy-network-speedtest,
# omarchy-bluetooth-device all had zero other invocation sites).
COMMAND_ASSIGN_HEAD_RE = re.compile(r"\w+\.command\s*=")


def _extract_bracket_arrays(s, max_arrays=4):
    """All top-level `[...]` bodies in s, via balanced-bracket scanning."""
    out = []
    i, n = 0, len(s)
    while i < n and len(out) < max_arrays:
        if s[i] == "[":
            depth, j = 1, i + 1
            start = j
            while j < n and depth > 0:
                if s[j] == "[":
                    depth += 1
                elif s[j] == "]":
                    depth -= 1
                j += 1
            out.append(s[start:j - 1])
            i = j
        else:
            i += 1
    return out


def command_assignment_arrays(text):
    """Array bodies from `.command = [...]`, ternary form included.

    `X.command = cond ? [...] : [...]` is common (two alternative argv
    arrays depending on runtime state, both genuinely reachable). This
    codebase's QML/JS relies on ASI (no trailing `;`), so the value can
    spill across a few following lines for the ternary form — a fixed
    lookahead window stands in for real statement-boundary parsing.
    """
    arrays = []
    for m in COMMAND_ASSIGN_HEAD_RE.finditer(text):
        window = text[m.end():m.end() + 400]
        semi = window.find(";")
        if semi != -1:
            window = window[:semi]
        arrays.extend(_extract_bracket_arrays(window))
    return arrays


RETURN_ARRAY_RE = re.compile(r"return\s*\[(.*?)\]", re.S)


def return_arrays(text):
    """Array bodies from `return [...]` inside a helper function.

    Some panels build the argv array in a small helper (`function
    deviceCommand(action, address) { return ["omarchy-bluetooth-device",
    action, address] }`) and only ever call it indirectly
    (`Quickshell.execDetached(deviceCommand(...))`), so neither the
    `command:`/`execDetached([`/`.command =` literal-array forms nor a
    plain function-call argument to execDetached ever shows the array
    itself at the call site.

    Unlike the other four invocation shapes, a bare `return [...]` is
    NOT unambiguous by itself -- plain data (`return ["Sun", "Mon", ...,
    "Sat"][d.getDay()]`) is built the exact same way and was caught here
    before this filter was added. The distinguishing signal is that an
    argv-building helper almost always threads a caller-supplied
    variable through alongside the literal command name (`action,
    address` above); an all-literal array of short strings indexed by a
    JS expression is the weekday/data-table shape instead. Requiring at
    least one bare (non-quoted) identifier in the array body keeps the
    real case and drops the data-table one.
    """
    arrays = []
    for body in RETURN_ARRAY_RE.findall(text):
        if re.search(r"[A-Za-z_]", QML_STR_RE.sub("", body)):
            arrays.append(body)
    return arrays


def _argv0_or_shell(body):
    """First array element's basename; `bash -c` payloads are re-parsed.

    Takes the raw array body text (not just the pre-extracted quoted
    strings) because trusting `parts[1:]` as shell-script payloads
    depends on whether the array was fully literal.

    The nightlight service is the case that forces the bash/sh branch: it
    does not call hyprsunset as argv[0], it calls it inside a `bash -c`
    string. `root.omarchyPath + "/bin/omarchy-foo"` concatenations are
    common for the first element too -- QML_STR_RE only sees the string
    literal part, so the basename split still lands on "omarchy-foo".

    But a fully-literal `["bash", "-c", "omarchy-hyprland-session-locked"]`
    and a partially-literal `["bash", "-c", Model.enterpriseConnectScript,
    "nmcli-eap", ssid, identity]` produce the *same* parts list once
    QML_STR_RE has stripped the non-string elements out -- ["bash", "-c",
    "<word>"] either way. In the first, that third string genuinely is
    the `-c` script. In the second, the real script is a JS variable
    reference invisible to QML_STR_RE, and "nmcli-eap" is really the
    script's own positional argument ($1), not further shell code. The
    two are only distinguishable by looking at the *raw* array body: if
    anything in it besides quoted strings and punctuation survives (a
    bare identifier), some element was a variable, so parts[1:] cannot
    be trusted as the actual script text and is left unscanned.
    """
    parts = QML_STR_RE.findall(body)
    if not parts:
        return set()
    head = parts[0].split("/")[-1]
    if head in ("bash", "sh"):
        if re.search(r"[A-Za-z_]", QML_STR_RE.sub("", body)):
            return set()
        found = set()
        for payload in parts[1:]:
            found |= bash_commands(payload)
        return found
    # Only accept command-name-shaped heads. A `return [...]` array can
    # capture a non-command quoted string that just happens to be
    # QML_STR_RE's first match -- `aliases.join(" ")`'s separator
    # argument, for instance, leaves " " as the only quoted literal in
    # its array, and a bare space is truthy in Python so `if head` alone
    # would not have caught it.
    if not COMMAND_SHAPE_RE.match(head):
        return set()
    return {head}


# QML/JS 문자열 리터럴 — 큰따옴표와 작은따옴표 둘 다. JS 쪽은 작은따옴표를
# 흔히 쓰고, QML 도 작은따옴표를 허용한다.
# 개행을 넘지 않는다. QML/JS 의 문자열 리터럴은 원시 개행을 담지 못하므로,
# 개행을 허용하면 영어 산문 속 아포스트로피 두 개가 짝지어져 주석 여러 줄을
# 통째로 "문자열" 로 삼킨다 — 실측으로 `omarchy-weather-icon` 이 그렇게
# 잡혔다(Panel.qml 주석의 "…entry." + "…icon's" 사이 구간).
QML_ANY_STR_RE = re.compile(r"\"((?:[^\"\\\n]|\\.)*)\"|'((?:[^'\\\n]|\\.)*)'")


def qml_omarchy_names(text):
    """QML/JS 의 **모든** 문자열 리터럴에서 omarchy-* 이름을 수확한다.

    아래 qml_commands() 의 좁은 다섯 형태는 실제 호출 자리만 본다. 그것이
    필요했던 이유는, 예전 스캐너가 이름의 *모양*만으로 헬퍼 여부를 판정해서
    `WlrLayershell.namespace: "omarchy-background"`, `reloadableId:
    "omarchy-battery"` 같은 식별자 문자열이 전부 UNSTAGED_REACHABLE 로
    올라왔기 때문이다.

    1c 에서 핀된 업스트림 `bin/` 인벤토리가 ground truth 가 되면서 그 위험이
    사라졌다 — 저 식별자들은 인벤토리에 없으므로 헬퍼로 인정되지 않는다.
    그래서 이제는 넓게 훑고 인벤토리가 거르게 둔다.

    이 함수가 필요한 구체적 사례: `plugins/services/idle/Service.qml:54` 는
    스스로 `runProcess(process, label, command)` 를 정의하고 셸 문자열을 세
    번째 인자로 넘긴다. 좁은 다섯 형태 중 어느 것도 "바 identifier 호출 +
    문자열 payload" 를 잡지 못해, idle 서비스가 기본 150초마다 부르는
    `omarchy-launch-screensaver` 가 감사에서 통째로 빠져 있었다.

    반환값은 omarchy-* 이름 **뿐이다**. 외부 명령은 여기서 뽑지 않는다 —
    임의의 문자열에서 외부 명령을 뽑으면 UNMAPPED_COMMAND 가 쏟아지고,
    인벤토리 같은 ground truth 도 없다. 외부 명령은 계속 qml_commands() 의
    좁은 형태가 담당한다. 그래서 좁은 형태들은 없앨 수 없다.
    """
    found = set()
    for m in QML_ANY_STR_RE.finditer(text):
        payload = m.group(1) if m.group(1) is not None else m.group(2)
        if not payload:
            continue
        found |= omarchy_names(payload)
    return found


def qml_commands(text):
    """Commands referenced from actual invocation call sites only.

    이 좁은 다섯 형태(`command:` 배열, `Quickshell.execDetached([...])`,
    `<Bar>.run(...)`, `X.command = [...]`, `return [...]`)는 원래
    `reloadableId: "omarchy-battery"` 같은 식별자 문자열이
    UNSTAGED_REACHABLE 로 올라오는 것을 막으려고 도입됐다. omarchy-* 쪽에서는
    그 역할이 끝났다 — 1c 의 인벤토리가 판정하고, 넓은 수확을 담당하는
    qml_omarchy_names() 가 이 함수가 잡는 omarchy-* 를 **전부** 포함한다
    (실측: narrow 43개 ⊂ broad 81개, narrow 단독 0개).

    그럼에도 없앨 수 없다. 이 함수는 QML/JS 에서 **외부 명령**을 뽑는 유일한
    경로이기 때문이다 — curl, hyprctl, pkexec, pgrep, pkill, tailscale,
    xdg-terminal-exec, xkbcli 등 17개가 오직 여기서만 나온다. 외부 명령에는
    인벤토리 같은 ground truth 가 없으므로 임의의 문자열에서 뽑을 수 없다.
    즉 역할이 갈렸다: omarchy-* 는 넓게+인벤토리, 외부 명령은 좁은 형태.
    """
    found = set()
    for body in QML_ARRAY_RE.findall(text):
        found |= _argv0_or_shell(body)
    for body in EXEC_DETACHED_RE.findall(text):
        found |= _argv0_or_shell(body)
    for raw in RUN_CALL_RE.findall(text):
        # QML string-literal escapes -> the actual runtime string value.
        payload = raw.replace('\\"', '"').replace("\\\\", "\\")
        found |= bash_commands(payload)
    for body in command_assignment_arrays(text):
        found |= _argv0_or_shell(body)
    for body in return_arrays(text):
        found |= _argv0_or_shell(body)
    return {c for c in found if c not in BUILTINS}


def extract_bash_array_body(text, name):
    """Raw text between a `name=( ... )` array literal's own parens.

    A non-greedy `.*?\\)` regex stops at the *first* `)` anywhere in the
    text, including one sitting inside a quoted description string
    (`'foot: ... hook (OSC reload)'`) -- not the array's real
    terminator. That silently truncated `optdepends=(...)` to its first
    entry here: the parsed set was exactly `{'tmux'}` out of five,
    so `brightnessctl`/`ddcutil`/... were reported missing while
    already declared. `depends=(...)` has the same defect but happened
    to contain no parenthesis, so it parsed correctly by luck, not by
    construction.

    This scans char by char instead, tracking quote state so a `)`
    inside `'...'` or `"..."` is never mistaken for the terminator, and
    tracking paren depth so only the terminator matching this array's
    own opening `(` ends the scan.
    """
    m = re.search(rf"^{re.escape(name)}=\(", text, re.M)
    if not m:
        return ""
    i, n = m.end(), len(text)
    depth, in_quote, start = 1, None, i
    while i < n and depth > 0:
        c = text[i]
        if in_quote:
            if c == in_quote:
                in_quote = None
        elif c in ("'", '"'):
            in_quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return text[start:i]


def read_tsv(path, ncols):
    rows = []
    for lineno, raw in enumerate(Path(path).read_text().splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        cols = raw.split("\t")
        if len(cols) < ncols or not all(c.strip() for c in cols[:ncols]):
            raise SystemExit(f"{path}:{lineno}: expected {ncols} non-empty columns")
        rows.append([c.strip() for c in cols[:ncols]])
    return rows


def disabled_plugins(shell_json):
    """Empty set == every plugin is active, which is today's default."""
    cfg = json.loads(Path(shell_json).read_text())
    return set(cfg.get("disabledPlugins") or [])


def load_plugin_ids(plugroot):
    """Plugin directory (absolute Path) -> its manifest.json "id" field.

    `disabledPlugins` entries and PluginRegistry.qml's own comparison
    (Util.canonicalWidgetId(), confirmed to be an identity function) both
    key on this dotted manifest id (e.g. "omarchy.polkit"), not on a
    directory name — and plugins can nest (plugins/services/battery/),
    so a directory-name guess like `parts[0]` would land on "services"
    for half of them anyway.
    """
    ids = {}
    for manifest in plugroot.rglob("manifest.json"):
        try:
            data = json.loads(manifest.read_text())
        except (OSError, ValueError):
            continue
        pid = data.get("id")
        if pid:
            ids[manifest.parent] = pid
    return ids


def plugin_id_for(path, plugin_ids, plugroot):
    """Manifest id of the nearest ancestor directory that owns one."""
    d = path.parent
    while True:
        if d in plugin_ids:
            return plugin_ids[d]
        if d == plugroot or d.parent == d:
            return None
        d = d.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--map", required=True)
    ap.add_argument("--exceptions", required=True)
    ap.add_argument("--upstream-helpers", required=True)
    ap.add_argument("--emit-table", action="store_true")
    args = ap.parse_args()

    tree, repo = Path(args.tree), Path(args.repo)
    upstream = tree / "usr/share/cachy-omarchy/upstream"
    binroot = upstream / "bin"

    map_rows = read_tsv(args.map, 4)
    cmdmap = {r[0]: (r[1], r[2], r[3]) for r in map_rows}
    exceptions = {r[0]: (r[1], r[2]) for r in read_tsv(args.exceptions, 3)}
    # 핀된 업스트림의 헬퍼 이름 목록 — UNSTAGED_REACHABLE 의 ground truth.
    # 설치 트리만으로는 "업스트림에 그런 헬퍼가 있는가" 를 알 수 없다.
    # 설치 트리에는 우리가 스테이징한 것만 들어 있기 때문이다. 그래서 이
    # 스캐너는 여섯 라운드 동안 이름의 **모양**으로 헬퍼 여부를 추론했고,
    # 그 추론이 지금까지 나온 모든 오탐 부류의 단일 원인이었다 —
    # QML layershell namespace, reloadableId, 우리 자신의 cachy-omarchy-*,
    # 설정 파일 이름, 알림 hint 키, grep 패턴, echo 안내 문구. 모양은
    # 업스트림에 대한 사실이 아니다. 사실은 핀에 있고, 그것이 이 파일이다.
    upstream_helpers = {
        line.strip()
        for line in Path(args.upstream_helpers).read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }

    staged = {p.name: p for p in binroot.iterdir() if p.is_file()} if binroot.is_dir() else {}
    # coo_extract_overlay refuses to share a dest with coo_extract_pkg (it
    # rm -rf's the dest first), so the harness extracts the overlay package
    # into a `tree/overlay/` subdirectory rather than merging it into
    # `tree/`. The overlay package is what actually owns compat/bin, so
    # that is where its output lands.
    for extra in (
        tree / "overlay/usr/lib/cachy-omarchy/compat/bin",
        tree / "usr/lib/cachy-omarchy/compat/bin",
    ):
        if extra.is_dir():
            for p in extra.iterdir():
                if p.is_file():
                    staged.setdefault(p.name, p)

    disabled = disabled_plugins(repo / "overlay/defaults/shell.json")
    unmatched_disabled_plugins = set()

    # --- roots -----------------------------------------------------------
    roots = set()
    menu_suppressed = set()
    for name in ("bindings.conf", "bindings.lua"):
        text = (repo / "overlay/hypr" / name).read_text()
        roots |= set(OMARCHY_RE.findall(text))
    qml_seed = set()
    plugroot = upstream / "shell/plugins"
    matched_disabled = set()
    if plugroot.is_dir():
        plugin_ids = load_plugin_ids(plugroot)
        # *.js too, not just *.qml: NotificationLogic.js and friends run
        # commands from the same plugin trees but were invisible to a
        # *.qml-only glob.
        src_files = list(plugroot.rglob("*.qml")) + list(plugroot.rglob("*.js"))
        for src in src_files:
            pid = plugin_id_for(src, plugin_ids, plugroot)
            if pid is not None and pid in disabled:
                matched_disabled.add(pid)
                continue
            text = src.read_text(errors="replace")
            # qml_commands() only harvests actual invocation call sites
            # (command: arrays, execDetached([, .run(") — not every
            # substring in the file that happens to look like an
            # omarchy-* name (reloadableId, WlrLayershell.namespace, ...
            # are identifiers, not commands, and were manufacturing
            # UNSTAGED_REACHABLE findings for names nothing ever runs).
            qml_seed |= qml_commands(text)
            # 그리고 모든 문자열 리터럴에서 omarchy-* 를 따로 훑는다.
            # 인벤토리가 무엇이 헬퍼인지 판정하므로 넓게 훑어도 안전하다.
            # qml_seed 와 섞지 않는 이유: qml_seed 의 non-omarchy 이름은
            # external(외부 명령)로 흘러가는데, 여기서 나온 것은 전부
            # omarchy-* 이고 BFS 루트로만 쓰여야 한다.
            roots |= qml_omarchy_names(text)
    roots |= qml_seed
    # A non-empty disabledPlugins that matches no plugin id at all is a
    # silent typo/rot risk (this repo's least-forgivable failure mode),
    # not something to pass over quietly.
    for pid in sorted(disabled - matched_disabled):
        unmatched_disabled_plugins.add(pid)
    menu = upstream / "default/omarchy/omarchy-menu.jsonc"
    if menu.is_file():
        audit = (repo / "docs/COMMAND_AUDIT.md").read_text()
        known_bad = {
            m.group(1)
            for m in re.finditer(
                r"\|\s*`(omarchy-[a-z0-9-]+)`\s*\|\s*DISABLED\s*\|", audit
            )
        }
        menu_names = set(OMARCHY_RE.findall(menu.read_text()))
        # 이 차감은 규모가 큰 억제 통로다 — 예외 파일보다 훨씬 크면서
        # 사유도, 신선도 검사도, 생성 문서 노출도 없었다. 개수를 세어
        # --emit-table 이 단언 대상으로 내보내게 한다(산문에 손으로 적은
        # 숫자는 맵이 바뀌어도 green 인 채로 거짓이 될 수 있다).
        menu_suppressed |= menu_names & known_bad
        roots |= menu_names - known_bad

    # --- BFS over staged helpers ----------------------------------------
    sourced_funcs_cache = {}
    seen, queue, unstaged = set(), sorted(roots), set()
    not_upstream_helpers = set()
    # omarchy-* names from qml_commands() are folded into `roots` above
    # (`roots |= qml_seed`) and belong in the BFS so their staged/unstaged
    # status is checked, not dumped straight into `external` where they'd
    # need a nonexistent Arch package mapping.
    # Bare `omarchy` (no trailing hyphen) is upstream's own top-level
    # dispatcher (`omarchy osd --help`, `omarchy default browser ...`).
    # It shares the same staged/unstaged fate as every `omarchy-*` helper,
    # it just doesn't match that literal prefix.
    def is_omarchy_name(c):
        return c == "omarchy" or c.startswith("omarchy-")

    external = {c for c in qml_seed if not is_omarchy_name(c)}
    while queue:
        name = queue.pop()
        if name in seen:
            continue
        seen.add(name)
        path = staged.get(name)
        if path is None:
            if not is_omarchy_name(name):
                continue
            if name in upstream_helpers:
                # 업스트림에 실재하는데 우리가 안 깔았다 — 진짜 결함.
                unstaged.add(name)
            else:
                # 업스트림에 그런 헬퍼가 없다 = 헬퍼가 아니다. 그래프에서
                # 빼되 조용히 빼지 않는다 — --emit-table 이 개수와 이름을
                # 함께 찍어, 생성된 문서를 읽는 사람이 스캐너가 무엇을
                # 헬퍼로 인정하지 않았는지 보게 한다.
                not_upstream_helpers.add(name)
            continue
        # 두 층을 서로 다른 텍스트로 읽는다.
        #
        # 외부 명령 추출(scan_commands)은 preprocess_bash() 를 거친 텍스트를
        # 써야 한다 — 주석·heredoc·따옴표 안 산문이 전부 "명령" 으로 새기
        # 때문이다. 반면 omarchy-* 루트 수확은 **원문**을 써야 한다.
        # strip_quoted_noise() 가 큰따옴표 payload 를 지우므로, 큰따옴표
        # 안에서만 불리는 헬퍼는 그래프에서 통째로 사라진다 — 실측으로
        # 스테이징된 헬퍼 137개 중 53개에 걸쳐 81개 이름이 이 층에서
        # 사라졌고, 그중 30개는 다른 어떤 헬퍼 본문에서도 회수되지 않는
        # 진짜 명령이었다(`omarchy-menu`, `omarchy-clipboard-paste-file`,
        # `omarchy-theme-set-*` 계열 등).
        #
        # 원문 수확이 이제 와서 안전한 이유: 따옴표 블랭킹이 막으려던
        # 파일 이름 오탐(`20-omarchy-dns.conf`, `90-omarchy-speaker-tuning.conf`,
        # `99-omarchy-nopasswd-$USER`)은 OMARCHY_RE 의 두 lookbehind 가
        # 이미 거부한다. 동적 조립 이름(`"omarchy-hw-$KIND"`)이 잘린
        # 리터럴로 남는 문제는 omarchy_names() 의 DYNAMIC_TAIL_RE 가 막고,
        # 주석 산문은 omarchy_harvest_text() 가 걷어낸다.
        #
        # 정적 분석이 여기서 볼 수 없는 것 — 런타임에 조립되는 헬퍼 이름.
        # `omarchy-bar:165` 의 `if "omarchy-installed-service-$service"`,
        # `"omarchy-hw-$KIND"`, `"omarchy-theme-set-${name}"` 은 전부
        # 진짜 호출이지만 `$service`/`$KIND` 가 취할 수 있는 값 집합은
        # 소스만 읽어서는 알 수 없다. 잘린 접두사(`omarchy-installed-service`)
        # 를 넣는 쪽이 더 나쁘다 — 존재하지 않는 명령에 대한 예외 행이
        # 생긴다. 그래서 버린다.
        #
        # QML/JS 쪽도 같은 한계를 공유한다. qml_omarchy_names() 는 문자열
        # **리터럴**만 읽으므로 `"omarchy-" + kind` 같은 연결이나 템플릿
        # 리터럴로 조립되는 이름은 보이지 않는다. 핀된 트리에는 그런 용례가
        # 지금 없지만(실측), 업스트림이 도입하면 조용히 빠진다.
        #
        # 결과적으로 **이 그래프는 완전하지 않으며, 이 도구를 근거로
        # 완전성을 주장하는 문서를 써서는 안 된다.**
        raw = path.read_text(errors="replace")
        text = preprocess_bash(raw)
        extra_defined = set()
        for src_name in SOURCE_RE.findall(text):
            src_path = staged.get(src_name)
            if src_path is None or src_path == path:
                continue
            src_text = sourced_funcs_cache.get(src_name)
            if src_text is None:
                src_text = FUNC_RE.findall(preprocess_bash(src_path.read_text(errors="replace")))
                sourced_funcs_cache[src_name] = src_text
            extra_defined.update(src_text)
        cmds = scan_commands(text, extra_defined)
        for c in cmds:
            if is_omarchy_name(c):
                queue.append(c)
            else:
                external.add(c)
        for c in omarchy_names(raw):
            queue.append(c)

    reachable_pkgs, violations, table = {}, [], []
    for cmd in sorted(external):
        entry = cmdmap.get(cmd)
        if entry is None:
            violations.append(f"UNMAPPED_COMMAND {cmd}")
            continue
        package, klass, rationale = entry
        table.append((cmd, package, klass, rationale))
        # AUR: real package, but repo-less — pacman -U (bin/install-packages:55)
        # resolves depends against repos and already-installed packages only,
        # never AUR, so declaring it in `depends` would make our own package
        # uninstallable via its own install path. It still has to show up
        # *somewhere* or the closure is silently unaudited, so it is held to
        # the same "declared in optdepends" bar as OPT below.
        # UNPACKAGED: no provider anywhere (repo or AUR) — nothing to declare,
        # so it is deliberately excluded from this reachable_pkgs tracking;
        # it only ever surfaces via --emit-table.
        if klass in ("HARD", "OPT", "AUR"):
            reachable_pkgs.setdefault(package, klass)
            if klass == "HARD":
                reachable_pkgs[package] = "HARD"

    pkgbuild = (repo / "packages/cachy-omarchy-shell/PKGBUILD").read_text()
    depends = set(re.findall(r"'([^']+)'", extract_bash_array_body(pkgbuild, "depends")))
    optdeps = {
        s.split(":")[0].strip()
        for s in re.findall(r"'([^']+)'", extract_bash_array_body(pkgbuild, "optdepends"))
    }
    for package, klass in sorted(reachable_pkgs.items()):
        if klass == "HARD" and package not in depends:
            violations.append(f"MISSING_HARD_DEP {package}")
        if klass == "OPT" and package not in depends and package not in optdeps:
            violations.append(f"MISSING_OPT_DEP {package}")
        if klass == "AUR":
            # AUR packages must be declared (in optdepends — never depends,
            # see the reachable_pkgs comment above) or the closure gap is
            # invisible again; and if one lands in depends anyway, pacman -U
            # would refuse to resolve it, so that is its own violation.
            if package not in optdeps:
                violations.append(f"MISSING_OPT_DEP {package}")
            if package in depends:
                violations.append(f"AUR_IN_DEPENDS {package}")

    for name in sorted(unstaged):
        if name not in exceptions:
            violations.append(f"UNSTAGED_REACHABLE {name}")

    # STALE_EXCEPTION: an exception row nobody needs any more is not
    # harmless bookkeeping -- it is a claim about the tree that this
    # scanner never re-checks on its own (the milestone column is opaque
    # to it), and at 31 rows that stopped being trustworthy by inspection.
    # A row is stale when its helper either (a) got staged since -- the
    # exception now exempts nothing -- or (b) the BFS never visits it at
    # all any more -- the closure that justified it is gone.
    #
    # (b) checks membership in `seen`, not `unstaged`. `unstaged` also
    # requires upstream_helpers membership, which is ground truth for the
    # *pinned commit currently being scanned* -- inside the update-pipeline
    # fixture's nested candidate, that pin is a synthetic test commit whose
    # regenerated tests/data/upstream-helpers.txt legitimately lists only a
    # handful of fixture names (fix round 2/3), which would make every real
    # exception row look unreachable there even though nothing changed
    # about the real tree. `seen` is populated by the BFS traversal itself,
    # before any upstream_helpers/staged classification, so it answers
    # "did the graph still lead here" without depending on which pin's
    # inventory happens to be loaded in this particular run.
    for name in sorted(exceptions):
        if name in staged:
            violations.append(f"STALE_EXCEPTION {name} (이미 스테이징됨 — 예외 불필요)")
        elif name not in seen:
            violations.append(f"STALE_EXCEPTION {name} (더는 도달 불가 — 예외 불필요)")

    # Cross-check the map against the live system where possible. This
    # audits *declarations* (the map + PKGBUILD depends/optdepends), not
    # this development machine's installed set: demanding that an
    # optdepends candidate already be installed here, just to prove the
    # optdepends declaration itself is correct, is self-contradictory and
    # makes a green run impossible on any machine that lacks every
    # optional tool. So a missing binary is not a violation, and — since
    # v0.9 rebaseline fix round 1 (C-2) — it is not noted anywhere in
    # --emit-table's output either: which commands happen to be installed
    # on the machine running this scan is a fact about that machine, not
    # about this project, and the emitted table is committed and asserted
    # against verbatim (test_dependency_closure.sh). A missing binary
    # simply narrows what this pass can check; it says nothing else. When
    # the binary *is* present, pacman still has to agree with the mapped
    # package, and a mismatch stays a real violation.
    # BASE 도 건너뛰지 않는다. 예전에는 건너뛰었고, 그 결과 BASE 는
    # 이 스캐너의 어떤 검사도 받지 않는 클래스가 됐다 — 하드 의존을
    # BASE 로 바꾸고 depends 에서 지워도 게이트가 통과했다(리뷰어 재현).
    # 호스트에 바이너리가 없으면 지금처럼 조용히 넘어간다.
    for cmd, package, klass, _ in table:
        which = shutil.which(cmd)
        if which is None:
            continue
        owner = subprocess.run(
            ["pacman", "-Qqo", which], capture_output=True, text=True
        )
        if owner.returncode == 0:
            actual = owner.stdout.strip().split()[-1]
            if actual != package:
                violations.append(
                    f"UNMAPPED_COMMAND {cmd} (map says {package}, pacman says {actual})"
                )

    # BASE 는 "부재할 수 없으므로 선언 대상이 아니다" 라는 주장이다. 그
    # 주장은 검사 가능하다: 선언된 depends 의 전이 폐포, 또는 Arch 의
    # base/base-devel 폐포, 또는 우리가 직접 빌드하는 패키지 안에 있어야
    # 한다. 그 셋 중 어디에도 없으면 그것은 기반 패키지가 아니라 그냥
    # 선언되지 않은 의존이고, BASE 라고 적어 침묵시킨 것이다.
    #
    # 이 검사가 없으면 클래스 칼럼 한 글자를 고치는 것만으로 게이트를
    # 만족시킬 수 있다 — 이 브랜치에서 가장 값싼 부정직 경로였다.
    #
    # pactree 가 없는 호스트에서는 검사를 건너뛴다(pacman 교차검증과 같은
    # 규칙: 호스트가 답을 모르면 판정하지 않는다). 건너뛴 사실은
    # --emit-table 이 적는다 — 조용히 넘어가지 않는다.
    base_unverifiable = shutil.which("pactree") is None
    if not base_unverifiable:
        guaranteed = set()
        for seed in sorted(depends) + ["base", "base-devel"]:
            r = subprocess.run(
                ["pactree", "-l", "-s", seed], capture_output=True, text=True
            )
            if r.returncode != 0:
                continue
            for tok in r.stdout.split():
                guaranteed.add(re.split(r"[<>=]", tok.strip())[0])
        # 우리 자신이 빌드하는 패키지는 우리가 그 파일을 배포하므로
        # 정의상 부재할 수 없다(`list.sh` → cachy-omarchy-shell).
        for pkgdir in sorted((repo / "packages").iterdir()):
            pkgb = pkgdir / "PKGBUILD"
            if pkgb.is_file():
                mm = re.search(r"^pkgname=([A-Za-z0-9_.+-]+)", pkgb.read_text(), re.M)
                if mm:
                    guaranteed.add(mm.group(1))
        for cmd, package, klass, _ in table:
            if klass == "BASE" and package not in guaranteed:
                violations.append(
                    f"UNJUSTIFIED_BASE {package} ({cmd} — 선언된 depends 의 전이 "
                    f"폐포에도 base/base-devel 에도 없다; BASE 가 아니라 선언되지 "
                    f"않은 의존이다)"
                )

    for pid in sorted(unmatched_disabled_plugins):
        violations.append(f"UNMATCHED_DISABLED_PLUGIN {pid}")

    if args.emit_table:
        # 이 표는 문서에 커밋되고 --emit-table 재생성 결과와 문자 그대로
        # 비교된다(test_dependency_closure.sh). 이 스캔을 실행하는 머신에
        # 무엇이 설치돼 있는지는 그 머신에 대한 사실이지 이 프로젝트에 대한
        # 사실이 아니다 — 커밋되는 표 안에 넣으면 다른 머신/CI/사용자가
        # optdepends 하나만 깔아도 손대지 않은 문서가 거짓 RED 를 낸다
        # (v0.9 rebaseline fix round 1, C-2). 그래서 여기서는 `not_installed`
        # 를 표에 전혀 찍지 않는다 — 그 정보는 위쪽 실제 위반 판정(있으면
        # UNMAPPED_COMMAND)에서만 쓰이고, 표 셀에는 클래스와 근거만 남는다.
        print("| command | package | class | 근거 |")
        print("| --- | --- | --- | --- |")
        for cmd, package, klass, rationale in table:
            print(f"| `{cmd}` | `{package}` | {klass} | {rationale} |")
        # 개수는 여기서 함께 내보내 표와 같은 단언 대상이 되게 한다 — 산문에
        # 손으로 옮겨 적은 숫자는 맵이 바뀌어도 스위트가 green 인 채로 거짓이
        # 될 수 있다(v0.9 rebaseline fix round 1, I-2).
        base_count = sum(1 for r in table if r[2] == "BASE")
        print()
        print(
            "tests/data/command-packages.tsv: 전체 %d행, 위 표에는 도달한 %d행이 "
            "모두 실린다(BASE %d행 포함 — BASE 는 declare 대상이 아닐 뿐 "
            "검사 대상에서 빠지지 않는다)"
            % (len(map_rows), len(table), base_count)
        )
        if base_unverifiable:
            print(
                "주의: 이 호스트에 pactree 가 없어 BASE 정당성 검사를 "
                "건너뛰었다 — 위 BASE 행들은 이번 실행에서 검증되지 않았다"
            )
        print()
        print(
            "docs/COMMAND_AUDIT.md 의 DISABLED 행으로 메뉴 루트에서 억제된 "
            "이름: %d개 (의도적으로 미지원인 Omarchy OS 스택 — 예외 파일과 "
            "달리 사유·신선도 검사가 없는 통로다)" % len(menu_suppressed)
        )
        for name in sorted(menu_suppressed):
            print(f"- `{name}`")
        # 스캐너가 헬퍼로 인정하지 않은 이름을 여기서 드러낸다. 이 목록이
        # 조용하면, 생성된 문서는 도구가 갖지 않은 완전성을 주장하게 된다.
        print()
        print(
            "스캐너가 헬퍼로 인정하지 않은 이름: %d개 "
            "(핀된 업스트림 bin/ 에 없음 — 파일 이름, 알림 hint 키, "
            "grep 패턴, 안내 문구 등 명령이 아닌 문자열)"
            % len(not_upstream_helpers)
        )
        for name in sorted(not_upstream_helpers):
            print(f"- `{name}`")
        return 0

    for v in violations:
        print(v)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
