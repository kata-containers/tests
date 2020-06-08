#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is intended to run in a postgres container

script_dir="$(realpath $(dirname $0))"
source "${script_dir}/lib.sh"

rows=${1:-500}
script_dir="$(dirname $(realpath $0))"
sql_file="/var/lib/postgresql/data/sql.sql"
cat > "${sql_file}" <<EOF
CREATE TABLE ${db_table_name} (
	id serial PRIMARY KEY,
	name varchar NOT NULL,
	age int NOT NULL,
	phone varchar NOT NULL,
	birth varchar NOT NULL,
	country varchar NOT NULL,
	company varchar NOT NULL,
	email varchar NOT NULL
);
EOF

# to avoid jenkins kills the process due to inactivity
for i in $(seq 1 1000); do echo -n .; sleep 5; done &
dots_pid=$!
trap "kill -9 ${dots_pid}" EXIT

echo "generating sql file"
count=0
stop=false

export IFS=$'\n'
users=($(cat "${script_dir}/users.txt"));
while [ "${stop}" != "true" ]; do
	for line in ${users[*]}; do
		if [ ${count} -ge ${rows} ]; then
			stop=true
			break;
		fi

		IFS=' ' a=(${line//|/ }); IFS=$'\n'
		echo "INSERT INTO ${db_table_name} (name, age, phone, birth, country, company, email) VALUES ('${a[0]}', ${a[1]}, '${a[2]}', '${a[3]}', '${a[4]}', '${a[5]}', '${a[6]}');" >> \
			 "${sql_file}"

		((count++))
	done
done
unset IFS

createdb "${db_name}"
echo "running sql file"
time psql -d "${db_name}" -f "${sql_file}" > /dev/null
rm -f "${sql_file}"
