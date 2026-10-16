import { LeafletApi } from '../shared/map/geo-map';

/** One layer the fake map drew. */
export interface FakeLayer {
  readonly type: 'circle' | 'circleMarker' | 'marker';
  readonly at: [number, number];
  readonly options: Record<string, unknown>;
  tooltip?: string;
  /** Marker handlers (e.g. dragend), to simulate a drag. */
  readonly handlers: Record<string, () => void>;
  latLng: { lat: number; lng: number };
}

/** One map the fake created. */
export interface FakeMap {
  readonly el: HTMLElement;
  readonly layers: FakeLayer[];
  /** The map's click handler, to simulate a click at a point. */
  click(lat: number, lng: number): void;
  removed: boolean;
  /** Last setView / fitBounds call. */
  view: unknown;
}

/**
 * A stand-in for Leaflet in tests (jsdom has no layout): records each map and what was drawn on
 * it. Provide `{ provide: LEAFLET, useValue: () => Promise.resolve(fake.api) }`.
 */
export function fakeLeaflet() {
  const maps: FakeMap[] = [];

  function layer(type: FakeLayer['type'], at: [number, number], options: Record<string, unknown>) {
    const l: FakeLayer = {
      type,
      at,
      options,
      handlers: {},
      latLng: { lat: at[0], lng: at[1] },
    };
    const api = {
      addTo(group: { add: (x: FakeLayer) => void }) {
        group.add(l);
        return api;
      },
      bindTooltip(text: string) {
        l.tooltip = text;
        return api;
      },
      on(event: string, cb: () => void) {
        l.handlers[event] = cb;
        return api;
      },
      getLatLng: () => l.latLng,
    };
    return api;
  }

  const api = {
    map(el: HTMLElement) {
      let onClick: (e: { latlng: { lat: number; lng: number } }) => void = () => undefined;
      const m: FakeMap = {
        el,
        layers: [],
        click: (lat, lng) => onClick({ latlng: { lat, lng } }),
        removed: false,
        view: null,
      };
      maps.push(m);
      return {
        on(event: string, cb: typeof onClick) {
          if (event === 'click') onClick = cb;
        },
        setView(at: unknown, zoom: number) {
          m.view = { at, zoom };
        },
        fitBounds(bounds: unknown) {
          m.view = { bounds };
        },
        invalidateSize() {},
        remove() {
          m.removed = true;
        },
        fake: m,
      };
    },
    tileLayer: () => ({ addTo: () => undefined }),
    layerGroup: () => {
      let target: FakeMap | null = null;
      const group = {
        addTo(map: { fake: FakeMap }) {
          target = map.fake;
          return group;
        },
        add: (x: FakeLayer) => target?.layers.push(x),
        clearLayers: () => {
          if (target) target.layers.length = 0;
        },
      };
      return group;
    },
    circle: (at: [number, number], o: Record<string, unknown>) => layer('circle', at, o),
    circleMarker: (at: [number, number], o: Record<string, unknown>) =>
      layer('circleMarker', at, o),
    marker: (at: [number, number], o: Record<string, unknown>) => layer('marker', at, o),
    divIcon: (o: unknown) => o,
    latLngBounds: (points: unknown) => points,
  };

  return { api: api as unknown as LeafletApi, maps };
}

export type FakeLeaflet = ReturnType<typeof fakeLeaflet>;
