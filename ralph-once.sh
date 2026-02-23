#!/bin/bash
# ralph-once.sh - Body Ops HITL（人間監視）単発実行スクリプト
# 使い方: ./ralph-once.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCPRETTY="$HOME/.gem/ruby/2.6.0/bin/xcpretty"
SIMULATOR_ID="905FDBCF-7BDF-41CC-B5C0-AB889F4783EA"

echo "Body Ops Ralph — single iteration (HITL mode)"
echo "========================================"

cd "$SCRIPT_DIR"

# プロンプトをファイルに書き出す
cat > /tmp/ralph_prompt.txt << PROMPT
Read PRD.json and progress.txt in the current directory.

You are implementing the Body Ops iOS app (SwiftUI + SwiftData + multi-LLM).
Working directory: $SCRIPT_DIR
Xcode project: $SCRIPT_DIR/BodyOps.xcodeproj

## Your task this iteration:
1. Read PRD.json and find the first task where passes == false.
2. If no task remains, output <promise>COMPLETE</promise> and stop.
3. Implement the task fully in the Xcode project.
   - If the task has a "test_file" field, copy the test code from tests/ into the path specified by "test_file". Then run "xcodegen generate" to include it.
4. Run ALL feedback loops before marking passes: true:
   - BUILD: xcodebuild build -scheme BodyOps -project '$SCRIPT_DIR/BodyOps.xcodeproj' -destination 'id=$SIMULATOR_ID' 2>&1 | $XCPRETTY
   - LINT:  swiftlint lint --quiet --config '$SCRIPT_DIR/.swiftlint.yml' '$SCRIPT_DIR/BodyOps'
   - TEST (only if task has "test_file"): xcodebuild test -scheme BodyOps -project '$SCRIPT_DIR/BodyOps.xcodeproj' -destination 'id=$SIMULATOR_ID' 2>&1 | $XCPRETTY
   Do NOT mark passes: true if any loop fails. Fix the issue first.
5. When all loops pass:
   - Update PRD.json: set passes to true for this task.
   - git -C '$SCRIPT_DIR' add -A && git -C '$SCRIPT_DIR' commit -m "feat: [task-id] description"
   - Append one line to progress.txt: "DONE [task-id]: description"
PROMPT

claude --print \
  --allowedTools "Bash,Edit,Write,Read,Glob,Grep" \
  --add-dir "$SCRIPT_DIR" \
  < /tmp/ralph_prompt.txt
