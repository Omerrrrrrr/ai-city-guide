import { useTrips } from '@/src/store/trips';

beforeEach(() => {
  useTrips.setState({ trips: [], activeTripId: null });
});

describe('useTrips', () => {
  it('starts a trip with the given stops and route, marking it active', () => {
    const routeGeometry: [number, number][] = [[58.1, 7.9], [58.11, 7.91]];
    const id = useTrips.getState().startTrip(['posebyen', 'kunstsilo'], {
      routeGeometry,
      distanceMeters: 1200,
      durationSeconds: 900,
    });

    const state = useTrips.getState();
    expect(state.activeTripId).toBe(id);
    expect(state.trips).toHaveLength(1);
    expect(state.trips[0]).toMatchObject({
      id,
      placeIds: ['posebyen', 'kunstsilo'],
      routeGeometry,
      distanceMeters: 1200,
      durationSeconds: 900,
      breadcrumb: [],
      photos: [],
    });
    expect(state.trips[0].endedAt).toBeUndefined();
  });

  it('renames a trip', () => {
    const id = useTrips.getState().startTrip(['posebyen']);
    useTrips.getState().renameTrip(id, 'Sunday walk');

    expect(useTrips.getState().trips.find((t) => t.id === id)?.name).toBe('Sunday walk');
  });

  it('updates a trip\'s stops and route without touching its breadcrumb/photos', () => {
    const id = useTrips.getState().startTrip(['posebyen']);
    useTrips.getState().addBreadcrumb(id, { lat: 58.1, lng: 7.9, timestamp: 1000 });

    const newRoute: [number, number][] = [[58.2, 8.0], [58.21, 8.01]];
    useTrips.getState().updateTripStops(id, ['posebyen', 'kunstsilo'], {
      routeGeometry: newRoute,
      distanceMeters: 2000,
      durationSeconds: 1500,
    });

    const trip = useTrips.getState().trips.find((t) => t.id === id);
    expect(trip?.placeIds).toEqual(['posebyen', 'kunstsilo']);
    expect(trip?.routeGeometry).toEqual(newRoute);
    expect(trip?.distanceMeters).toBe(2000);
    expect(trip?.breadcrumb).toEqual([{ lat: 58.1, lng: 7.9, timestamp: 1000 }]);
  });

  it('appends breadcrumb points to the right trip only', () => {
    const id = useTrips.getState().startTrip(['posebyen']);
    useTrips.getState().addBreadcrumb(id, { lat: 58.1, lng: 7.9, timestamp: 1000 });
    useTrips.getState().addBreadcrumb(id, { lat: 58.11, lng: 7.91, timestamp: 2000 });

    const trip = useTrips.getState().trips.find((t) => t.id === id);
    expect(trip?.breadcrumb).toEqual([
      { lat: 58.1, lng: 7.9, timestamp: 1000 },
      { lat: 58.11, lng: 7.91, timestamp: 2000 },
    ]);
  });

  it('appends photos to a trip', () => {
    const id = useTrips.getState().startTrip(['posebyen']);
    useTrips.getState().addPhoto(id, { uri: 'file:///photo.jpg', timestamp: 5000 });

    const trip = useTrips.getState().trips.find((t) => t.id === id);
    expect(trip?.photos).toEqual([{ uri: 'file:///photo.jpg', timestamp: 5000 }]);
  });

  it('ends a trip, stamping endedAt and clearing activeTripId', () => {
    const id = useTrips.getState().startTrip(['posebyen']);
    useTrips.getState().endTrip(id);

    const state = useTrips.getState();
    expect(state.activeTripId).toBeNull();
    expect(state.trips.find((t) => t.id === id)?.endedAt).toBeDefined();
  });

  it('deletes a trip and clears activeTripId if it was the active one', () => {
    const id = useTrips.getState().startTrip(['posebyen']);
    useTrips.getState().deleteTrip(id);

    const state = useTrips.getState();
    expect(state.trips).toHaveLength(0);
    expect(state.activeTripId).toBeNull();
  });
});
