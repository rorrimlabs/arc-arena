import { isPlatformBrowser } from '@angular/common';
import {
  Component,
  DestroyRef,
  ElementRef,
  InjectionToken,
  PLATFORM_ID,
  afterNextRender,
  effect,
  inject,
  input,
  output,
  signal,
  untracked,
  viewChild,
} from '@angular/core';
import type * as Leaflet from 'leaflet';
import { GeoPoint, circleCorners, round6 } from './geo';

export type { GeoPoint } from './geo';

/** A pin: a clock-in is drawn solid, a clock-out hollow (`kind`), with a tooltip label. */
export interface GeoMarker extends GeoPoint {
  readonly kind: 'in' | 'out';
  readonly label: string;
}

/** The part of Leaflet this component uses (tests provide a fake through LEAFLET). */
export type LeafletApi = Pick<
  typeof Leaflet,
  | 'map'
  | 'tileLayer'
  | 'layerGroup'
  | 'circle'
  | 'circleMarker'
  | 'marker'
  | 'divIcon'
  | 'latLngBounds'
>;

/**
 * Loads Leaflet on first use (a lazy chunk: only screens with a map download it). Tests
 * provide a fake.
 */
export const LEAFLET = new InjectionToken<() => Promise<LeafletApi>>('LEAFLET', {
  providedIn: 'root',
  factory: () => async () => {
    const m = (await import('leaflet')) as unknown as { default?: LeafletApi } & LeafletApi;
    return m.default ?? m;
  },
});

const TILES = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
/** India, when there is nothing to show yet. */
const START: GeoPoint = { lat: 20.5937, lng: 78.9629 };
/**
 * An OpenStreetMap map (Leaflet): an optional centre with a radius circle (the arena's
 * geofence), punch pins, and — when `editable` — a click or a drag of the centre pin moves the
 * centre (`centerChange`, rounded to 6 decimals). Created after the first render in the browser
 * only and removed with the component. The map is a visual aid: every value it shows or sets is
 * also given as text or a field next to it.
 */
@Component({
  selector: 'app-geo-map',
  host: {
    class: 'relative block overflow-hidden rounded-card border border-border bg-surface',
    '[style.height]': 'height()',
  },
  template: `
    <div #box class="absolute inset-0" role="region" [attr.aria-label]="label()"></div>
    @if (failed()) {
      <p
        role="alert"
        class="absolute inset-0 grid place-items-center p-4 text-center text-[13px] text-muted"
      >
        The map couldn't load. Check the connection; the values beside it still work.
      </p>
    }
  `,
})
export class GeoMap {
  /** The geofence centre (and the draggable pin when editable). */
  readonly center = input<GeoPoint | null>(null);
  /** Metres around `center`, drawn as a circle. */
  readonly radius = input<number | null>(null);
  readonly markers = input<readonly GeoMarker[]>([]);
  readonly editable = input(false);
  /** What the map shows, for screen readers. */
  readonly label = input('Map');
  readonly height = input('320px');
  readonly centerChange = output<GeoPoint>();

  private readonly box = viewChild.required<ElementRef<HTMLElement>>('box');
  private readonly load = inject(LEAFLET);
  protected readonly failed = signal(false);
  private readonly ready = signal(false);

  private L: LeafletApi | null = null;
  private map: Leaflet.Map | null = null;
  private layers: Leaflet.LayerGroup | null = null;
  private observer: ResizeObserver | null = null;
  private destroyed = false;
  /** The last centre this map emitted: echoing it back does not move the view. */
  private emitted: GeoPoint | null = null;
  /** What the view was last fitted to; the view moves only when that changes. */
  private fittedTo = '';

  constructor() {
    const browser = isPlatformBrowser(inject(PLATFORM_ID));
    afterNextRender(() => {
      if (browser) void this.create();
    });
    effect(() => {
      const state = {
        center: this.center(),
        radius: this.radius(),
        markers: this.markers(),
        editable: this.editable(),
      };
      if (this.ready()) untracked(() => this.draw(state));
    });
    inject(DestroyRef).onDestroy(() => {
      this.destroyed = true;
      this.observer?.disconnect();
      this.map?.remove();
      this.map = null;
    });
  }

