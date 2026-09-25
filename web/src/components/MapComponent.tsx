'use client';

import React, { useEffect, useRef, useState } from 'react';
import type * as Leaflet from 'leaflet';
import 'leaflet/dist/leaflet.css';

export interface MapMarker {
  lat: number;
  lng: number;
  /** Trusted HTML for the popup; escape any user-provided text before passing it. */
  popupText: string;
  isViolation?: boolean;
  color?: string;
}

export interface MapPolygon {
  name: string;
  coords: [number, number][];
}

export interface MapPolyline {
  coords: [number, number][];
  color?: string;
  weight?: number;
}

export interface MapCircle {
  id: string;
  name: string;
  lat: number;
  lng: number;
  radius: number;
}

interface MapComponentProps {
  markers?: MapMarker[];
  polygons?: MapPolygon[];
  polylines?: MapPolyline[];
  circles?: MapCircle[];
  selectedCircleId?: string | null;
  center?: [number, number];
  zoom?: number;
  onMapClick?: (lat: number, lng: number) => void;
  onCircleClick?: (id: string) => void;
}

const EMPTY: never[] = [];

function escape(text: string) {
  return text.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string);
}

/**
 * Leaflet map with a dark basemap. The map instance is created once; data
 * layers are redrawn when their props change and the view is animated when
 * `center`/`zoom` change, so re-renders of the parent page stay cheap.
 */
export default function MapComponent({
  markers = EMPTY,
  polygons = EMPTY,
  polylines = EMPTY,
  circles = EMPTY,
  selectedCircleId = null,
  center = [33.3152, 44.3661],
  zoom = 12,
  onMapClick,
  onCircleClick,
}: MapComponentProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Leaflet.Map | null>(null);
  const layerRef = useRef<Leaflet.LayerGroup | null>(null);
  const [L, setL] = useState<typeof Leaflet | null>(null);

  // Keep the latest callbacks without re-binding map listeners.
  const handlers = useRef({ onMapClick, onCircleClick });
  useEffect(() => {
    handlers.current = { onMapClick, onCircleClick };
  });

  // Load Leaflet on the client only.
  useEffect(() => {
    let active = true;
    import('leaflet')
      .then((mod) => {
        if (active) setL(mod.default ?? mod);
      })
      .catch((err) => console.error('Failed to load Leaflet:', err));
    return () => {
      active = false;
    };
  }, []);

  // Create the map once Leaflet is available.
  useEffect(() => {
    if (!L || !containerRef.current || mapRef.current) return;

    const map = L.map(containerRef.current, {
      center,
      zoom,
      zoomControl: true,
      attributionControl: false,
    });

    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png', {
      maxZoom: 22,
      maxNativeZoom: 19,
    }).addTo(map);

    layerRef.current = L.layerGroup().addTo(map);
    map.on('click', (e: Leaflet.LeafletMouseEvent) => handlers.current.onMapClick?.(e.latlng.lat, e.latlng.lng));

    // Leaflet measures its container on init; re-measure once layout settles.
    const timer = setTimeout(() => map.invalidateSize(), 250);
    const observer = new ResizeObserver(() => map.invalidateSize());
    observer.observe(containerRef.current);

    mapRef.current = map;
    return () => {
      clearTimeout(timer);
      observer.disconnect();
      map.remove();
      mapRef.current = null;
      layerRef.current = null;
    };
    // center/zoom are applied by the effect below after creation.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [L]);

  // Move the view when the requested center/zoom changes.
  const [lat, lng] = center;
  useEffect(() => {
    mapRef.current?.flyTo([lat, lng], zoom, { duration: 0.6 });
  }, [lat, lng, zoom]);

  // Redraw data layers.
  useEffect(() => {
    const layer = layerRef.current;
    if (!L || !layer) return;
    layer.clearLayers();

    polygons.forEach((poly) => {
      if (!poly.coords || poly.coords.length < 3) return;
      L.polygon(poly.coords, { color: '#818CF8', fillColor: '#818CF8', fillOpacity: 0.12, weight: 2 })
        .bindPopup(`<strong>السياج الجغرافي: ${escape(poly.name)}</strong>`)
        .addTo(layer);
    });

    circles.forEach((c) => {
      if (!c.lat || !c.lng) return;
      const selected = !!selectedCircleId && c.id === selectedCircleId;
      L.circle([c.lat, c.lng], {
        radius: c.radius,
        color: selected ? '#34D399' : '#818CF8',
        fillColor: selected ? '#34D399' : '#818CF8',
        fillOpacity: selected ? 0.22 : 0.12,
        weight: selected ? 3 : 2,
        dashArray: selected ? '6, 6' : undefined,
      })
        .bindPopup(`<strong>فرع: ${escape(c.name)}</strong><br/>نطاق البصمة: ${Math.round(c.radius)} متر`)
        .on('click', () => handlers.current.onCircleClick?.(c.id))
        .addTo(layer);
    });

    markers.forEach((marker) => {
      const color = marker.color || (marker.isViolation ? '#F43F5E' : '#34D399');
      const icon = L.divIcon({
        html: `<span class="map-dot" style="--dot:${color}"></span>`,
        className: '',
        iconSize: [14, 14],
        iconAnchor: [7, 7],
      });
      L.marker([marker.lat, marker.lng], { icon }).bindPopup(marker.popupText).addTo(layer);
    });

    polylines.forEach((line) => {
      if (!line.coords || line.coords.length < 2) return;
      L.polyline(line.coords, {
        color: line.color || '#60A5FA',
        weight: line.weight || 4,
        opacity: 0.85,
        dashArray: '8, 8',
      }).addTo(layer);
    });
  }, [L, markers, polygons, polylines, circles, selectedCircleId]);

  return (
    <div className="relative w-full h-full min-h-[420px] rounded-2xl overflow-hidden border border-slate-800/80 bg-slate-950">
      {!L && <div className="absolute inset-0 skeleton rounded-none" />}
      <div ref={containerRef} className="absolute inset-0" />
    </div>
  );
}
