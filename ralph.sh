#!/bin/bash
# ralph.sh - Body Ops AFK自動実行スクリプト（複数イテレーション）
# 使い方: ./ralph.sh <イテレーション数>
# 例: ./ralph.sh 10

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  echo "Example: $0 10"
  exit 1
fi

ITERATIONS=$1
echo "Starting Body Ops Ralph — $ITERATIONS iterations"
echo "========================================"

for ((i=1; i<=ITERATIONS; i++)); do
  echo ""
  echo "--- Iteration $i / $ITERATIONS ---"

  result=$(claude -p \
"@PRD.json @progress.txt

You are implementing the Body Ops iOS app (SwiftUI + SwiftData + multi-LLM).

## Your task each iteration:
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
8. If all tasks in PRD.json have passes: true, output <promise>COMPLETE</promise>.
" \
  --cwd "$SCRIPT_DIR")

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo ""
    echo "========================================"
    echo "All tasks complete!"
    exit 0
  fi
done

echo ""
echo "========================================"
echo "Reached max iterations ($ITERATIONS). Check progress.txt for status."
