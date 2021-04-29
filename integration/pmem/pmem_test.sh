#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
source "${dir_path}/data/lib.sh"
source /etc/os-release || source /usr/lib/os-release
osbuilder_repository="github.com/kata-containers/osbuilder"
osbuilder_repository_path="${GOPATH}/src/${osbuilder_repository}"
test_directory_name="test_pmem1"
test_directory=$(mktemp -d --suffix="${test_directory_name}")
TEST_INITRD="${TEST_INITRD:-no}"
experimental_qemu="${experimental_qemu:-false}"
# List of containers to remove before exit
list_containers=()
RUNTIME="io.containerd.kata.v2"
arch=$("${dir_path}"/../../.ci/kata-arch.sh -d)
exec_id=1

if [ "$TEST_INITRD" == "yes" ]; then
	echo "Skip pmem test: nvdimm is disabled when initrd is used as rootfs"
	exit 0
fi

if [ "$experimental_qemu" == "true" ]; then
	echo "Skip pmem test: experimental qemu doesn't have libpmem support"
	exit 0
fi

if [ "$arch" == "aarch64" ]; then
	echo "Skip pmem test: $arch can't ensure data persistence for the lack of libpmem support"
	exit 0
fi

function setup() {
	sudo systemctl restart containerd
	clean_env_ctr
	check_processes
	if [ ! -d "${osbuilder_repository_path}" ]; then
		go get -d "${osbuilder_repository}" || true
	fi
}

function ctr_exec {
	args=()
	for i; do
		if [[ $i = *" "* ]]; then
			args+=(\""${i}"\")
		else
			args+=("${i}")
		fi
	done

	sleep 5
	tmp_dir="$(mktemp -d)"
	eval ctr t exec --exec-id $((exec_id++)) --cwd / --fifo-dir "${tmp_dir}" "${args[@]}"
	ret=$?
	rm -rf "${tmp_dir}"

	return $ret
}

function ctr_rm_rf {
	container=$1
	while [ -n "$(ctr t list | grep RUNNING | grep "${container}")" ]; do
		ctr t kill -a "${container}"
		sleep 1
	done
	ctr c rm "${container}"
}

function test_pmem_mount {
	local container_name="test-pmem"
	local payload="tail -f /dev/null"
	local image="quay.io/prometheus/busybox:latest"

	"${dir_path}/../../cmd/pmemctl/pmemctl.sh" -s 128M -f xfs -m "${test_directory}" xfs.img

	ctr image pull "${image}"

	list_containers+=(${container_name})

	# Running container
	ctr run --null-io -d --runtime ${RUNTIME} --mount type=bind,src="${test_directory}",dst="/${test_directory_name}",options=rbind:rw "${image}" "${container_name}" sh -c "${payload}"

	# Check container
	ctr_exec "${container_name}" mount | grep ${test_directory_name} | grep '/dev/pmem' | grep 'dax'

	ctr_rm_rf "${container_name}"
	sudo umount "${test_directory}"
	sudo losetup -D
	rm -f xfs.img
}

function wait_for_postgres {
	container="$1"
	for i in {1..30}; do
		echo "Waiting for the data base..."
		if ctr_exec "${container}" su - postgres -c "psql -c '\l'"; then
			break
		fi
		sleep 5
	done
}

function test_database {
	"${dir_path}/../../cmd/pmemctl/pmemctl.sh" -s 1G -f xfs -m "${test_directory}" xfs.img

	rows=100
	cont_image="public.ecr.aws/ubuntu/postgres:latest"
	postgresql_cont_dir="/var/lib/postgresql/data"

	ctr image pull "${cont_image}"

	producer_cont="producer"
	list_containers+=(${producer_cont})
	ctr run --null-io --runtime ${RUNTIME} -d \
		--mount type=bind,src="${test_directory}",dst="${postgresql_cont_dir}",options=rbind:rw \
		--mount type=bind,src=$(realpath ${dir_path}/data),dst=/data,options=rbind:rw \
		--env POSTGRES_PASSWORD=mysecretpassword --env PGDATA="${postgresql_cont_dir}/pgdata" ${cont_image} "${producer_cont}"
	ctr_exec "${producer_cont}" sh -c "mount | grep ${postgresql_cont_dir} | grep dax"
	ctr_exec "${producer_cont}" chown postgres "${postgresql_cont_dir}"
	wait_for_postgres "${producer_cont}"

	echo "Inserting into the database..."
	ctr_exec "${producer_cont}" su - postgres -c "/data/dbinsert.sh ${rows}"
	ctr_rm_rf "${producer_cont}"

	consumer_cont="consumer"
	list_containers+=(${consumer_cont})
	ctr run --null-io --runtime ${RUNTIME} -d \
		--mount type=bind,src="${test_directory}",dst="${postgresql_cont_dir}/",options=rbind:rw \
		--env POSTGRES_PASSWORD=mysecretpassword --env PGDATA="${postgresql_cont_dir}/pgdata" ${cont_image} "${consumer_cont}"
	wait_for_postgres "${consumer_cont}"

	echo "Checking the data base..."
	[ -n $(ctr_exec "${consumer_cont}" su - postgres -c "psql -d ${db_name} \
		-c 'select count(*) from '${db_table_name}'' | grep ${rows}") ]

	[ -n $(ctr_exec "${consumer_cont}" su - postgres -c "psql -d ${db_name} \
	  --tuples-only -c 'select name from '${db_table_name}' where id=1;'") ]

	[ -n $(ctr_exec "${consumer_cont}" su - postgres -c "psql -d ${db_name} \
	  --tuples-only -c 'select name from '${db_table_name}' where id=${rows};'") ]

	# check random row
	[ $(ctr_exec "${consumer_cont}" su - postgres -c "psql -d ${db_name} --tuples-only -c \
	  'select name from '${db_table_name}' where \
	  id=$((RANDOM%rows+1));'" | sed '/^[[:space:]]*$/d' | wc -l) == 1 ]

	ctr_rm_rf "${consumer_cont}"
}

function teardown() {
	sudo umount "${test_directory}"
	sudo losetup -D
	sudo rm -rf "${test_directory}"
	for c in ${list_containers[*]}; do
		ctr_rm_rf "${c}" 2&> /dev/null || true
	done

	clean_env_ctr
	check_processes
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running pmem mount test"
test_pmem_mount

echo "Running database pmem test"
test_database
