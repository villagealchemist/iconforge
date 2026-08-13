package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var releaseVersion string

// prettyTestStart sets up consistent logging for each test
func prettyTestStart(t *testing.T, name string) {
	t.Helper()
	t.Logf("▶️  %s", name)
	t.Cleanup(func() {
		if t.Failed() {
			// mark as failed
			t.Logf("❌ Failed: %s", name)
		} else {
			// mark as passed
			t.Logf("✅ Passed: %s", name)
		}
	})
}

// TestMain runs before all other tests
func TestMain(m *testing.M) {
	fmt.Println("🧪 Running iconforge-processor Go tests...")

	// Build the binary for integration tests
	versionBytes, err := os.ReadFile(filepath.Join("..", "VERSION"))
	if err != nil {
		panic("Failed to read release version: " + err.Error())
	}
	releaseVersion = strings.TrimSpace(string(versionBytes))
	if err := exec.Command("go", "build", "-ldflags", "-X main.version="+releaseVersion, "-o", "iconforge-processor-test").Run(); err != nil {
		panic("Failed to build test binary: " + err.Error())
	}

	// Run tests
	code := m.Run()

	// Cleanup
	_ = os.Remove("iconforge-processor-test")

	if code != 0 {
		fmt.Println("❗ One or more tests failed")
	} else {
		fmt.Println("🎉 All tests passed!")
	}
	os.Exit(code)
}

// Test version command
func TestVersionCommand(t *testing.T) {
	prettyTestStart(t, "version command")
	cmd := exec.Command("./iconforge-processor-test", "version")
	output, err := cmd.Output()
	if err != nil {
		t.Fatalf("Version command failed: %v", err)
	}

	expected := "iconforge-processor v" + releaseVersion
	if string(output) != expected+"\n" {
		t.Errorf("Expected %q, got %q", expected, string(output))
	}
}

// Test invalid command
func TestInvalidCommand(t *testing.T) {
	prettyTestStart(t, "invalid command should fail")
	cmd := exec.Command("./iconforge-processor-test", "invalid")
	err := cmd.Run()
	if err == nil {
		t.Error("Expected invalid command to fail, but it succeeded")
	}
}

// Test missing arguments
func TestMissingArguments(t *testing.T) {
	prettyTestStart(t, "missing arguments cases fail")
	testCases := []struct {
		name string
		args []string
	}{
		{"no args", []string{}},
		{"resize missing args", []string{"resize"}},
		{"resize partial args", []string{"resize", "input.png"}},
		{"convert missing args", []string{"convert"}},
		{"icns missing args", []string{"icns"}},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			prettyTestStart(t, tc.name)
			cmd := exec.Command("./iconforge-processor-test", tc.args...)
			err := cmd.Run()
			if err == nil {
				t.Errorf("Expected %s to fail, but it succeeded", tc.name)
			}
		})
	}
}

func TestCreateICNS(t *testing.T) {
	prettyTestStart(t, "native ICNS assembly")
	tempDir := t.TempDir()
	sizes := []int{16, 32, 64, 128, 256, 512, 1024}
	inputs := make([]string, 0, len(sizes))
	for _, size := range sizes {
		path := filepath.Join(tempDir, fmt.Sprintf("%d.png", size))
		createTestImage(t, size, size, path)
		inputs = append(inputs, path)
	}

	output := filepath.Join(tempDir, "test.icns")
	if err := createICNS(output, inputs); err != nil {
		t.Fatalf("create ICNS: %v", err)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if len(data) < 8 || string(data[:4]) != "icns" {
		t.Fatalf("invalid ICNS header")
	}
	declaredLength := int(data[4])<<24 | int(data[5])<<16 | int(data[6])<<8 | int(data[7])
	if declaredLength != len(data) {
		t.Fatalf("declared length %d, actual length %d", declaredLength, len(data))
	}
	for _, chunkType := range []string{"icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10"} {
		if !bytes.Contains(data, []byte(chunkType)) {
			t.Errorf("missing %s chunk", chunkType)
		}
	}
}
