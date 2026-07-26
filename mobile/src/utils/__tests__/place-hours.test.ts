import { getPlaceOpenStatus } from '@/src/utils/place-hours';

import { fakeT, makePlace } from '@/src/test-utils/place-fixtures';

// All test dates are winter (Oslo = UTC+1, no DST) to avoid daylight-saving
// ambiguity. 2026-01-05 is a Monday, 2026-01-04 is a Sunday.
const MONDAY_14_00 = new Date('2026-01-05T13:00:00Z'); // 14:00 Oslo time
const MONDAY_08_00 = new Date('2026-01-05T07:00:00Z'); // 08:00 Oslo time
const MONDAY_23_00 = new Date('2026-01-05T22:00:00Z'); // 23:00 Oslo time

describe('getPlaceOpenStatus — temporarily closed', () => {
  it('reports temporarily-closed regardless of hours data', () => {
    const place = makePlace({
      category: 'restaurant',
      visitInfo: { hoursVerified: true, temporarilyClosed: true },
    });

    const status = getPlaceOpenStatus(place, fakeT, MONDAY_14_00);

    expect(status.state).toBe('temporarily-closed');
  });
});

describe('getPlaceOpenStatus — unverified profile-based hours', () => {
  it('treats outdoor categories as always open', () => {
    const beach = makePlace({ category: 'beach' });

    const status = getPlaceOpenStatus(beach, fakeT, MONDAY_23_00);

    expect(status.state).toBe('all-day');
    expect(status.verified).toBe(false);
  });

  it('reports a restaurant open during its scheduled window', () => {
    const restaurant = makePlace({ category: 'restaurant' });

    const status = getPlaceOpenStatus(restaurant, fakeT, MONDAY_14_00);

    expect(status.state).toBe('open');
    expect(status.verified).toBe(false);
  });

  it('reports a restaurant closed before opening hours, with a next-opening hint', () => {
    const restaurant = makePlace({ category: 'restaurant' });

    const status = getPlaceOpenStatus(restaurant, fakeT, MONDAY_08_00);

    expect(status.state).toBe('closed');
    expect(status.detail).toContain('placeHours.detail.likelyClosedWithNext');
  });

  it('reports a restaurant closed after hours on the same day', () => {
    const restaurant = makePlace({ category: 'restaurant' });

    const status = getPlaceOpenStatus(restaurant, fakeT, MONDAY_23_00);

    expect(status.state).toBe('closed');
  });

  it('reports a museum closed on Monday (no scheduled hours that day)', () => {
    const museum = makePlace({ category: 'museum' });

    const status = getPlaceOpenStatus(museum, fakeT, MONDAY_14_00);

    expect(status.state).toBe('closed');
  });

  it('treats a landmark tagged outdoor as always open, unlike a plain landmark', () => {
    const outdoorLandmark = makePlace({ category: 'landmark', tags: ['outdoor'] });
    const indoorLandmark = makePlace({ category: 'landmark', tags: [] });

    expect(getPlaceOpenStatus(outdoorLandmark, fakeT, MONDAY_23_00).state).toBe('all-day');
    expect(getPlaceOpenStatus(indoorLandmark, fakeT, MONDAY_23_00).state).toBe('closed');
  });
});

describe('getPlaceOpenStatus — verified hours from a real source', () => {
  it('reports all-day open when verified hours say always-open', () => {
    const place = makePlace({
      category: 'walking-area',
      visitInfo: {
        hoursVerified: true,
        temporarilyClosed: false,
        openingHours: { timezone: 'Europe/Oslo', mode: 'always-open', days: {} as any },
      },
    });

    const status = getPlaceOpenStatus(place, fakeT, MONDAY_14_00);

    expect(status.state).toBe('all-day');
    expect(status.verified).toBe(true);
  });

  it('reports open/closed from verified per-day scheduled ranges, overriding the category profile guess', () => {
    // A "restaurant" that verified hours say is actually closed at 14:00 —
    // verified data should win over the RESTAURANT_PROFILE guess (which
    // would otherwise say open at this hour).
    const place = makePlace({
      category: 'restaurant',
      visitInfo: {
        hoursVerified: true,
        temporarilyClosed: false,
        openingHours: {
          timezone: 'Europe/Oslo',
          mode: 'scheduled',
          days: { '1': [{ start: '17:00', end: '23:00' }] } as any,
        },
      },
    });

    const closedStatus = getPlaceOpenStatus(place, fakeT, MONDAY_14_00);
    expect(closedStatus.state).toBe('closed');
    expect(closedStatus.verified).toBe(true);

    const openStatus = getPlaceOpenStatus(place, fakeT, new Date('2026-01-05T16:30:00Z')); // 17:30 Oslo time
    expect(openStatus.state).toBe('open');
    expect(openStatus.verified).toBe(true);
  });
});
