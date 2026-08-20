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
OMARCHY_RE = re.compile(r"\b(omarchy-[a-z0-9]+(?:-[a-z0-9]+)*)")
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
    """Drop heredoc bodies before scanning.

    A heredoc body is data (jq/awk/sql/JSON payloads embedded in these
    helpers), not shell command text. Left in, it floods the scan with
    every bare word in the payload as a fake command.
    """
    lines = text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        out.append(lines[i])
        m = HEREDOC_RE.search(lines[i])
        if m:
            delim = m.group(2)
            i += 1
            while i < len(lines) and lines[i].strip() != delim:
                i += 1
            i += 1  # skip the delimiter line itself
            continue
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
# from `=~` to the closing `]]` of the enclosing `[[ ... ]]` test — not
# to the first single `]`, since these patterns routinely contain their
# own POSIX bracket expressions (`([0-9]+)x([0-9]+)`) whose closing `]`
# would otherwise end the blanked span far too early.
REGEX_MATCH_RE = re.compile(r"=~.*?\]\]")


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
    text = REGEX_MATCH_RE.sub(lambda m: "=~" + " " * (len(m.group(0)) - 2), text)
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


def bash_commands(text):
    """Commands appearing in command position, minus builtins and local funcs."""
    text = preprocess_bash(text)
    defined = set(FUNC_RE.findall(text))
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


QML_ARRAY_RE = re.compile(r"command:\s*\[(.*?)\]", re.S)
QML_STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def qml_commands(text):
    """argv[0] of each `command:` array; shell payloads are re-parsed as bash.

    The nightlight service is the case that forces this: it does not call
    hyprsunset as argv[0], it calls it inside a `bash -c` string.
    """
    found = set()
    for body in QML_ARRAY_RE.findall(text):
        parts = QML_STR_RE.findall(body)
        if not parts:
            continue
        head = parts[0].split("/")[-1]
        if head in ("bash", "sh"):
            for payload in parts[1:]:
                found |= bash_commands(payload)
        else:
            found.add(head)
    return {c for c in found if c not in BUILTINS}


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--map", required=True)
    ap.add_argument("--exceptions", required=True)
    ap.add_argument("--emit-table", action="store_true")
    args = ap.parse_args()

    tree, repo = Path(args.tree), Path(args.repo)
    upstream = tree / "usr/share/cachy-omarchy/upstream"
    binroot = upstream / "bin"

    cmdmap = {r[0]: (r[1], r[2], r[3]) for r in read_tsv(args.map, 4)}
    exceptions = {r[0]: (r[1], r[2]) for r in read_tsv(args.exceptions, 3)}

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

    # --- roots -----------------------------------------------------------
    roots = set()
    for name in ("bindings.conf", "bindings.lua"):
        text = (repo / "overlay/hypr" / name).read_text()
        roots |= set(OMARCHY_RE.findall(text))
    qml_seed = set()
    plugroot = upstream / "shell/plugins"
    if plugroot.is_dir():
        for qml in plugroot.rglob("*.qml"):
            plugin = qml.relative_to(plugroot).parts[0]
            if plugin in disabled:
                continue
            text = qml.read_text(errors="replace")
            qml_seed |= qml_commands(text)
            roots |= set(OMARCHY_RE.findall(text))
    menu = upstream / "default/omarchy/omarchy-menu.jsonc"
    if menu.is_file():
        audit = (repo / "docs/COMMAND_AUDIT.md").read_text()
        known_bad = {
            m.group(1)
            for m in re.finditer(
                r"\|\s*`(omarchy-[a-z0-9-]+)`\s*\|\s*DISABLED\s*\|", audit
            )
        }
        roots |= set(OMARCHY_RE.findall(menu.read_text())) - known_bad

    # --- BFS over staged helpers ----------------------------------------
    seen, queue, unstaged = set(), sorted(roots), set()
    # omarchy-* names from qml_commands() are already covered by the
    # OMARCHY_RE root scan above (line 337) and belong in the BFS so their
    # staged/unstaged status is checked, not dumped straight into
    # `external` where they'd need a nonexistent Arch package mapping.
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
            if is_omarchy_name(name):
                unstaged.add(name)
            continue
        text = preprocess_bash(path.read_text(errors="replace"))
        cmds = bash_commands(text)
        for c in cmds:
            if is_omarchy_name(c):
                queue.append(c)
            else:
                external.add(c)
        for c in OMARCHY_RE.findall(text):
            queue.append(c)

    reachable_pkgs, violations, table = {}, [], []
    for cmd in sorted(external):
        entry = cmdmap.get(cmd)
        if entry is None:
            violations.append(f"UNMAPPED_COMMAND {cmd}")
            continue
        package, klass, rationale = entry
        table.append((cmd, package, klass, rationale))
        if klass in ("HARD", "OPT"):
            reachable_pkgs.setdefault(package, klass)
            if klass == "HARD":
                reachable_pkgs[package] = "HARD"

    pkgbuild = (repo / "packages/cachy-omarchy-shell/PKGBUILD").read_text()
    dep_block = re.search(r"^depends=\((.*?)\)", pkgbuild, re.S | re.M)
    opt_block = re.search(r"^optdepends=\((.*?)\)", pkgbuild, re.S | re.M)
    depends = set(re.findall(r"'([^']+)'", dep_block.group(1) if dep_block else ""))
    optdeps = {
        s.split(":")[0].strip()
        for s in re.findall(r"'([^']+)'", opt_block.group(1) if opt_block else "")
    }
    for package, klass in sorted(reachable_pkgs.items()):
        if klass == "HARD" and package not in depends:
            violations.append(f"MISSING_HARD_DEP {package}")
        if klass == "OPT" and package not in depends and package not in optdeps:
            violations.append(f"MISSING_OPT_DEP {package}")

    for name in sorted(unstaged):
        if name not in exceptions:
            violations.append(f"UNSTAGED_REACHABLE {name}")

    # Verify the map against the live system where possible.  A lookup that
    # cannot run is not silently accepted; it is reported.
    for cmd, package, klass, _ in table:
        if klass == "BASE":
            continue
        which = shutil.which(cmd)
        if which is None:
            violations.append(f"UNMAPPED_COMMAND {cmd} (not installed; cannot verify)")
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

    if args.emit_table:
        print("| command | package | class | 근거 |")
        print("| --- | --- | --- | --- |")
        for cmd, package, klass, rationale in table:
            if klass == "BASE":
                continue
            print(f"| `{cmd}` | `{package}` | {klass} | {rationale} |")
        return 0

    for v in violations:
        print(v)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
