// Package geo wraps the Uber H3 hexagonal grid library so the rest of the
// codebase never imports h3 directly. H3 gives us the spatial index that
// replaces Redis GEORADIUS: every driver location is reduced to an H3 cell,
// and "find drivers within R metres" becomes "gather the cells covering a
// disk of radius R, then look up the drivers bucketed in those cells".
package geo

import (
	"math"

	"github.com/uber/h3-go/v4"
)

// Cell is re-exported so callers can keep H3 out of their imports while still
// naming the type (e.g. as a map key in memstore).
type Cell = h3.Cell

// DefaultResolution is the H3 resolution used to index drivers. At resolution 9
// a hexagon spans roughly 350m across (~174m edge), a sensible bucket size for
// city-scale matching: small enough to keep per-cell driver counts low, large
// enough that a typical search radius only touches a handful of cells.
const DefaultResolution = 9

// avgEdgeLengthMeters is the average hexagon edge length in metres for each H3
// resolution 0..15 (source: H3 documentation). Used to translate a search
// radius into a number of grid rings (k).
var avgEdgeLengthMeters = [16]float64{
	1281256.011, 483056.8391, 182512.9565, 68979.22179,
	26071.75968, 9854.090990, 3724.532667, 1406.475763,
	531.4140101, 200.7861888, 75.86375297, 28.66315720,
	10.83018875, 4.092010473, 1.546099657, 0.584169442,
}

// CellAt returns the H3 cell that contains the given latitude/longitude at the
// requested resolution.
func CellAt(lat, lng float64, resolution int) (Cell, error) {
	return h3.LatLngToCell(h3.LatLng{Lat: lat, Lng: lng}, resolution)
}

// DiskForRadius returns every H3 cell that could contain a point within
// radiusMeters of (lat, lng), at the given resolution. Because cells are added
// ring by ring, the result is a superset of the exact circle — callers that
// need precision should filter candidates with HaversineMeters.
func DiskForRadius(lat, lng, radiusMeters float64, resolution int) ([]Cell, error) {
	origin, err := CellAt(lat, lng, resolution)
	if err != nil {
		return nil, err
	}
	return origin.GridDisk(RingsForRadius(radiusMeters, resolution))
}

// RingsForRadius converts a radius in metres into the number of H3 grid rings
// (k) needed to fully cover it at the given resolution. It rounds up and clamps
// to at least 1, deliberately erring toward over-coverage so no in-range driver
// is ever missed.
func RingsForRadius(radiusMeters float64, resolution int) int {
	if resolution < 0 {
		resolution = 0
	}
	if resolution > 15 {
		resolution = 15
	}
	edge := avgEdgeLengthMeters[resolution]
	if edge <= 0 {
		return 1
	}
	k := int(math.Ceil(radiusMeters / edge))
	if k < 1 {
		return 1
	}
	return k
}

// CellCenter returns the lat/lng of a cell's centre, useful for debugging and
// for drawing coverage on a map.
func CellCenter(c Cell) (lat, lng float64, err error) {
	ll, err := c.LatLng()
	if err != nil {
		return 0, 0, err
	}
	return ll.Lat, ll.Lng, nil
}

// HaversineMeters returns the great-circle distance in metres between two
// lat/lng points. Used to refine H3's hex-grid approximation into an exact
// radius check.
func HaversineMeters(lat1, lng1, lat2, lng2 float64) float64 {
	const earthRadiusM = 6_371_000.0
	const degToRad = math.Pi / 180

	phi1 := lat1 * degToRad
	phi2 := lat2 * degToRad
	dPhi := (lat2 - lat1) * degToRad
	dLambda := (lng2 - lng1) * degToRad

	a := math.Sin(dPhi/2)*math.Sin(dPhi/2) +
		math.Cos(phi1)*math.Cos(phi2)*math.Sin(dLambda/2)*math.Sin(dLambda/2)
	return earthRadiusM * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
