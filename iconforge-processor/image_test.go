package main

import (
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

// Helper function to create a test image
func createTestImage(t *testing.T, width, height int, filename string) {
	img := image.NewRGBA(image.Rect(0, 0, width, height))

	// Fill with a simple pattern
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			// Create a gradient pattern
			r := uint8(x * 255 / width)
			g := uint8(y * 255 / height)
			b := uint8((x + y) * 255 / (width + height))
			img.Set(x, y, color.RGBA{r, g, b, 255})
		}
	}

	file, err := os.Create(filename)
	if err != nil {
		t.Fatalf("Failed to create test image: %v", err)
	}
	defer file.Close()

	if err := png.Encode(file, img); err != nil {
		t.Fatalf("Failed to encode test image: %v", err)
	}
}

// Test image loading
func TestLoadImage(t *testing.T) {
	prettyTestStart(t, "load image")
	// Create test image
	testFile := filepath.Join("testdata", "test_load.png")
	os.MkdirAll("testdata", 0755)
	createTestImage(t, 100, 100, testFile)
	defer os.Remove(testFile)

	// Test loading
	img, err := loadImage(testFile)
	if err != nil {
		t.Fatalf("Failed to load image: %v", err)
	}

	bounds := img.Bounds()
	if bounds.Dx() != 100 || bounds.Dy() != 100 {
		t.Errorf("Expected 100x100 image, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

// Test image resizing
func TestResizeImage(t *testing.T) {
	prettyTestStart(t, "resize image")
	os.MkdirAll("testdata", 0755)

	testCases := []struct {
		name         string
		inputWidth   int
		inputHeight  int
		outputWidth  int
		outputHeight int
	}{
		{"downscale", 512, 512, 256, 256},
		{"upscale", 128, 128, 256, 256},
		{"aspect change", 200, 100, 100, 100},
		{"small to icon", 64, 64, 16, 16},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			prettyTestStart(t, tc.name)
			inputFile := filepath.Join("testdata", "input_"+tc.name+".png")
			outputFile := filepath.Join("testdata", "output_"+tc.name+".png")

			// Create test input
			createTestImage(t, tc.inputWidth, tc.inputHeight, inputFile)
			defer os.Remove(inputFile)
			defer os.Remove(outputFile)

			// Test resize
			err := resizeImage(inputFile, tc.outputWidth, tc.outputHeight, outputFile)
			if err != nil {
				t.Fatalf("Failed to resize image: %v", err)
			}

			// Verify output
			img, err := loadImage(outputFile)
			if err != nil {
				t.Fatalf("Failed to load resized image: %v", err)
			}

			bounds := img.Bounds()
			if bounds.Dx() != tc.outputWidth || bounds.Dy() != tc.outputHeight {
				t.Errorf("Expected %dx%d image, got %dx%d",
					tc.outputWidth, tc.outputHeight, bounds.Dx(), bounds.Dy())
			}
		})
	}
}

// Test image conversion
func TestConvertImage(t *testing.T) {
	prettyTestStart(t, "convert image")
	os.MkdirAll("testdata", 0755)

	inputFile := filepath.Join("testdata", "convert_input.png")
	outputFile := filepath.Join("testdata", "convert_output.png")

	createTestImage(t, 200, 200, inputFile)
	defer os.Remove(inputFile)
	defer os.Remove(outputFile)

	err := convertImage(inputFile, outputFile)
	if err != nil {
		t.Fatalf("Failed to convert image: %v", err)
	}

	// Verify output exists and is loadable
	img, err := loadImage(outputFile)
	if err != nil {
		t.Fatalf("Failed to load converted image: %v", err)
	}

	bounds := img.Bounds()
	if bounds.Dx() != 200 || bounds.Dy() != 200 {
		t.Errorf("Expected 200x200 image, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

// Benchmark resize performance
func BenchmarkResizeImage(b *testing.B) {
	os.MkdirAll("testdata", 0755)
	inputFile := filepath.Join("testdata", "bench_input.png")
	outputFile := filepath.Join("testdata", "bench_output.png")

	// Create a large test image
	img := image.NewRGBA(image.Rect(0, 0, 1024, 1024))
	file, _ := os.Create(inputFile)
	png.Encode(file, img)
	file.Close()

	defer os.Remove(inputFile)
	defer os.Remove(outputFile)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		resizeImage(inputFile, 512, 512, outputFile)
	}
}

// Test error handling
func TestLoadImageErrors(t *testing.T) {
	prettyTestStart(t, "load image error cases")
	testCases := []struct {
		name     string
		filename string
	}{
		{"nonexistent file", "does_not_exist.png"},
		{"invalid file", "invalid.txt"},
	}

	// Create invalid.txt
	os.WriteFile("testdata/invalid.txt", []byte("not an image"), 0644)
	defer os.Remove("testdata/invalid.txt")

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			prettyTestStart(t, tc.name)
			_, err := loadImage(tc.filename)
			if err == nil {
				t.Errorf("Expected error when loading %s, but got none", tc.filename)
			}
		})
	}
}
