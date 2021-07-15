package mounts

import (
	"bufio"
	"fmt"
	"io/ioutil"
	"net"
	"os"
	"os/exec"
	"path"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

const (
	socketPath     = "/var/run/vc/vm/foobar/console.sock"
	kataConfigPath = "/usr/share/kata-containers/configuration.toml"
)

var (
	kataConfigBackup = strings.Join([]string{kataConfigPath, "bak"}, ".")
)

func testOverConsole(cmd, match, socket string) bool {
	conn, err := net.DialTimeout("unix", socket, 10*time.Second)
	if err != nil {
		fmt.Println("failed to connect: %w", err)
		return false
	}
	defer conn.Close()

	if _, err = conn.Write([]byte(cmd)); err != nil {
		conn.Close()
		return false
	}

	errChan := make(chan error)

	go func() {
		reader := bufio.NewReader(conn)
		// expect echo from shell, skip what we sent and ignore first response
		if _, err := reader.ReadString('\n'); err != nil {
			errChan <- err
			fmt.Println("failed to read: ", err)
			return
		}

		if _, err = reader.ReadString('\n'); err != nil {
			errChan <- err
			fmt.Println("failed to read: ", err)
			return
		}

		for {
			response, err := reader.ReadString('\n')
			if err != nil {
				errChan <- err
				fmt.Println("failed to read: ", err)
				return
			}
			fmt.Println("rx:", response)
			if strings.Contains(response, match) {
				errChan <- nil
			}
		}
	}()

	select {
	case err = <-errChan:
		if err != nil {
			conn.Close()
			fmt.Println("there was an error: %w", err)
			return false
		}
	case <-time.After(10 * time.Second):
		fmt.Println("timeout trying to get response: %w", err)
		return false
	}
	return true
}

func enableSandboxMounts(basedir string) error {
	mountPath := path.Join(basedir, "test-mount")
	filePath := path.Join(mountPath, "test-file")

	mounts := strings.Join([]string{"['", mountPath, "', '", filePath, "']"}, "")

	execCmd := exec.Command("crudini", "--set", kataConfigPath, "runtime", "sandbox_bind_mounts", mounts)
	return execCmd.Run()
}

func enableDebugConsole() error {
	execCmd := exec.Command("crudini", "--set", kataConfigPath, "hypervisor.qemu", "kernel_params", "\"agent.debug_console\"")
	return execCmd.Run()
}

func cleanup() {

	execCmd := exec.Command("ctr", "task", "kill", "foobar")
	execCmd.Run()

	execCmd = exec.Command("ctr", "task", "delete", "foobar")
	execCmd.Run()

	execCmd = exec.Command("ctr", "container", "delete", "foobar")
	execCmd.Run()

	restoreToml()

}

func startTestContainer() error {
	//sudo ctr run --rm --runtime io.containerd.kata.v2 -d docker.io/library/busybox:latest foobar sh
	execCmd := exec.Command("ctr", "run", "--rm", "--runtime", "io.containerd.kata.v2", "-d", "docker.io/library/busybox:latest", "foobar", "sh")
	return execCmd.Run()
}

func saveToml() error {
	execCmd := exec.Command("cp", kataConfigPath, kataConfigBackup)
	return execCmd.Run()
}

func restoreToml() error {
	execCmd := exec.Command("cp", kataConfigBackup, kataConfigPath)
	return execCmd.Run()
}

func createSandboxMount(tmpdir string) error {
	// Create sandbox mount data:
	os.Mkdir(path.Join(tmpdir, "test-mount"), os.FileMode(0750))
	d1 := []byte("hello hello!")
	return ioutil.WriteFile(path.Join(tmpdir, "test-mount", "test-file"), d1, 0644)
}

func prepareRuntime(mountPath string) error {
	if err := saveToml(); err != nil {
		return err
	}

	if err := enableDebugConsole(); err != nil {
		return err
	}

	if err := createSandboxMount(mountPath); err != nil {
		return err
	}

	if err := enableSandboxMounts(mountPath); err != nil {
		return err
	}

	return nil
}

var _ = Describe("Test sandbox bindmounts", func() {
	var (
		tmpdir string
		result bool
	)

	BeforeEach(func() {
		tmpdir, err := ioutil.TempDir("", "")
		Expect(err).To(BeNil())

		err = prepareRuntime(tmpdir)
		Expect(err).To(BeNil())

		err = startTestContainer()
		Expect(err).To(BeNil())
	})

	AfterEach(func() {
		os.RemoveAll(tmpdir)
		cleanup()
	})

	Context("Check sandbox bind-mount functionality", func() {
		It("Should see subdirectory of mount", func() {
			result = testOverConsole(fmt.Sprintf("ls /run/kata-containers/shared/containers/sandbox-mounts/test-mount/\n"), "test-file", socketPath)
			Expect(result).To(Equal(true))

			result = testOverConsole(fmt.Sprintf("echo 'should fail' >> /run/kata-containers/shared/containers/sandbox-mounts/test-mount/test-file\n"), "Read-only", socketPath)
			Expect(result).To(Equal(true))

			result = testOverConsole(fmt.Sprintf("cat /run/kata-containers/shared/containers/sandbox-mounts/test-mount/test-file | grep hello\n"), "hello", socketPath)
			Expect(result).To(Equal(true))

		})
	})
})
