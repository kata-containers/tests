#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
source "${dir_path}/data/lib.sh"
source /etc/os-release || source /usr/lib/os-release
image="fedora"
payload="tail -f /dev/null"
container_name="test-pmem"
osbuilder_repository="github.com/kata-containers/osbuilder"
osbuilder_repository_path="${GOPATH}/src/${osbuilder_repository}"
test_directory_name="test_pmem1"
test_directory=$(mktemp -d --suffix="${test_directory_name}")
TEST_INITRD="${TEST_INITRD:-no}"
experimental_qemu="${experimental_qemu:-false}"

if [ "$TEST_INITRD" == "yes" ]; then
	echo "Skip pmem test: nvdimm is disabled when initrd is used as rootfs"
	exit 0
fi

if [ "$experimental_qemu" == "true" ]; then
	echo "Skip pmem test: experimental qemu doesn't have libpmem support"
	exit 0
fi

function setup() {
	clean_env
	check_processes
	if [ ! -d "${osbuilder_repository_path}" ]; then
		go get -d "${osbuilder_repository}" || true
	fi
}

function test_pmem_mount {
	"${dir_path}/../../cmd/pmemctl/pmemctl.sh" -s 128M -f xfs -m "${test_directory}" xfs.img

	# Running container
	docker run -d --name "${container_name}" --runtime ${RUNTIME} -v "${test_directory}:/${test_directory_name}" "${image}" sh -c "${payload}"

	# Check container
	docker exec "${container_name}" sh -exc "mount | grep ${test_directory_name} | grep '/dev/pmem' | grep 'dax'"

	sudo umount "${test_directory}"
	sudo losetup -D
	rm -f xfs.img
}

function wait_for_postgres {
	container="$1"

	for i in $(seq 1 20); do
		if docker exec -u postgres "${container}" psql -c '\l'; then
			break
		fi
		sleep 3
	done
}

function test_database {
	"${dir_path}/../../cmd/pmemctl/pmemctl.sh" -s 1G -f xfs -m "${test_directory}" xfs.img

	rows=1000000
	cont_image=postgres
	postgresql_cont_dir="/var/lib/postgresql/data"

	producer_cont="producer"
	docker run --runtime ${RUNTIME} --name "${producer_cont}" -d \
		   -v "${test_directory}":"${postgresql_cont_dir}" -v $(realpath ${dir_path}/data):/data \
		   -e POSTGRES_PASSWORD=mysecretpassword -e PGDATA="${postgresql_cont_dir}/pgdata" ${cont_image}
	docker exec "${producer_cont}" sh -c "mount | grep ${postgresql_cont_dir} | grep dax"
	docker exec "${producer_cont}" chown postgres "${postgresql_cont_dir}"
	wait_for_postgres "${producer_cont}"

	echo "Inserting into the database..."
	docker exec -u postgres "${producer_cont}" /data/dbinsert.sh ${rows}
	docker rm -f "${producer_cont}" > /dev/null

	consumer_cont="consumer"
	docker run --runtime ${RUNTIME} --name "${consumer_cont}" -d \
		   -v "${test_directory}":"${postgresql_cont_dir}/" \
		   -e POSTGRES_PASSWORD=mysecretpassword -e PGDATA="${postgresql_cont_dir}/pgdata" ${cont_image}
	wait_for_postgres "${consumer_cont}"

	echo "Checking the data base..."
	docker exec -u postgres "${consumer_cont}" psql -d "${db_name}" -c "select count(*) from ${db_table_name}" | grep ${rows}
	[ -n "$(docker exec -u postgres "${consumer_cont}" psql -d "${db_name}" --tuples-only -c "select name from ${db_table_name} where id=1;")" ]
	[ -n "$(docker exec -u postgres "${consumer_cont}" psql -d "${db_name}" --tuples-only -c "select name from ${db_table_name} where id=${rows+100};")" ]
	# check random rows
	for i in $(seq 1 20); do
		[ -n "$(docker exec -u postgres "${consumer_cont}" psql -d "${db_name}" --tuples-only -c "select name from ${db_table_name} where id=$((RANDOM%rows+1));")" ]
	done
	docker rm -f "${consumer_cont}" > /dev/null
}

function teardown() {
	clean_env
	check_processes
	sudo umount "${test_directory}"
	sudo losetup -D
	sudo rm -rf "${test_directory}"
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running pmem mount test"
test_pmem_mount

echo "Running database pmem test"
test_database
