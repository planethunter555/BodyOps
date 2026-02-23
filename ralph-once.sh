#!/bin/bash
# ralph-once.sh - Body Ops HITL（人間監視）単発実行スクリプト
# 使い方: ./ralph-once.sh
# 1タスクだけ実行して止まる。内容を確認してからまた実行する。

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Body Ops Ralph — single iteration (HITL mode)"
echo "========================================"

claude -p \
"@PRD.json @progress.txt

You are implementing the Body Ops iOS app (SwiftUI + SwiftData + multi-LLM).

## Your task this iteration:
1. Read PRD.json and find the first task where passes == false.
2. If no task remains, output <promise>COMPLETE</promise> and stop.
3. Implement the task fully. If the task has a 'test_file' field:
   - Copy the corresponding test code from tests/*.swift into the Xcode test target at the path specified in 'test_file'.
4. Run ALL feedback loops before marking passes: true:
   - BUILD: xcodebuild build -scheme BodyOps -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty
   - LINT:  swiftlint lint --quiet
   - TEST (only if the task has a 'test_file'): xcodebuild test -scheme BodyOps -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty
   Do NOT mark passes: true if any feedback loop fails. Fix the issue and re-run.
5. When all feedback loops pass, update PRD.json: set passes to true for this task.
6. Make a git commit: git add -A && git commit -m 'feat: [task-id] description'
7. Append a one-line summary to progress.txt: 'DONE [task-id]: description'
" \
  --cwd "$SCRIPT_DIR"
