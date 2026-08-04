export function getDirectionsUrl(place: {
  location?: { lat: number; lng: number };
  verifiedFacts?: { address?: string };
}) {
  if (place.location) {
    return `https://www.google.com/maps/search/?api=1&query=${place.location.lat},${place.location.lng}`;
  }
  if (place.verifiedFacts?.address) {
    return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(place.verifiedFacts.address)}`;
  }
  return null;
}
