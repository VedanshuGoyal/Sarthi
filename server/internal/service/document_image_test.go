package service

import (
	"bytes"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"testing"
)

func TestProcessDocumentImageStripsEXIF(t *testing.T) {
	// A phone photo's EXIF block carries the GPS coordinates of wherever the
	// document was photographed — usually the driver's home. Re-encoding is
	// what drops it, so this is the test that matters most in this file.
	withEXIF := jpegWithEXIF(t, 200, 150)
	if !bytes.Contains(withEXIF, []byte("Exif\x00\x00")) {
		t.Fatal("test fixture has no EXIF block to strip")
	}

	got, err := processDocumentImage(withEXIF)
	if err != nil {
		t.Fatalf("processDocumentImage: %v", err)
	}

	if bytes.Contains(got, []byte("Exif\x00\x00")) {
		t.Error("processed image still carries an EXIF block")
	}
	if bytes.Contains(got, []byte("28.6139")) {
		t.Error("processed image still carries the EXIF GPS payload")
	}
	if _, err := jpeg.Decode(bytes.NewReader(got)); err != nil {
		t.Errorf("processed image is not decodable JPEG: %v", err)
	}
}

func TestProcessDocumentImageNormalisesPNGToJPEG(t *testing.T) {
	got, err := processDocumentImage(encodePNG(t, 120, 90))
	if err != nil {
		t.Fatalf("processDocumentImage: %v", err)
	}
	if _, err := jpeg.Decode(bytes.NewReader(got)); err != nil {
		t.Errorf("PNG upload was not stored as JPEG: %v", err)
	}
}

func TestProcessDocumentImageDownscalesOversizeEdge(t *testing.T) {
	const width, height = MaxDocumentEdge * 2, MaxDocumentEdge
	got, err := processDocumentImage(encodeJPEG(t, width, height))
	if err != nil {
		t.Fatalf("processDocumentImage: %v", err)
	}

	cfg, _, err := image.DecodeConfig(bytes.NewReader(got))
	if err != nil {
		t.Fatalf("DecodeConfig: %v", err)
	}
	if cfg.Width != MaxDocumentEdge {
		t.Errorf("width = %d, want %d", cfg.Width, MaxDocumentEdge)
	}
	// Aspect ratio preserved: a squashed licence is an unreadable licence.
	if want := MaxDocumentEdge / 2; cfg.Height != want {
		t.Errorf("height = %d, want %d", cfg.Height, want)
	}
}

func TestProcessDocumentImageLeavesSmallImagesAlone(t *testing.T) {
	got, err := processDocumentImage(encodeJPEG(t, 640, 480))
	if err != nil {
		t.Fatalf("processDocumentImage: %v", err)
	}

	cfg, _, err := image.DecodeConfig(bytes.NewReader(got))
	if err != nil {
		t.Fatalf("DecodeConfig: %v", err)
	}
	if cfg.Width != 640 || cfg.Height != 480 {
		t.Errorf("dimensions = %dx%d, want 640x480", cfg.Width, cfg.Height)
	}
}

func TestProcessDocumentImageRejectsNonImages(t *testing.T) {
	tests := map[string][]byte{
		"empty":           nil,
		"plain text":      []byte("this is not an image"),
		"truncated JPEG":  encodeJPEG(t, 64, 64)[:20],
		"executable-ish":  {0x7f, 'E', 'L', 'F', 0x02, 0x01, 0x01, 0x00},
		"JPEG magic only": {0xff, 0xd8, 0xff, 0xe0},
		"zip disguised":   []byte("PK\x03\x04payload"),
	}

	for name, input := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := processDocumentImage(input); !errors.Is(err, ErrUnsupportedImage) {
				t.Errorf("error = %v, want ErrUnsupportedImage", err)
			}
		})
	}
}

func TestProcessDocumentImageRejectsOversizeUpload(t *testing.T) {
	_, err := processDocumentImage(make([]byte, MaxDocumentBytes+1))
	if !errors.Is(err, ErrDocumentTooLarge) {
		t.Errorf("error = %v, want ErrDocumentTooLarge", err)
	}
}

// A decompression bomb is a small file declaring enormous dimensions; decoding
// one would allocate width*height*4 bytes. The header check must catch it
// before any pixels are decoded.
func TestProcessDocumentImageRejectsDecompressionBomb(t *testing.T) {
	bomb := pngHeaderClaiming(t, 40_000, 40_000)
	if _, err := processDocumentImage(bomb); !errors.Is(err, ErrDocumentTooLarge) {
		t.Errorf("error = %v, want ErrDocumentTooLarge", err)
	}
}

// --- fixtures ------------------------------------------------------------

// testImage draws a recognisable gradient so a resize has something to
// resample rather than a flat colour that would survive any transformation.
func testImage(width, height int) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := range height {
		for x := range width {
			img.Set(x, y, color.RGBA{
				R: uint8(x % 256),
				G: uint8(y % 256),
				B: 0x40,
				A: 0xff,
			})
		}
	}
	return img
}

func encodeJPEG(t *testing.T, width, height int) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, testImage(width, height), nil); err != nil {
		t.Fatalf("encoding JPEG fixture: %v", err)
	}
	return buf.Bytes()
}

func encodePNG(t *testing.T, width, height int) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := png.Encode(&buf, testImage(width, height)); err != nil {
		t.Fatalf("encoding PNG fixture: %v", err)
	}
	return buf.Bytes()
}

// jpegWithEXIF splices an APP1/EXIF segment into a freshly encoded JPEG, the
// way a phone camera would. Go's encoder writes none, so it has to be added
// here for the stripping test to mean anything.
func jpegWithEXIF(t *testing.T, width, height int) []byte {
	t.Helper()
	base := encodeJPEG(t, width, height)

	// Stand-in for the GPS tags a real camera writes.
	payload := append([]byte("Exif\x00\x00"), []byte("GPSLatitude=28.6139;GPSLongitude=77.2090")...)
	length := len(payload) + 2 // the length field counts itself

	var out bytes.Buffer
	out.Write(base[:2]) // SOI
	out.Write([]byte{0xff, 0xe1, byte(length >> 8), byte(length)})
	out.Write(payload)
	out.Write(base[2:])
	return out.Bytes()
}

// pngHeaderClaiming builds a PNG whose IHDR declares the given dimensions, so
// DecodeConfig reports them without the file carrying that many pixels.
func pngHeaderClaiming(t *testing.T, width, height int) []byte {
	t.Helper()
	// Encode a tiny real PNG, then overwrite the width/height in its IHDR —
	// a few hundred bytes on the wire claiming billions of pixels.
	raw := encodePNG(t, 1, 1)

	// PNG layout: 8-byte signature, then the IHDR chunk as
	// [4 length][4 "IHDR"][13 data][4 CRC]. The data starts with width and
	// height as big-endian uint32s.
	const (
		chunkStart = 8              // after the signature
		typeStart  = chunkStart + 4 // "IHDR"
		dataStart  = typeStart + 4  // width, height, then 5 more bytes
		crcStart   = dataStart + 13 // IHDR data is always 13 bytes
	)
	be32(raw[dataStart:], uint32(width))
	be32(raw[dataStart+4:], uint32(height))

	// The CRC covers the chunk type and data, and Go's decoder checks it, so
	// it has to be recomputed for DecodeConfig to report the new dimensions.
	be32(raw[crcStart:], crc32.ChecksumIEEE(raw[typeStart:crcStart]))
	return raw
}

func be32(b []byte, v uint32) {
	b[0] = byte(v >> 24)
	b[1] = byte(v >> 16)
	b[2] = byte(v >> 8)
	b[3] = byte(v)
}
