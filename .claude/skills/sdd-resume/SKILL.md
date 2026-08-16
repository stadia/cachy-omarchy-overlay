---
name: sdd-resume
description: 끊긴 컨트롤러 세션을 이어받을 때 SDD 워크스페이스의 현재 상태와 남은 태스크를 요약. 인자로 워크스페이스 경로(생략 시 가장 최근 .superpowers/sdd/ 항목).
---

이 프로젝트는 다중 세션 Subagent-Driven Development 워크플로로, 각 마일스톤마다 `.superpowers/sdd/<date>-<scope>/` 아래에 `HANDOFF.md`, `progress.md`, task brief/report, review 파일을 남긴다. 컨트롤러 세션이 끊겨 이어받을 때 이 스킬로 현재 상태를 한 번에 파악한다.

## 절차

1. **대상 워크스페이스 선택.** 인자가 주어지면 그 경로; 아니면 가장 최근 수정된 `.superpowers/sdd/*/` 항목:
   ```bash
   ls -dt .superpowers/sdd/*/ | head -1
   ```

2. **정해진 읽기 순서** (HANDOFF가 명시한 순서):
   - `HANDOFF.md` — 재개 절차, 환경 사실, 안전 규칙, 남은 태스크 주의사항.
   - `progress.md` — 원장. 각 태스크의 상태·커밋 범위·루링.
   - 플랜: `docs/superpowers/plans/<해당>.md`.
   - `SPEC.md` — 최종 권위.

3. **실측 상태**:
   ```bash
   git branch --show-current
   git log --oneline | head -15
   ./tests/test.sh          # 기대: 전부 PASS
   systemctl --user status coo-shell.service --no-pager
   ```

4. **재디스패치 금지 규칙:** 원장에서 `Task <N>: complete`인 태스크는 다시 실행하지 않는다.

5. **보고 형식** (사용자에게):
   - 현재 브랜치·HEAD·테스트 결과(N/N).
   - 완료된 태스크 요약(커밋 범위).
   - 남은 태스크 + 다음 결정 사항(예: 브랜치 마무리, 다음 마일스톤 플랜, 사용자 게이트 항목).
   - 원장의 `Ruling:` 목록 중 사용자에게 보고해야 할 것들.

## 안전
- 이 스킬은 읽기 + `./tests/test.sh` 실행만 한다. 코드 수정·커밋·라이브 세션 변경은 하지 않는다.
- 라이브 테스트는 `COO_SHELL_PATH=$PWD/shell` 환경에서만; 사용자 세션 Hyprland에 무격리 `hyprctl`/`pkill` 금지.
- 산출물 보고는 한국어.