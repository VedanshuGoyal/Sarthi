package service

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png" // register PNG so a screenshot-style upload decodes too
	"math"

	"golang.org/x/image/draw"
)

// Limits on an uploaded KYC image.
const (
	// MaxDocumentBytes bounds the request body. Comfortably above a phone
	// photo at the quality the app captures, low enough that a handful of
	// concurrent uploads can't exhaust memory.
	MaxDocumentBytes = 12 << 20 // 12 MiB

	// MaxDocumentPixels rejects decompression bombs: a small file can declare
	// enormous dimensions, and decoding it would allocate width*height*4
	// bytes. Checked from the header before any pixels are decoded.
	MaxDocumentPixels = 50_000_000 // 50 MP

	// MaxDocumentEdge is the longest side kept after re-encoding. The app
	// already captures at 1600px, so this only bites when the request didn't
	// come from our client.
	MaxDocumentEdge = 1600

	// documentJPEGQuality trades size against legibility. Aadhaar and licence
	// numbers must stay readable to a human reviewer.
	documentJPEGQuality = 85
)

// DocumentContentType is what every stored document is normalised to.
const DocumentContentType = "image/jpeg"

// ErrDocumentTooLarge is returned when an upload exceeds [MaxDocumentBytes] or
// declares more than [MaxDocumentPixels].
var ErrDocumentTooLarge = errors.New("document image is too large")

// ErrUnsupportedImage is returned when an upload isn't a JPEG or PNG the
// server can decode.
var ErrUnsupportedImage = errors.New("document must be a JPEG or PNG image")

// processDocumentImage validates raw and returns it as a clean JPEG.
//
// The re-encode is the point, not a side effect. Phone photos carry EXIF, and
// EXIF carries GPS — uploading a driving licence would otherwise hand us the
// coordinates of wherever the driver photographed it, usually their home.
// Decoding to pixels and encoding fresh drops every metadata block, and as a
// bonus it means a stored "image" is always something we successfully parsed,
// never an arbitrary blob with an image extension.
func processDocumentImage(raw []byte) ([]byte, error) {
	if len(raw) == 0 {
		return nil, ErrUnsupportedImage
	}
	if len(raw) > MaxDocumentBytes {
		return nil, ErrDocumentTooLarge
	}

	// Read the header first: this reports the true format regardless of what
	// the client claimed, and gives dimensions before anything is allocated.
	cfg, format, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		return nil, ErrUnsupportedImage
	}
	if format != "jpeg" && format != "png" {
		return nil, ErrUnsupportedImage
	}
	if cfg.Width <= 0 || cfg.Height <= 0 {
		return nil, ErrUnsupportedImage
	}
	if cfg.Width*cfg.Height > MaxDocumentPixels {
		return nil, ErrDocumentTooLarge
	}

	src, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, ErrUnsupportedImage
	}

	out := downscale(src, MaxDocumentEdge)

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, out, &jpeg.Options{Quality: documentJPEGQuality}); err != nil {
		return nil, fmt.Errorf("encoding document image: %w", err)
	}
	return buf.Bytes(), nil
}

// downscale returns src resized so its longest side is at most maxEdge,
// preserving aspect ratio. Images already within the bound are returned as-is.
func downscale(src image.Image, maxEdge int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	longest := max(w, h)
	if longest <= maxEdge {
		return src
	}

	scale := float64(maxEdge) / float64(longest)
	dstW := max(1, int(math.Round(float64(w)*scale)))
	dstH := max(1, int(math.Round(float64(h)*scale)))

	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
	// CatmullRom over the faster kernels: these are documents, and a soft
	// resample can turn an Aadhaar digit into a different one.
	draw.CatmullRom.Scale(dst, dst.Bounds(), src, b, draw.Src, nil)
	return dst
}

// Limits on the driver photo customers see: a small copy of the selfie, so
// the full-size KYC image never leaves the server and the app downloads a
// few tens of kilobytes rather than half a megabyte.
const (
	// DriverPhotoEdge is the photo's longest side. The app shows it in a
	// circle at most ~64 dp across; 320 px stays sharp on a 3x screen.
	DriverPhotoEdge = 320

	driverPhotoJPEGQuality = 80
)

// makeDriverPhoto returns the customer-facing copy of a stored selfie. clean
// is what processDocumentImage produced, so it is already a metadata-free
// JPEG within the pixel limits.
func makeDriverPhoto(clean []byte) ([]byte, error) {
	src, _, err := image.Decode(bytes.NewReader(clean))
	if err != nil {
		return nil, fmt.Errorf("decoding selfie: %w", err)
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, downscale(src, DriverPhotoEdge), &jpeg.Options{Quality: driverPhotoJPEGQuality}); err != nil {
		return nil, fmt.Errorf("encoding driver photo: %w", err)
	}
	return buf.Bytes(), nil
}
