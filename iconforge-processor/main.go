package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"image"
	"image/gif"
	"image/jpeg"
	"image/png"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/tiff"
	"golang.org/x/image/webp"
)

var version = "dev"

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	command := os.Args[1]
	switch command {
	case "resize":
		handleResize()
	case "convert":
		handleConvert()
	case "icns":
		handleICNS()
	case "version":
		fmt.Printf("iconforge-processor v%s\n", version)
	case "info":
		handleInfo()
	default:
		fmt.Printf("Unknown command: %s\n", command)
		printUsage()
		os.Exit(1)
	}
}

// Add this function:
func handleInfo() {
	if len(os.Args) != 3 {
		fmt.Println("Usage: iconforge-processor info <input>")
		os.Exit(1)
	}

	inputPath := os.Args[2]
	img, err := loadImage(inputPath)
	if err != nil {
		log.Fatalf("Failed to load image: %v", err)
	}

	bounds := img.Bounds()
	fmt.Printf("%dx%d", bounds.Dx(), bounds.Dy())
}

func printUsage() {
	fmt.Println("Usage:")
	fmt.Println("  iconforge-processor resize <input> <width> <height> <output>")
	fmt.Println("  iconforge-processor convert <input> <output>")
	fmt.Println("  iconforge-processor icns <output> <16.png> <32.png> <64.png> <128.png> <256.png> <512.png> <1024.png>")
	fmt.Println("  iconforge-processor info <input>")
	fmt.Println("  iconforge-processor version")
}

func handleICNS() {
	if len(os.Args) != 10 {
		fmt.Println("Usage: iconforge-processor icns <output> <16.png> <32.png> <64.png> <128.png> <256.png> <512.png> <1024.png>")
		os.Exit(1)
	}

	if err := createICNS(os.Args[2], os.Args[3:]); err != nil {
		log.Fatalf("Failed to create ICNS: %v", err)
	}
}

func createICNS(outputPath string, inputPaths []string) error {
	chunkTypes := []string{"icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10"}
	expectedSizes := []int{16, 32, 64, 128, 256, 512, 1024}
	if len(inputPaths) != len(chunkTypes) {
		return fmt.Errorf("expected %d PNG inputs, got %d", len(chunkTypes), len(inputPaths))
	}

	var payload bytes.Buffer
	for i, inputPath := range inputPaths {
		img, err := loadImage(inputPath)
		if err != nil {
			return fmt.Errorf("load %s: %w", inputPath, err)
		}
		bounds := img.Bounds()
		if bounds.Dx() != expectedSizes[i] || bounds.Dy() != expectedSizes[i] {
			return fmt.Errorf("%s must be %dx%d, got %dx%d", inputPath, expectedSizes[i], expectedSizes[i], bounds.Dx(), bounds.Dy())
		}

		pngData, err := os.ReadFile(inputPath)
		if err != nil {
			return fmt.Errorf("read %s: %w", inputPath, err)
		}
		payload.WriteString(chunkTypes[i])
		if err := binary.Write(&payload, binary.BigEndian, uint32(len(pngData)+8)); err != nil {
			return err
		}
		payload.Write(pngData)
	}

	var output bytes.Buffer
	output.WriteString("icns")
	if err := binary.Write(&output, binary.BigEndian, uint32(payload.Len()+8)); err != nil {
		return err
	}
	output.Write(payload.Bytes())
	return os.WriteFile(outputPath, output.Bytes(), 0644)
}

func handleResize() {
	if len(os.Args) != 6 {
		fmt.Println("Usage: iconforge-processor resize <input> <width> <height> <output>")
		os.Exit(1)
	}

	inputPath := os.Args[2]
	width, err := strconv.Atoi(os.Args[3])
	if err != nil {
		log.Fatalf("Invalid width: %s", os.Args[3])
	}
	height, err := strconv.Atoi(os.Args[4])
	if err != nil {
		log.Fatalf("Invalid height: %s", os.Args[4])
	}
	outputPath := os.Args[5]

	if err := resizeImage(inputPath, width, height, outputPath); err != nil {
		log.Fatalf("Failed to resize image: %v", err)
	}
}

func handleConvert() {
	if len(os.Args) != 4 {
		fmt.Println("Usage: iconforge-processor convert <input> <output>")
		os.Exit(1)
	}

	inputPath := os.Args[2]
	outputPath := os.Args[3]

	if err := convertImage(inputPath, outputPath); err != nil {
		log.Fatalf("Failed to convert image: %v", err)
	}
}

func loadImage(filename string) (image.Image, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	// Get file extension to determine format
	ext := strings.ToLower(filepath.Ext(filename))

	var img image.Image
	switch ext {
	case ".png":
		img, err = png.Decode(file)
	case ".jpg", ".jpeg":
		img, err = jpeg.Decode(file)
	case ".gif":
		img, err = gif.Decode(file)
	case ".webp":
		img, err = webp.Decode(file)
	default:
		// Try to decode automatically
		img, _, err = image.Decode(file)
	}

	return img, err
}

func saveImage(img image.Image, filename string) error {
	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	// Always save as PNG for iconforge
	return png.Encode(file, img)
}

func resizeImage(inputPath string, width, height int, outputPath string) error {
	// Load the source image
	srcImg, err := loadImage(inputPath)
	if err != nil {
		return fmt.Errorf("failed to load image: %v", err)
	}

	// Create a new image with the target dimensions
	dstImg := image.NewRGBA(image.Rect(0, 0, width, height))

	// Use high-quality scaling
	draw.CatmullRom.Scale(dstImg, dstImg.Bounds(), srcImg, srcImg.Bounds(), draw.Over, nil)

	// Save the resized image
	return saveImage(dstImg, outputPath)
}

func convertImage(inputPath, outputPath string) error {
	// Load the source image
	srcImg, err := loadImage(inputPath)
	if err != nil {
		return fmt.Errorf("failed to load image: %v", err)
	}

	// Save as PNG
	return saveImage(srcImg, outputPath)
}
