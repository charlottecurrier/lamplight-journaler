#!/bin/bash
# Starts a simulator and waits until it has finished starting.
#
#     tools/boot_simulator.sh <udid>
#
# A simulator's first start on a new machine moves its data over ("Data Migration"). Once that ended with "Data
# Migration Failed", `simctl bootstatus` still returned success, and the test runner then crashed before any test
# ran. So read what it says: if the start failed, wipe the simulator and start it once more.
set -u
udid="$1"

start() {
  xcrun simctl bootstatus "$udid" -b 2>&1 | tee "${TMPDIR:-/tmp}/boot-$udid.log"
  status=${PIPESTATUS[0]}
  if [ "$status" -ne 0 ] || grep -q "Data Migration Failed" "${TMPDIR:-/tmp}/boot-$udid.log"; then
    return 1
  fi
  return 0
}

if ! start; then
  echo "The simulator didn't start cleanly. Wiping it and starting it again."
  xcrun simctl shutdown "$udid" || true
  xcrun simctl erase "$udid"
  if ! start; then
    echo "The simulator didn't start cleanly the second time either."
    exit 1
  fi
fi
# Tests on a simulator that has only just started stall. Give it a moment.
sleep 20
