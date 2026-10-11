import { Service, computed, inject, signal } from '@angular/core';
import { CanMatchFn, Router } from '@angular/router';

export interface OwnerAccount {
  readonly name: string;
  readonly email: string;
}

/** The signed-in owner. Uses the design's sample account until real auth exists. */
@Service()
export class Session {
  private readonly router = inject(Router);

  readonly user = signal<OwnerAccount | null>({ name: 'Arjun Mehra', email: 'arjun@404arena.in' });
  readonly signedIn = computed(() => this.user() !== null);
  readonly initials = computed(() =>
    (this.user()?.name ?? '')
      .split(' ')
      .map((word) => word[0])
      .slice(0, 2)
      .join('')
      .toUpperCase(),
  );

  signIn(): void {
    this.user.set({ name: 'Arjun Mehra', email: 'arjun@404arena.in' });
    void this.router.navigate(['/overview']);
  }

  signOut(): void {
    this.user.set(null);
    void this.router.navigate(['/sign-in']);
  }
}

/** Keeps the app shell behind sign-in. */
export const signedInGuard: CanMatchFn = () =>
  inject(Session).signedIn() || inject(Router).createUrlTree(['/sign-in']);
