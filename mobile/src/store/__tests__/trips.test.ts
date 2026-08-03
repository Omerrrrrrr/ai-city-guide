import { useTrips } from '@/src/store/trips';

beforeEach(() => {
  useTrips.setState({ trips: [], activeTripId: null });
});

describe('useTrips', () => {
  it('starts a trip with the given stops and route, marking it active', () => {
    const route: [number, number][] = [[58.1, 7.9], [58.11, 7.91]];
    const id = useTrips.getState().startTrip(['posebyen', 'kunstsilo'], route);

    const state = useTrips.getState();
    expect(state.activeTripId).toBe(id);
    expect(state.trips).toHaveLength(1);
    expect(state.trips[0]).toMatchObject({
      id,
      placeIds: ['posebyen', 'kunstsilo'],
      routeGeometry: route,
      breadcrumb: [],
      photos: [],
    });
    expect(state.trips[0].endedAt).toBeUndefined();
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
