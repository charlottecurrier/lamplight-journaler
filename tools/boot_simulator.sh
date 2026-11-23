#!/bin/bash
# Starts a simulator and waits until it has finished starting.
#
#     tools/boot_simulator.sh <udid>
#
# On the xcode-27 runner the iPhone Air's first start ends with "Data Migration Failed" (Status=3) every time, and the
# simulator works all the same: the runs that passed had that line too. So it is not treated as a failure. Treating it
# as one, and wiping the simulator to try again, failed every phone job (the wiped simulator said the same). Only
# `simctl bootstatus` itself failing stops the step.
set -u
udid="$1"
xcrun simctl bootstatus "$udid" -b || { echo "The simulator didn't start."; exit 1; }
# The first time a keyboard comes up on a new simulator, it shows a lesson over itself ("Speed up your typing by
# sliding your finger across the letters", with a Continue button). The first UI test that typed sat behind it until
# its lookups timed out: a run's screen recording shows it. Say the lesson has been seen.
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true \
  || echo "Couldn't turn off the keyboard's first-use lesson."
# Tests on a simulator that has only just started stall. Give it a moment.
sleep 20
