#!/bin/bash
# Copyright (c) 2024 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
set -euo pipefail

usage() { echo "Usage: $0 <query> <path to yaml> <action> [value]"; }

QUERY="${1-}"
YAML_PATH="${2-}"
ACTION="${3-}"
VALUE="${4-}"
VERSION=""

handle_v3() {
	query="${QUERY#.}"

	case ${ACTION} in
		r)
			yq r "${YAML_PATH}" "${query}"
			;;
		w)
			yq w -i "${YAML_PATH}" "${query}" "${VALUE}"
			;;
		d)
			yq d -i -d'*' "${YAML_PATH}" "${query}"
			;;
		*)
			usage
			exit 1
			;;
	esac
}

handle_v4() {
	query=".${QUERY#.}"
	case ${ACTION} in
		r)
			yq "${query}" "${YAML_PATH}"
			;;
		w)
			export VALUE
			yq -i "${query} = strenv(VALUE)" "${YAML_PATH}"
			;;
		d)
			yq -i "del(${query})" "${YAML_PATH}"
			;;
		*)
			usage
			exit 1
			;;
	esac
}

if [ "$QUERY" == "-h" ]; then
	usage
	exit 0
elif [ $# -lt 3 ]; then
	usage >&2
	exit 1
fi

if ! command -v yq > /dev/null; then
	echo "yq not found in path" >&2
	exit 1
fi

if yq --version | grep '^.* version v4.*$' > /dev/null; then
	handle_v4
elif yq --version | grep '^.* version 3.*$' > /dev/null; then
	handle_v3
else
	echo "unsupported yq version" >&2
	exit 1
fi
