# Upstream Pin

Repository: basecamp/omarchy
URL: https://github.com/basecamp/omarchy
Branch: quattro
Commit: b724f7615630d7a7aca76dce070d469f43a3bfec
Date: 2026-08-15
License: MIT — Copyright (c) David Heinemeier Hansson

## How to refresh the vendored tree

    rm -rf vendor/omarchy
    git clone --depth 1 --branch quattro --filter=blob:none --sparse \
      https://github.com/basecamp/omarchy.git vendor/omarchy
    git -C vendor/omarchy sparse-checkout set --skip-checks shell bin LICENSE
    git -C vendor/omarchy checkout <Commit above>

`vendor/omarchy/` is git-ignored and read-only. Never edit it. Bumping the pin
means editing the `Commit:` and `Date:` lines above and re-running
`./tests/test.sh`, which will fail until `docs/QUATTRO_PORT_MAP.md` is
re-verified against the new tree.

## Components reviewed

- shell/shell.qml
- shell/plugins/menu/{Menu.qml,MenuModel.js,BarWidget.qml,manifest.json}
- shell/Commons/{Style.qml,Color.qml,Util.qml,Border.qml,qmldir}
- shell/Ui/ (component inventory)
- bin/omarchy-shell (IPC transport reference)