  private async create(): Promise<void> {
    try {
      const L = await this.load();
      if (this.destroyed) return;
      const map = L.map(this.box().nativeElement, { zoomControl: true, attributionControl: true });
      L.tileLayer(TILES, { attribution: ATTRIBUTION, maxZoom: 19 }).addTo(map);
      this.layers = L.layerGroup().addTo(map);
      map.on('click', (e: Leaflet.LeafletMouseEvent) => {
        if (this.editable()) this.emit(e.latlng);
      });
      if (typeof ResizeObserver !== 'undefined') {
        this.observer = new ResizeObserver(() => this.map?.invalidateSize());
        this.observer.observe(this.box().nativeElement);
      }
      this.L = L;
      this.map = map;
      this.ready.set(true);
    } catch {
      this.failed.set(true);
    }
  }

  private emit(at: GeoPoint): void {
    const point = { lat: round6(at.lat), lng: round6(at.lng) };
    this.emitted = point;
    this.centerChange.emit(point);
  }

  private draw(s: {
    center: GeoPoint | null;
    radius: number | null;
    markers: readonly GeoMarker[];
    editable: boolean;
  }): void {
    const { L, map, layers } = this;
    if (!L || !map || !layers) return;
    layers.clearLayers();
    const { center, radius, markers, editable } = s;
    if (center && radius && radius > 0) {
      L.circle([center.lat, center.lng], {
        radius,
        className: 'geo-fence',
        weight: 2,
        fillOpacity: 0.12,
        interactive: false,
      }).addTo(layers);
    }
    if (center) {
      const pin = L.marker([center.lat, center.lng], {
        draggable: editable,
        keyboard: false,
        title: 'Arena centre',
        alt: 'Arena centre',
        icon: L.divIcon({ className: 'geo-pin', iconSize: [18, 18], iconAnchor: [9, 9] }),
      });
      if (editable) {
        pin.on('dragend', () => this.emit(pin.getLatLng()));
      }
      pin.addTo(layers);
    }
    for (const m of markers) {
      L.circleMarker([m.lat, m.lng], {
        radius: 7,
        weight: 2,
        className: m.kind === 'in' ? 'geo-in' : 'geo-out',
        fillOpacity: m.kind === 'in' ? 0.9 : 0.15,
      })
        // Leaflet renders a string tooltip as HTML; labels carry user-entered names.
        .bindTooltip(Object.assign(document.createElement('span'), { textContent: m.label }))
        .addTo(layers);
    }
    this.fit(center, radius, markers);
  }

  /** Moves the view to what is shown, unless that only echoes the user's own pick. */
  private fit(center: GeoPoint | null, radius: number | null, markers: readonly GeoMarker[]): void {
    const { L, map } = this;
    if (!L || !map) return;
    const echo =
      !!center &&
      !!this.emitted &&
      center.lat === this.emitted.lat &&
      center.lng === this.emitted.lng;
    const key = JSON.stringify([echo ? 'echo' : center, radius, markers]);
    if (echo || key === this.fittedTo) {
      this.fittedTo = echo ? this.fittedTo : key;
      return;
    }
    this.fittedTo = key;
    const points: GeoPoint[] = markers.map((m) => ({ lat: m.lat, lng: m.lng }));
    if (center) {
      points.push(...(radius && radius > 0 ? circleCorners(center, radius) : [center]));
    }
    if (!points.length) {
      map.setView([START.lat, START.lng], 4);
    } else if (points.length === 1) {
      map.setView([points[0].lat, points[0].lng], 17);
    } else {
      map.fitBounds(L.latLngBounds(points.map((p) => [p.lat, p.lng] as [number, number])), {
        padding: [24, 24],
        maxZoom: 18,
      });
    }
  }
}
