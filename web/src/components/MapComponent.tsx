'use client';

import React, { useEffect, useRef, useState } from 'react';

interface MapMarker {
  lat: number;
  lng: number;
  popupText: string;
  isViolation?: boolean;
  color?: string;
}

interface MapPolygon {
  name: string;
  coords: [number, number][];
}

interface MapPolyline {
  coords: [number, number][];
  color?: string;
  weight?: number;
}

interface MapCircle {
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

export default function MapComponent({
  markers = [],
  polygons = [],
  polylines = [],
  circles = [],
  selectedCircleId = null,
  center = [33.3152, 44.3661], // Center of Baghdad
  zoom = 12,
  onMapClick,
  onCircleClick
}: MapComponentProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const [leafletInstance, setLeafletInstance] = useState<any>(null);

  // Dynamically load Leaflet library only on the client side
  useEffect(() => {
    if (typeof window === 'undefined') return;

    let active = true;

    const loadLeaflet = async () => {
      try {
        const L = (await import('leaflet')).default;
        if (active) {
          setLeafletInstance(L);
        }
      } catch (err) {
        console.error('Failed to load Leaflet:', err);
      }
    };

    loadLeaflet();

    return () => {
      active = false;
    };
  }, []);

  // Initialize and update the map when Leaflet is loaded and props change
  useEffect(() => {
    if (!leafletInstance || !containerRef.current) return;

    const L = leafletInstance;

    // Clean existing map instance if any
    if (mapRef.current) {
      mapRef.current.remove();
      mapRef.current = null;
    }

    // Initialize map container
    const mapInstance = L.map(containerRef.current, {
      center: center,
      zoom: zoom,
      zoomControl: true,
      attributionControl: false
    });

    // Premium Dark Mode Map Tile Skin (CartoDB Dark Matter)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png', {
      maxZoom: 22,
      maxNativeZoom: 19,
      attribution: '&copy; <a href="https://carto.com/attributions">CARTO</a>'
    }).addTo(mapInstance);

    // Add Polygons (Geofence Zones)
    polygons.forEach((poly) => {
      if (!poly.coords || poly.coords.length < 3) return;
      
      const leafletPoly = L.polygon(poly.coords, {
        color: '#0D9488', // Teal color for active geofences
        fillColor: '#0D9488',
        fillOpacity: 0.15,
        weight: 2
      }).addTo(mapInstance);

      leafletPoly.bindPopup(`<strong style="font-family: Cairo; color: #111;">السياج الجغرافي: ${poly.name}</strong>`);
    });

    // Add Circles (Branch Range Circles)
    circles.forEach((c) => {
      if (!c.lat || !c.lng) return;
      
      const isSelected = selectedCircleId && c.id === selectedCircleId;
      const leafletCircle = L.circle([c.lat, c.lng], {
        radius: c.radius,
        color: isSelected ? '#00FF66' : '#00F0FF', // glowing neon green for selected, glowing cyan for others
        fillColor: isSelected ? '#00FF66' : '#00F0FF',
        fillOpacity: isSelected ? 0.22 : 0.12,
        weight: isSelected ? 4 : 2,
        dashArray: isSelected ? '5, 5' : undefined
      }).addTo(mapInstance);

      leafletCircle.bindPopup(`<div style="font-family: Cairo; direction: rtl; text-align: right; color: #111; padding: 2px;"><strong style="color: #0D9488;">🏢 فرع: ${c.name}</strong><br/>نطاق البصمة الجغرافية: ${c.radius} متر</div>`);

      leafletCircle.on('click', () => {
        if (onCircleClick) {
          onCircleClick(c.id);
        }
      });
    });

    // Add Markers
    markers.forEach((marker) => {
      const markerColor = marker.color || (marker.isViolation ? '#EF4444' : '#0D9488');
      
      // Custom interactive glowing marker icon
      const glowHtml = `
        <div style="position: relative; width: 14px; height: 14px;">
          <div style="position: absolute; width: 14px; height: 14px; border-radius: 50%; background-color: ${markerColor}; border: 2.5px solid #fff; box-shadow: 0 0 10px ${markerColor};"></div>
          <div style="position: absolute; width: 30px; height: 30px; border-radius: 50%; background-color: ${markerColor}; opacity: 0.25; top: -8px; left: -8px; animation: pulse 2s infinite;"></div>
        </div>
      `;

      const customIcon = L.divIcon({
        html: glowHtml,
        className: 'custom-map-marker',
        iconSize: [14, 14],
        iconAnchor: [7, 7]
      });

      const m = L.marker([marker.lat, marker.lng], { icon: customIcon }).addTo(mapInstance);
      m.bindPopup(`<div style="font-family: Cairo; direction: rtl; text-align: right; color: #111; padding: 2px;">${marker.popupText}</div>`);
    });

    // Add Polylines (Trails / History paths)
    polylines.forEach((line) => {
      if (!line.coords || line.coords.length < 2) return;
      L.polyline(line.coords, {
        color: line.color || '#3B82F6',
        weight: line.weight || 4,
        opacity: 0.85,
        dashArray: '8, 8'
      }).addTo(mapInstance);
    });

    if (onMapClick) {
      mapInstance.on('click', (e: any) => {
        onMapClick(e.latlng.lat, e.latlng.lng);
      });
    }

    // Solve Leaflet disappearing tiles on tab switch or layout computing delay
    mapInstance.invalidateSize();
    const timer = setTimeout(() => {
      mapInstance.invalidateSize();
    }, 250);

    // Watch for window resize events
    const handleResize = () => {
      mapInstance.invalidateSize();
    };
    window.addEventListener('resize', handleResize);

    mapRef.current = mapInstance;

    return () => {
      window.removeEventListener('resize', handleResize);
      clearTimeout(timer);
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
    };
  }, [leafletInstance, markers, polygons, polylines, circles, selectedCircleId, center, zoom]);

  return (
    <div className="relative w-full h-full min-h-[450px] rounded-3xl overflow-hidden border border-slate-800/80 shadow-2xl bg-[#090D16]">
      {/* Pulsing glow animation styles directly injected */}
      <style dangerouslySetInnerHTML={{__html: `
        @keyframes pulse {
          0% { transform: scale(0.6); opacity: 0.6; }
          100% { transform: scale(1.3); opacity: 0; }
        }
        .leaflet-popup-content-wrapper {
          border-radius: 12px !important;
          padding: 6px !important;
          box-shadow: 0 4px 16px rgba(0,0,0,0.15) !important;
        }
      `}} />
      <div ref={containerRef} className="w-full h-full absolute inset-0" />
    </div>
  );
}
