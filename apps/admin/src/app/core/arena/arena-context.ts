import { Service, computed, signal } from '@angular/core';

export interface Arena {
  readonly id: string;
  readonly name: string;
  readonly area: string;
}

/** The arena the owner is looking at; every screen's data is scoped to it. */
@Service()
export class ArenaContext {
  // Sample arenas from the design until the backend exists.
  readonly arenas = signal<readonly Arena[]>([
    { id: 'a1', name: '404 Arena', area: 'Koramangala' },
    { id: 'a2', name: '404 Arena', area: 'Indiranagar' },
  ]);

  private readonly currentId = signal('a1');

  readonly current = computed(
    () => this.arenas().find((arena) => arena.id === this.currentId()) ?? this.arenas()[0],
  );

  select(id: string): void {
    this.currentId.set(id);
  }
}
