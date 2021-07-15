# Copyright (c) 2021 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#

# Include the VM runner specific targets.
include job/vm/Makefile.include

.PHONY: help
help:
	@echo "Job related targets"
	@echo ""
	@echo "  job-run-NAME             - Run the job NAME. Use KATA_TESTS_JOB_RUNNER to set the runner."
	@echo "  job-list                 - List all available CI jobs"
	@echo "help: CI targets"
	@echo "  vm-help                  - Help for the VM runner targets."
	@echo "Environment variables:"
	@echo "  KATA_TESTS_JOB_RUNNER:   - local or vm (default)"

.PHONY: job-list
job-list:
	@bash ./job/job_runner.sh -l

job-run-%:
	@bash ./job/job_runner.sh -j "$*"
