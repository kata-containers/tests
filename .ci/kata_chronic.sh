#!/usr/bin/env bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Use chronic to mute the output of a command, unless it errors.
# But, to prevent system timeouts from complete inactivity, periodically
# output '.'s to keep the system looking alive...

cmdLine=$@

eval chronic "${cmdLine[@]}" &
cmdPid="$!"

(
	sleepval=10
	echoval=60
	count=0
	while true; do
		printf ".";sleep ${sleepval};
		((count+=${sleepval}))
		printf $count
		((count%${echoval} == 0)) && printf ":\n" && count=0
	done
)&

printerPid="$!"

wait "$cmdPid"
ret=$?
printf "\n"
kill "$printerPid"

# And return the exit code from the sub-command
exit "$ret"
