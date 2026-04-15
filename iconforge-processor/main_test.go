package main

import (
	"fmt"
	"os"
	"os/exec"
	"testing"
)

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
	if err := exec.Command("go", "build", "-o", "iconforge-processor-test").Run(); err != nil {
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

	expected := "iconforge-processor v1.0.0"
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
