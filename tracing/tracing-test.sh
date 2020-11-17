#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

script_name=${0##*/}

# Set to true if all tests pass
success="false"

DEBUG=${DEBUG:-}

# If set to any value, do not shut down the Jaeger service.
DEBUG_KEEP_JAEGER=${DEBUG_KEEP_JAEGER:-}

[ -n "$DEBUG" ] && set -o xtrace

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

RUNTIME="io.containerd.kata.v2"
CONTAINER_IMAGE="quay.io/prometheus/busybox:latest"

TRACE_LOG_DIR=${TRACE_LOG_DIR:-${KATA_TESTS_LOGDIR}/traces}

jaeger_server=${jaeger_server:-localhost}
jaeger_ui_port=${jaeger_ui_port:-16686}
jaeger_docker_container_name="jaeger"

logdir=""

# Cleanup will remove Jaeger container and
# disable tracing.
cleanup()
{
	local fp="die"
	local result="failed"
	local dest="$logdir"

	if [ "$success" = "true" ]; then
		local fp="info"
		result="passed"

		[ -z "$DEBUG_KEEP_JAEGER" ] && stop_jaeger 2>/dev/null || true

		# The tests worked so remove the logs
		if [ -n "$DEBUG" ]; then
			eval "$fp" "test $result - logs left in '$dest'"
		else
			"${SCRIPT_PATH}/../.ci/configure_tracing_for_kata.sh" disable

			[ -d "$logdir" ] && rm -rf "$logdir" || true
		fi

		return 0
	fi

	if [ -n "${CI:-}" ]; then
		# Running under the CI, so copy the logs to allow them
		# to be added as test artifacts.
		sudo mkdir -p "$TRACE_LOG_DIR"
		sudo cp -a "$logdir"/* "$TRACE_LOG_DIR"

		dest="$TRACE_LOG_DIR"
	fi

	eval "$fp" "test $result - logs left in '$dest'"
}

# Run an operation to generate Jaeger trace spans
create_traces()
{
	sudo ctr image pull "$CONTAINER_IMAGE"
	sudo ctr run --runtime "$RUNTIME" --rm "$CONTAINER_IMAGE" tracing-test true
}

start_jaeger()
{
	local jaeger_docker_image="jaegertracing/all-in-one:latest"

	# Defaults - see https://www.jaegertracing.io/docs/getting-started/
	docker run -d --runtime runc --name "${jaeger_docker_container_name}" \
		-e COLLECTOR_ZIPKIN_HTTP_PORT=9411 \
		-p 5775:5775/udp \
		-p 6831:6831/udp \
		-p 6832:6832/udp \
		-p 5778:5778 \
		-p "${jaeger_ui_port}:${jaeger_ui_port}" \
		-p 14268:14268 \
		-p 9411:9411 \
		"$jaeger_docker_image"

	sudo mkdir -m 0750 -p "$TRACE_LOG_DIR"
}

stop_jaeger()
{
	docker stop "${jaeger_docker_container_name}"
	docker rm -f "${jaeger_docker_container_name}"
}

get_jaeger_traces()
{
	local service="$1"
	[ -z "$service" ] && die "need jaeger service name"

	local traces_url="http://${jaeger_server}:${jaeger_ui_port}/api/traces?service=${service}"
	curl -s "${traces_url}" 2>/dev/null
}

get_trace_summary()
{
	local status="$1"
	[ -z "$status" ] && die "need jaeger status JSON"

	echo "${status}" | jq -S '.data[].spans[] | [.spanID, .operationName] | @sh'
}

get_span_count()
{
	local status="$1"
	[ -z "$status" ] && die "need jaeger status JSON"

	# This could be simplified but creating a variable holding the
	# summary is useful in debug mode as the summary is displayed.
	local trace_summary=$(get_trace_summary "$status" || true)

	local count=$(echo "${trace_summary}" | wc -l)

	[ -z "$count" ] && count=0

	echo "$count"
}

# Returns status from Jaeger web UI
get_jaeger_status()
{
	local service="$1"
	local logdir="$2"

	[ -z "$service" ] && die "need jaeger service name"
	[ -z "$logdir" ] && die "need logdir"

	local max_attempts=10

	local status=""
	local span_count=0

	# Loop until we find some spans
	for _ in $(seq $max_attempts)
	do
		status=$(get_jaeger_traces "$service" || true)
		if [ -n "$status" ]; then
			echo "$status" > "$logdir/${service}-status.json"
			span_count=$(get_span_count "$status")
			[ "$span_count" -gt 0 ] && break
		fi
		sleep 1
	done

	[ -z "$status" ] && die "failed to query Jaeger for status"
	[ "$span_count" -eq 0 ] && die "failed to find any trace spans"

	# Now that we have a valid status, poll until it settles.
	# Yes, it's horrid but we need to poll to give the Jaeger
	# web service time to think it seems ;)
	for _ in $(seq $max_attempts)
	do
		local new_status=$(get_jaeger_traces "$service" || true)

		# We have already queried the services status, so it should
		# still be there!
		[ -z "$new_status" ] && die "Jaeger trace status disappeared"

		local new_span_count=$(get_span_count "$new_status")
		[ -z "$new_span_count" ] && die "no span count"
		[ "$new_span_count" -le 0 ] && die "invalid span count"
		[ "$new_span_count" -lt "$span_count" ] && die "span count dropped ($span_count to $new_span_count)"

		# Span count didn't change, so the service
		# has "stabilised"
		if [ "$new_span_count" -eq "$span_count" ]; then
			get_trace_summary "$status" \
				> "$logdir/span-summary.txt"
			return
		fi

		# The span count increased, so reset
		status="$new_status"
		span_count="$new_span_count"

		sleep 1
	done

	die "span count failed to stabilize after $max_attempts seconds"

}

# Check Jaeger spans for the specified service.
check_jaeger_status()
{
	local service="$1"
	local min_spans="$2"
	local logdir="$3"

	[ -z "$service" ] && die "need jaeger service name"
	[ -z "$min_spans" ] && die "need minimum trace span count"
	[ -z "$logdir" ] && die "need logdir"

	local status
	local errors=0

	local attempt=0
	local attempts=3

	info "Checking Jaeger status"

	while [ "$attempt" -lt "$attempts" ]
	do
		status=$(get_jaeger_status "$service" "$logdir")

		#------------------------------
		# Basic sanity checks
		[ -z "$status" ] && die "failed to query status via HTTP"

		local span_lines=$(echo "$status"|jq -S '.data[].spans | length')
		[ -z "$span_lines" ] && die "no span status"

		# Log the spans to allow for analysis in case the test fails
		echo "$status"|jq -S . > "$logdir/${service}-traces-formatted.json"

		local span_lines_count=$(echo "$span_lines"|wc -l)

		# Total up all span counts
		local spans=$(echo "$span_lines"|paste -sd+ -|bc)
		[ -z "$spans" ] && die "no spans"

		# Ensure total span count is numeric
		echo "$spans"|grep -q "^[0-9][0-9]*$" || die "invalid span count: '$spans'"

		info "found $spans spans (across $span_lines_count traces)"

		# Validate
		[ "$spans" -lt "$min_spans" ] && die "expected >= $min_spans spans, got $spans"

		# Look for common errors in span data
		local error_msg=$(echo "$status"|jq -S . 2>/dev/null|grep "invalid parent span" || true)

		if [ -n "$error_msg" ]; then
			errors=$((errors+1))
			warn "Found invalid parent span errors (attempt $attempt): $error_msg"
			attempt=$((attempt+1))
			continue
		else
			errors=$((errors-1))
			[ "$errors" -lt 0 ] && errors=0
		fi

		# Crude but it works
		error_or_warning_msgs=$(echo "$status" |\
			jq -S . 2>/dev/null |\
			grep -E "\"(warnings|errors)\"" |\
			grep -E -v "\<null\>" || true)

		if [ -n "$error_or_warning_msgs" ]; then
			errors=$((errors+1))
			warn "Found errors/warnings (attempt $attempt): $error_or_warning_msgs"
			attempt=$((attempt+1))
			continue
		else
			errors=$((errors-1))
			[ "$errors" -lt 0 ] && errors=0
		fi

		attempt=$((attempt+1))

		[ "$errors" -eq 0 ] && break
	done

	[ "$errors" -eq 0 ] || die "errors still detected after $attempts attempts"
}

setup()
{
	# containerd must be running in order to use ctr to generate traces
	sudo systemctl restart containerd

	start_jaeger

	"${SCRIPT_PATH}/../.ci/configure_tracing_for_kata.sh" enable
}

run_test()
{
	local service="$1"
	local min_spans="$2"
	local logdir="$3"

	[ -z "$service" ] && die "need service name"
	[ -z "$min_spans" ] && die "need minimum span count"
	[ -z "$logdir" ] && die "need logdir"

	info "Running test for service '$service'"

	logdir="$logdir/$service"
	mkdir -p "$logdir"

	check_jaeger_status "$service" "$min_spans" "$logdir"

	info "test passed"
}

run_tests()
{
	# List of services to check
	#
	# Format: "name:min-spans"
	#
	# Where:
	#
	# - 'name' is the Jaeger service name.
	# - 'min-spans' is an integer representing the minimum number of
	#   trace spans this service should generate.
	#
	# Notes:
	#
	# - Uses an array to ensure predictable ordering.
	# - All services listed are expected to generate traces
	#   when create_traces() is called a single time.
	local -a services

	services+=("kata:4")

	create_traces

	logdir=$(mktemp -d)

	for service in "${services[@]}"
	do
		local name=$(echo "${service}"|cut -d: -f1)
		local min_spans=$(echo "${service}"|cut -d: -f2)

		run_test "${name}" "${min_spans}" "${logdir}"
	done

	info "all tests passed"
	success="true"
}

usage()
{
	cat <<EOT

Usage: $script_name [<command>]

Commands:

  clean  - Perform cleanup phase only.
  help   - Show usage.
  run    - Only run tests (no setup or cleanup).
  setup  - Perform setup phase only.

Environment variables:

  CI    - if set, save logs of all tests to ${TRACE_LOG_DIR}.
  DEBUG - if set, enable tracing and do not cleanup after tests.
  DEBUG_KEEP_JAEGER - if set, do not shut down the Jaeger service.

Notes:
  - Runs all test phases if no arguments are specified.

EOT
}

main()
{
	local cmd="${1:-}"

	case "$cmd" in
		clean) success="true"; cleanup; exit 0;;
		help|-h|-help|--help) usage; exit 0;;
		run) run_tests; exit 0;;
		setup) setup; exit 0;;
	esac

	trap cleanup EXIT

	setup

	run_tests
}

main "$@"
