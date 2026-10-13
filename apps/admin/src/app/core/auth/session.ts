import { Service, computed, inject, signal } from '@angular/core';
import { CanMatchFn, Router } from '@angular/router';
import { Account, AuthApi } from './auth-api';

export type { Account as OwnerAccount } from './auth-api';

/** The signed-in owner, restored from the stored session on start. */
@Service()
export class Session {
  private readonly api = inject(AuthApi);
  private readonly router = inject(Router);

  readonly user = signal<Account | null>(null);
  readonly signedIn = computed(() => this.user() !== null);
  readonly initials = computed(() =>
    (this.user()?.name ?? '')
      .split(/[\s@.]+/)
      .filter(Boolean)
      .map((word) => word[0])
      .slice(0, 2)
      .join('')
      .toUpperCase(),
  );

  /** Resolves once the stored session (if any) has been read. Guards wait for it. */
  readonly ready: Promise<void>;

  constructor() {
    this.ready = this.api.current().then((account) => this.user.set(account));
    this.api.onChange((account) => this.user.set(account));
  }

  async signIn(email: string, password: string): Promise<void> {
    await this.api.signIn(email, password);
    this.user.set(await this.api.current());
    await this.router.navigateByUrl('/');
  }

  /** Re-reads the stored session (after sign-up confirmation signs the person in). */
  async refresh(): Promise<void> {
    this.user.set(await this.api.current());
  }

  async signOut(): Promise<void> {
    await this.api.signOut();
    this.user.set(null);
    await this.router.navigate(['/sign-in']);
  }
}

/** Keeps the app behind sign-in. */
export const signedInGuard: CanMatchFn = async () => {
  const session = inject(Session);
  const router = inject(Router);
  await session.ready;
  return session.signedIn() || router.createUrlTree(['/sign-in']);
};

/** Sign-in and register are only for signed-out visitors. */
export const signedOutGuard: CanMatchFn = async () => {
  const session = inject(Session);
  const router = inject(Router);
  await session.ready;
  return !session.signedIn() || router.createUrlTree(['/']);
};
