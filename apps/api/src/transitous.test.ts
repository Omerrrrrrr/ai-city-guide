import assert from 'node:assert/strict';
import test from 'node:test';

import { decodeGooglePolyline } from './transitous';

// Google's own documented example (precision 5, the encoding's original
// default) -- verifies the decode algorithm itself is correct, independent
// of the precision-6 MOTIS actually uses (this module's default), since
// `decodeGooglePolyline` takes precision as a parameter for exactly this
// reason: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
test('decodeGooglePolyline matches Google\'s own documented example at precision 5', () => {
  const points = decodeGooglePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', 5);
  assert.equal(points.length, 3);
  assert.ok(Math.abs(points[0][0] - 38.5) < 1e-5);
  assert.ok(Math.abs(points[0][1] - -120.2) < 1e-5);
  assert.ok(Math.abs(points[1][0] - 40.7) < 1e-5);
  assert.ok(Math.abs(points[1][1] - -120.95) < 1e-5);
  assert.ok(Math.abs(points[2][0] - 43.252) < 1e-5);
  assert.ok(Math.abs(points[2][1] - -126.453) < 1e-5);
});

test('decodeGooglePolyline returns an empty array for an empty string', () => {
  assert.deepEqual(decodeGooglePolyline(''), []);
});
