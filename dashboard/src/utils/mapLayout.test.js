import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

describe('Leaflet Map Layout & Architecture Validation', () => {
  const appPath = path.resolve(__dirname, '../App.jsx');
  const cssPath = path.resolve(__dirname, '../index.css');

  const appContent = fs.readFileSync(appPath, 'utf-8');
  const cssContent = fs.readFileSync(cssPath, 'utf-8');

  it('uses dedicated .leaflet-map-host element in App.jsx', () => {
    expect(appContent).toContain('className="leaflet-map-host"');
    expect(appContent).not.toContain('<div ref={mapRef} style={{ width: \'100%\', height: \'100%\' }} />');
  });

  it('does not use dangerous delete container._leaflet_id workaround', () => {
    expect(appContent).not.toContain('delete container._leaflet_id');
  });

  it('calls invalidateSize with { pan: false } to prevent camera jumping', () => {
    expect(appContent).toContain('invalidateSize({ pan: false })');
  });

  it('ensures index.css does NOT contain broad .map-wrapper > div rule', () => {
    expect(cssContent).not.toContain('.map-wrapper > div');
  });

  it('defines .leaflet-map-host with absolute inset positioning', () => {
    expect(cssContent).toContain('.leaflet-map-host {');
    expect(cssContent).toContain('position: absolute;');
    expect(cssContent).toContain('inset: 0;');
  });

  it('defines robust grid columns preventing sidebar blowout', () => {
    expect(cssContent).toContain('grid-template-columns: minmax(0, 1fr) minmax(0, 520px);');
    expect(cssContent).toContain('grid-template-columns: minmax(0, 1fr) 0;');
  });

  it('safeguards Leaflet tiles against global image max-width clipping', () => {
    expect(cssContent).toContain('.leaflet-container img.leaflet-tile');
    expect(cssContent).toContain('max-width: none !important;');
  });

  it('properly layers overlays with z-index and positions layer controls at top-right', () => {
    expect(cssContent).toContain('.map-layer-controls,');
    expect(cssContent).toContain('.map-filter-overlay,');
    expect(cssContent).toContain('.map-legend,');
    expect(cssContent).toContain('.sidebar-expand-btn {');
    expect(cssContent).toContain('position: absolute;');
    expect(cssContent).toContain('z-index: 1000;');
  });
});
