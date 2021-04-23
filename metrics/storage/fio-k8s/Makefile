#
## Copyright (c) 2021 Intel Corporation
#
## SPDX-License-Identifier: Apache-2.0
#

MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MKFILE_DIR := $(dir $(MKFILE_PATH))
build:
	make -C $(MKFILE_DIR)/cmd/fiotest/ gomod
	make -C $(MKFILE_DIR)/cmd/fiotest/
