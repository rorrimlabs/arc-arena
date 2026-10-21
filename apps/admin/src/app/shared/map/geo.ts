/** A point on the map, in degrees. */
export interface GeoPoint {
  readonly lat: number;
  readonly lng: number;
}

const METRES_PER_DEGREE = 111_320;

/** Rounds to 6 decimals (about 11 cm), as the server stores a geofence centre. */
export function round6(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}

/** The corners of a circle's bounding box (degrees), for fitting the view around it. */
export function circleCorners(center: GeoPoint, radiusM: number): [GeoPoint, GeoPoint] {
  const dLat = radiusM / METRES_PER_DEGREE;
  const cos = Math.max(0.01, Math.cos((center.lat * Math.PI) / 180));
  const dLng = radiusM / (METRES_PER_DEGREE * cos);
  return [
    { lat: center.lat - dLat, lng: center.lng - dLng },
    { lat: center.lat + dLat, lng: center.lng + dLng },
  ];
}
