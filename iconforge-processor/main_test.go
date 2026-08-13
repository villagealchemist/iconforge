package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var releaseVersion string

const (
	testColorGreen         = "\x1b[32m"
	testColorRed           = "\x1b[31m"
	testColorCyan          = "\x1b[36m"
	testColorYellow        = "\x1b[33m"
	testColorBrightMagenta = "\x1b[95m"
	testColorReset         = "\x1b[0m"
)

func testSymbol(label string) string {
	switch label {
	case "PASS":
		return "✓"
	case "FAIL":
		return "✗"
	case "RUN":
		return "▸"
	case "SKIP":
		return "○"
	case "INFO":
		return "ⓘ"
	default:
		return "·"
	}
}

func testStatus(color, label, message string) string {
	return fmt.Sprintf("%s%s [%s]%s %s", color, testSymbol(label), label, testColorReset, message)
}

// prettyTestStart sets up consistent logging for each test
func prettyTestStart(t *testing.T, name string) {
	t.Helper()
	t.Log(testStatus(testColorCyan, "RUN", name))
	t.Cleanup(func() {
		if t.Failed() {
			t.Log(testStatus(testColorRed, "FAIL", name))
		} else {
			t.Log(testStatus(testColorGreen, "PASS", name))
		}
	})
}

// TestMain runs before all other tests
func TestMain(m *testing.M) {
	fmt.Println(testStatus(testColorCyan, "RUN", "Running iconforge-processor Go tests"))

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
		fmt.Println(testStatus(testColorRed, "FAIL", "One or more tests failed"))
	} else {
		fmt.Println(testStatus(testColorGreen, "PASS", "All tests passed"))
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

func TestStatusOutputIsColoredAndReadable(t *testing.T) {
	prettyTestStart(t, "colored status output")
	testCases := []struct {
		color    string
		label    string
		expected string
	}{
		{testColorGreen, "PASS", "\x1b[32m✓ [PASS]\x1b[0m example"},
		{testColorRed, "FAIL", "\x1b[31m✗ [FAIL]\x1b[0m example"},
		{testColorCyan, "RUN", "\x1b[36m▸ [RUN]\x1b[0m example"},
		{testColorYellow, "SKIP", "\x1b[33m○ [SKIP]\x1b[0m example"},
		{testColorBrightMagenta, "INFO", "\x1b[95mⓘ [INFO]\x1b[0m example"},
	}

	for _, tc := range testCases {
		status := testStatus(tc.color, tc.label, "example")
		if status != tc.expected {
			t.Errorf("unexpected %s status output %q", tc.label, status)
		}
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
	expectedChunks := []struct {
		chunkType string
		size      int
	}{
		{"icp4", 16},
		{"ic11", 32},
		{"icp5", 32},
		{"ic12", 64},
		{"ic07", 128},
		{"ic13", 256},
		{"ic08", 256},
		{"ic14", 512},
		{"ic09", 512},
		{"ic10", 1024},
	}
	offset := 8
	for _, expected := range expectedChunks {
		if offset+8 > len(data) {
			t.Fatalf("missing %s chunk", expected.chunkType)
		}
		chunkType := string(data[offset : offset+4])
		chunkLength := int(binary.BigEndian.Uint32(data[offset+4 : offset+8]))
		if chunkType != expected.chunkType {
			t.Fatalf("expected %s chunk, got %s", expected.chunkType, chunkType)
		}
		if chunkLength < 8 || offset+chunkLength > len(data) {
			t.Fatalf("invalid %s chunk length %d", chunkType, chunkLength)
		}
		config, err := png.DecodeConfig(bytes.NewReader(data[offset+8 : offset+chunkLength]))
		if err != nil {
			t.Fatalf("decode %s chunk: %v", chunkType, err)
		}
		if config.Width != expected.size || config.Height != expected.size {
			t.Errorf("%s chunk is %dx%d, expected %dx%d", chunkType, config.Width, config.Height, expected.size, expected.size)
		}
		offset += chunkLength
	}
	if offset != len(data) {
		t.Fatalf("unexpected data after final chunk: %d bytes", len(data)-offset)
	}
}

func TestCreateICNSRoundTripsThroughIconutil(t *testing.T) {
	prettyTestStart(t, "ICNS iconset round trip")
	if _, err := exec.LookPath("iconutil"); err != nil {
		t.Skip("iconutil is unavailable")
	}

	tempDir := t.TempDir()
	sizes := []int{16, 32, 64, 128, 256, 512, 1024}
	inputs := make([]string, 0, len(sizes))
	for _, size := range sizes {
		path := filepath.Join(tempDir, fmt.Sprintf("%d.png", size))
		createTestImage(t, size, size, path)
		inputs = append(inputs, path)
	}

	icnsPath := filepath.Join(tempDir, "test.icns")
	if err := createICNS(icnsPath, inputs); err != nil {
		t.Fatalf("create ICNS: %v", err)
	}
	iconsetPath := filepath.Join(tempDir, "test.iconset")
	if output, err := exec.Command("iconutil", "-c", "iconset", "-o", iconsetPath, icnsPath).CombinedOutput(); err != nil {
		t.Fatalf("iconutil round trip: %v\n%s", err, output)
	}

	expectedFiles := []string{
		"icon_16x16.png",
		"icon_16x16@2x.png",
		"icon_32x32.png",
		"icon_32x32@2x.png",
		"icon_128x128.png",
		"icon_128x128@2x.png",
		"icon_256x256.png",
		"icon_256x256@2x.png",
		"icon_512x512.png",
		"icon_512x512@2x.png",
	}
	for _, name := range expectedFiles {
		if _, err := os.Stat(filepath.Join(iconsetPath, name)); err != nil {
			t.Errorf("missing round-tripped representation %s: %v", name, err)
		}
	}
}
