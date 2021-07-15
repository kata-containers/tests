package mounts_test

import (
	"testing"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

func TestMounts(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Mounts Suite")
}
