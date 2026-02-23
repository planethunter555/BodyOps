#!/bin/bash
# ralph.sh - Body Ops AFK自動実行スクリプト
# 使い方: ./ralph.sh <イテレーション数>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCPRETTY="$HOME/.gem/ruby/2.6.0/bin/xcpretty"
SIMULATOR_ID="905FDBCF-7BDF-41CC-B5C0-AB889F4783EA"

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

ITERATIONS=$1
echo "Starting Body Ops Ralph — $ITERATIONS iterations"
echo "========================================"

cd "$SCRIPT_DIR"

for ((i=1; i<=ITERATIONS; i++)); do
  echo ""
  echo "--- Iteration $i / $ITERATIONS ---"

  cat > /tmp/ralph_prompt.txt << PROMPT
Read PRD.json and progress.txt in the current directory.

You are implementing the Body Ops iOS app (SwiftUI + SwiftData + multi-LLM).
Working directory: $SCRIPT_DIR
Xcode project: $SCRIPT_DIR/BodyOps.xcodeproj

## Your task each iteration:
1. Read PRD.json and find the first task where passes == false.
2. If no task remains, output <promise>COMPLETE</promise> and stop.
3. Implement the task fully in the Xcode project.
   - If the task has a "test_file" field, copy test code from tests/ into the path in "test_file". Then run "xcodegen generate".
4. Run ALL feedback loops before marking passes: true:
   - BUILD: xcodebuild build -scheme BodyOps -project '$SCRIPT_DIR/BodyOps.xcodeproj' -destination 'id=$SIMULATOR_ID' 2>&1 | $XCPRETTY
   - LINT:  swiftlint lint --quiet --config '$SCRIPT_DIR/.swiftlint.yml' '$SCRIPT_DIR/BodyOps'
   - TEST (only if task has "test_file"): xcodebuild test -scheme BodyOps -project '$SCRIPT_DIR/BodyOps.xcodeproj' -destination 'id=$SIMULATOR_ID' 2>&1 | $XCPRETTY
   Do NOT mark passes: true if any loop fails. Fix first.
5. When all loops pass:
   - Update PRD.json: set passes to true.
   - git -C '$SCRIPT_DIR' add -A && git -C '$SCRIPT_DIR' commit -m "feat: [task-id] description"
   - Append to progress.txt: "DONE [task-id]: description"
6. If all tasks have passes: true, output <promise>COMPLETE</promise>.
PROMPT

  result=$(claude --print \
    --allowedTools "Bash,Edit,Write,Read,Glob,Grep" \
    --add-dir "$SCRIPT_DIR" \
    < /tmp/ralph_prompt.txt)

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "========================================"
    echo "All tasks complete!"
    exit 0
  fi
done

echo "========================================"
echo "Reached max iterations ($ITERATIONS). Check progress.txt for status."
