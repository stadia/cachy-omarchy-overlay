#!/usr/bin/env python3
"""Compare packaged menu omarchy-* names to COMMAND_AUDIT.md census."""
import re
import sys
from pathlib import Path


def main() -> int:
    audit = Path(sys.argv[1]).read_text()
    menu = Path(sys.argv[2]).read_text()
    qml = Path(sys.argv[3]).read_text() if Path(sys.argv[3]).exists() else ""

    begin = audit.find("MENU_AUDIT_BEGIN")
    end = audit.find("MENU_AUDIT_END")
    if begin < 0 or end < 0 or end <= begin:
        print("missing MENU_AUDIT markers")
        return 1
    classified = {}
    for line in audit[begin:end].splitlines():
        m = re.match(
            r"\|\s*`([^`]+)`\s*\|\s*(SAFE|ADAPTED|DISABLED)\s*\|\s*(\S+)\s*\|",
            line,
        )
        if m:
            classified[m.group(1)] = (m.group(2), m.group(3))

    seen = set(re.findall(r"\b(omarchy-[a-z0-9-]+)", menu))
    seen.update(re.findall(r"\b(omarchy-[a-z0-9-]+)", qml))
    missing = sorted(seen - set(classified))
    bad_action = sorted(
        name
        for name, (_cls, act) in classified.items()
        if act not in ("package", "copy", "wrapper", "disable")
    )
    if missing:
        print("unclassified:", ", ".join(missing[:30]), f"({len(missing)} total)")
    if bad_action:
        print("bad action:", ", ".join(bad_action[:20]))
    if missing or bad_action:
        return 1
    print(f"ok:   메뉴 omarchy-* {len(seen)}개 전부 분류됨")
    print(f"ok:   분류표 {len(classified)}행")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
