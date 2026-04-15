package main

import (
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
	"golang.org/x/image/webp"
)

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
	case "version":
		fmt.Println("iconforge-processor v1.0.0")
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
	fmt.Println("  iconforge-processor info <input>")
	fmt.Println("  iconforge-processor version")
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
