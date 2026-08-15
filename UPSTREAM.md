# Upstream Pin

Repository: basecamp/omarchy  
URL: https://github.com/basecamp/omarchy  
Branch: quattro  
Commit: b724f7615630d7a7aca76dce070d469f43a3bfec  
Date: 2026-08-15  
License: MIT — Copyright (c) David Heinemeier Hansson

## vendored 트리 갱신 방법

```bash
rm -rf vendor/omarchy
git clone --depth 1 --branch quattro --filter=blob:none --sparse \
  https://github.com/basecamp/omarchy.git vendor/omarchy
git -C vendor/omarchy sparse-checkout set --skip-checks shell bin LICENSE
git -C vendor/omarchy checkout <위 Commit>
```

`vendor/omarchy/`는 gitignore 대상이며 읽기 전용입니다. 직접 수정하지 마세요.

핀을 올리려면 위의 `Commit:` / `Date:`를 고친 뒤 `./tests/test.sh`를 다시 실행하세요. 새 트리에 맞춰 `docs/QUATTRO_PORT_MAP.md`를 재검증하기 전까지 테스트는 실패합니다.

## 검토한 구성 요소

- `shell/shell.qml`
- `shell/plugins/menu/{Menu.qml,MenuModel.js,BarWidget.qml,manifest.json}`
- `shell/Commons/{Style.qml,Color.qml,Util.qml,Border.qml,qmldir}`
- `shell/Ui/` (컴포넌트 목록)
- `bin/omarchy-shell` (IPC 전송 참고)
