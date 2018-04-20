// Copyright (c) 2018 Intel Corporation
//
// SPDX-License-Identifier: Apache-2.0

package docker

import (
	"fmt"
	"math"
	"strconv"
	"strings"

	. "github.com/kata-containers/tests"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/ginkgo/extensions/table"
	. "github.com/onsi/gomega"
)

func getDefaultVCPUs() int {
	args := []string{"--rm", Image, "sh", "-c", "sleep 5; nproc"}
	stdout, _, exitCode := dockerRun(args...)
	if stdout == "" || exitCode != 0 {
		LogIfFail("Failed to get default number of vCPUs")
		return -1
	}

	stdout = strings.Trim(stdout, "\n\t ")
	vcpus, err := strconv.Atoi(stdout)
	if err != nil {
		LogIfFail("Failed to convert '%s' to int", stdout)
		return -1
	}

	return vcpus
}

func withCPUPeriodAndQuota(quota, period, defaultVCPUs int, fail bool) TableEntry {
	var msg string

	if fail {
		msg = "should fail"
	} else {
		msg = fmt.Sprintf("should have %d CPUs", ((quota+period-1)/period)+defaultVCPUs)
	}

	return Entry(msg, quota, period, fail)
}

func withCPUConstraint(cpus float64, defaultVCPUs int, fail bool) TableEntry {
	var msg string
	c := int(math.Ceil(cpus))

	if fail {
		msg = "should fail"
	} else {
		msg = fmt.Sprintf("should have %d CPUs", c+defaultVCPUs)
	}

	return Entry(msg, c, fail)
}

var _ = Describe("Hot plug CPUs", func() {
	var (
		args         []string
		id           string
		vCPUs        int
		defaultVCPUs = getDefaultVCPUs()
		cpuSysPath   string
		waitTime     int
		maxTries     int
		checkCpusCmd string
	)

	BeforeEach(func() {
		id = RandID(30)
		cpuSysPath = "/sys/devices/system/cpu"
		checkCpusCmd = `c=0; while [[ "$(cat %s/cpu%d/online 2> /dev/null)" != "1" ]] && [[ $c < %d ]]; do sleep %d; ((c++)); done; nproc --all`
		waitTime = 5
		maxTries = 5
		args = []string{"--rm", "--name", id}
		Expect(defaultVCPUs).To(BeNumerically(">", 0))
	})

	AfterEach(func() {
		Expect(ExistDockerContainer(id)).NotTo(BeTrue())
	})

	DescribeTable("container with CPU period and quota",
		func(quota, period int, fail bool) {
			vCPUs = ((quota + period - 1) / period) + defaultVCPUs
			args = append(args, "--cpu-quota", fmt.Sprintf("%d", quota),
				"--cpu-period", fmt.Sprintf("%d", period), Image, "sh", "-c",
				fmt.Sprintf(checkCpusCmd, cpuSysPath, vCPUs-1, maxTries, waitTime))
			stdout, _, exitCode := dockerRun(args...)
			if fail {
				Expect(exitCode).ToNot(BeZero())
				return
			}
			Expect(exitCode).To(BeZero())
			Expect(fmt.Sprintf("%d", vCPUs)).To(Equal(strings.Trim(stdout, "\n\t ")))
		},
		withCPUPeriodAndQuota(30000, 20000, defaultVCPUs, false),
		withCPUPeriodAndQuota(30000, 10000, defaultVCPUs, false),
		withCPUPeriodAndQuota(10000, 10000, defaultVCPUs, false),
		withCPUPeriodAndQuota(10000, 100, defaultVCPUs, true),
	)

	DescribeTable("container with CPU constraint",
		func(cpus int, fail bool) {
			args = append(args, "--cpus", fmt.Sprintf("%d", cpus), Image, "sh", "-c",
				fmt.Sprintf(checkCpusCmd, cpuSysPath, vCPUs-1, maxTries, waitTime))
			stdout, _, exitCode := dockerRun(args...)
			if fail {
				Expect(exitCode).ToNot(BeZero())
				return
			}
			Expect(exitCode).To(BeZero())
			Expect(fmt.Sprintf("%d", cpus+defaultVCPUs)).To(Equal(strings.Trim(stdout, "\n\t ")))
		},
		withCPUConstraint(1, defaultVCPUs, false),
		withCPUConstraint(1.5, defaultVCPUs, false),
		withCPUConstraint(2, defaultVCPUs, false),
		withCPUConstraint(2.5, defaultVCPUs, false),
		withCPUConstraint(-5, defaultVCPUs, true),
	)
})

var _ = Describe("CPU constraints", func() {
	var (
		args          []string
		id            string
		shares        int
		quota         int
		period        int
		sharesSysPath string
		quotaSysPath  string
		periodSysPath string
	)

	BeforeEach(func() {
		sharesSysPath = "/sys/fs/cgroup/cpu,cpuacct/cpu.shares"
		quotaSysPath = "/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_quota_us"
		periodSysPath = "/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_period_us"
		shares = 300
		quota = 2000
		period = 1500
		id = RandID(30)
		args = []string{"--rm", "--name", id}
	})

	AfterEach(func() {
		Expect(ExistDockerContainer(id)).NotTo(BeTrue())
	})

	Describe("checking container with CPU constraints", func() {
		Context(fmt.Sprintf("with shares equal to %d", shares), func() {
			It(fmt.Sprintf("%s should have %d", sharesSysPath, shares), func() {
				args = append(args, "--cpu-shares", fmt.Sprintf("%d", shares), Image, "cat", sharesSysPath)
				stdout, _, exitCode := dockerRun(args...)
				Expect(exitCode).To(BeZero())
				Expect(fmt.Sprintf("%d", shares)).To(Equal(strings.Trim(stdout, "\n\t ")))
			})
		})

		Context(fmt.Sprintf("with period equal to %d", period), func() {
			It(fmt.Sprintf("%s should have %d", periodSysPath, period), func() {
				args = append(args, "--cpu-period", fmt.Sprintf("%d", period), Image, "cat", periodSysPath)
				stdout, _, exitCode := dockerRun(args...)
				Expect(exitCode).To(BeZero())
				Expect(fmt.Sprintf("%d", period)).To(Equal(strings.Trim(stdout, "\n\t ")))
			})
		})

		Context(fmt.Sprintf("with quota equal to %d", quota), func() {
			It(fmt.Sprintf("%s should have %d", quotaSysPath, quota), func() {
				args = append(args, "--cpu-quota", fmt.Sprintf("%d", quota), Image, "cat", quotaSysPath)
				stdout, _, exitCode := dockerRun(args...)
				Expect(exitCode).To(BeZero())
				Expect(fmt.Sprintf("%d", quota)).To(Equal(strings.Trim(stdout, "\n\t ")))
			})
		})
	})
})
