#!/bin/bash
cd ~/Developer/DeskRun
# Attempt to set xcode-select (may fail without sudo, that's ok)
xcode-select -s /Applications/Xcode.app/Contents/Developer 2>/dev/null
# Build the project
xcodebuild -project DeskRun.xcodeproj -scheme DeskRun -configuration Debug build CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" 2>&1 | tee ~/Developer/DeskRun/build-output.txt
echo ""
echo "===== BUILD COMPLETE - output saved to build-output.txt ====="
echo "Press any key to close..."
read -n 1
