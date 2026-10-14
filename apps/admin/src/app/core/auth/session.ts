import { Service, computed, inject, signal } from '@angular/core';
import { CanMatchFn, Router } from '@angular/router';
import { Account, AuthApi } from './auth-api';
import { LoginScope } from './login-scope';

export type { Account as OwnerAccount } from './auth-api';

/** The signed-in owner, restored from the stored session on start. */
@Service()
export class Session {
  private readonly api = inject(AuthApi);
  private readonly router = inject(Router);
  private readonly scope = inject(LoginScope);

  private readonly account = signal<Account | null>(null);
  readonly user = this.account.asReadonly();
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
  /** The server's half of a sign-out still in flight (never rejects). */
  private ending: Promise<void> | null = null;

  constructor() {
    this.ready = this.api.current().then((account) => this.setUser(account));
    // While a sign-out is ending, the client may still refresh the old session first: that must
    // not sign the previous login back in here.
    this.api.onChange((account) => {
      if (!this.ending) this.setUser(account);
    });
  }

  /** Signs in, then opens `next` (where the visitor was going; see safeNext) or the dashboard. */
  async signIn(email: string, password: string, next?: string | null): Promise<void> {
    // The previous login's session ends on the server before the next one starts.
    await this.ending;
    await this.api.signIn(email, password);
    this.setUser(await this.api.current());
    await this.router.navigateByUrl(safeNext(next));
  }

  /** Re-reads the stored session (after sign-up confirmation signs the person in). */
  async refresh(): Promise<void> {
    this.setUser(await this.api.current());
  }

  /**
   * The login's data leaves memory and the screen at once; then the server ends this browser's
   * session (AuthApi.signOut), which can take a while when offline. The local sign-out stands
   * even if the server cannot be told.
   */
  async signOut(): Promise<void> {
    this.setUser(null);
    const ending: Promise<void> = this.api
      .signOut()
      .catch(() => undefined)
      .finally(() => {
        if (this.ending === ending) this.ending = null;
      });
    this.ending = ending;
    await this.router.navigate(['/sign-in']);
    await ending;
  }

  /** A different login (or none) clears everything the previous one loaded, before it shows. */
  private setUser(account: Account | null): void {
    const before = this.account()?.id ?? null;
    if (before !== null && before !== (account?.id ?? null)) this.scope.end();
    this.account.set(account);
  }
}

/**
 * Where to go after signing in: an address inside this app (a path starting with one `/`) that
 * is not itself an auth page, else the dashboard. Anything else is ignored, so a crafted link
 * cannot send someone off the site.
 */
export function safeNext(next: string | null | undefined): string {
  if (!next || !next.startsWith('/') || next.startsWith('//') || next.includes('\\')) return '/';
  return /^\/(sign-in|register|accept-invite|reset-password)(?:[/?#]|$)/.test(next) ? '/' : next;
}

/** Keeps the app behind sign-in; the address the visitor asked for waits in `?next=`. */
export const signedInGuard: CanMatchFn = async () => {
  const session = inject(Session);
  const router = inject(Router);
  await session.ready;
  if (session.signedIn()) return true;
  const asked = router.currentNavigation()?.extractedUrl.toString();
  const next = safeNext(asked);
  return router.createUrlTree(['/sign-in'], next === '/' ? {} : { queryParams: { next } });
};

/** Sign-in and register are only for signed-out visitors. */
export const signedOutGuard: CanMatchFn = async () => {
  const session = inject(Session);
  const router = inject(Router);
  await session.ready;
  return !session.signedIn() || router.createUrlTree(['/']);
};
