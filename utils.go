// Copyright (c) 2018 Intel Corporation
//
// SPDX-License-Identifier: Apache-2.0

package tests

import (
	"fmt"
	"os"
	"os/exec"
)

// DistroID returns the ID of the OS distribution.
func DistroID() string {
	pathFile := "/etc/os-release"
	if _, err := os.Stat(pathFile); os.IsNotExist(err) {
		pathFile = "/usr/lib/os-release"
	}
	cmd := exec.Command("sh", "-c", fmt.Sprintf("source %s; echo -n $ID", pathFile))
	id, err := cmd.CombinedOutput()
	if err != nil {
		LogIfFail("couldn't find distro ID %s\n", err)
		return ""
	}
	return string(id)
}
