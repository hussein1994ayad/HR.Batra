import { describe, expect, it } from 'vitest';
import { distanceMeters, extractCoordsFromText } from '@/lib/geo';

describe('extractCoordsFromText', () => {
  it('reads @lat,lng from Google Maps URLs', () => {
    expect(extractCoordsFromText('https://www.google.com/maps/place/X/@33.3152,44.3661,17z')).toEqual({ lat: 33.3152, lng: 44.3661 });
  });
  it('reads query parameters', () => {
    expect(extractCoordsFromText('https://maps.google.com/?q=33.30,44.40')).toEqual({ lat: 33.3, lng: 44.4 });
  });
  it('reads /place/lat+lng', () => {
    expect(extractCoordsFromText('https://www.google.com/maps/place/33.31+44.36')).toEqual({ lat: 33.31, lng: 44.36 });
  });
  it('accepts a bare pair only inside Iraq', () => {
    expect(extractCoordsFromText('33.3152, 44.3661')).toEqual({ lat: 33.3152, lng: 44.3661 });
    expect(extractCoordsFromText('48.8566, 2.3522')).toBeNull();
  });
  it('handles URL-encoded text and junk', () => {
    expect(extractCoordsFromText('https://x.com/?q=33.1%2C44.2')).toEqual({ lat: 33.1, lng: 44.2 });
    expect(extractCoordsFromText('no coordinates here')).toBeNull();
    expect(extractCoordsFromText('')).toBeNull();
  });
});

describe('distanceMeters', () => {
  it('is zero for the same point', () => {
    expect(distanceMeters(33.3, 44.4, 33.3, 44.4)).toBe(0);
  });
  it('matches a known distance within 1%', () => {
    // ~111.2 km per degree of latitude
    const d = distanceMeters(33, 44, 34, 44);
    expect(d).toBeGreaterThan(110_000);
    expect(d).toBeLessThan(112_300);
  });
  it('detects points inside a 150 m radius', () => {
    const d = distanceMeters(33.3152, 44.3661, 33.3162, 44.3661); // ~111 m north
    expect(d).toBeLessThan(150);
  });
});
