import { A11yModule } from '@angular/cdk/a11y';
import { CdkMenu, CdkMenuItemRadio, CdkMenuTrigger } from '@angular/cdk/menu';
import { Component, computed, effect, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { ArenaContext } from '../arena/arena-context';
import { Session } from '../auth/session';
import { RealtimeSync } from '../sync/realtime-sync';
import { Layout } from './layout';
import { NAV_GROUPS } from './nav';

/** App frame from the design: side nav (overlay drawer / 88px rail / 264px full) + routed page. */
@Component({
  selector: 'app-shell',
  imports: [
    RouterOutlet,
    RouterLink,
    RouterLinkActive,
    A11yModule,
    CdkMenuTrigger,
    CdkMenu,
    CdkMenuItemRadio,
  ],
  templateUrl: './shell.html',
  host: { class: 'flex h-dvh overflow-hidden bg-bg text-fg' },
})
export class Shell {
  protected readonly layout = inject(Layout);
  protected readonly arenaContext = inject(ArenaContext);
  protected readonly session = inject(Session);
  /** Injected so live updates run while the dashboard is open (it follows user and arena). */
  private readonly realtime = inject(RealtimeSync);
  private readonly router = inject(Router);

  protected readonly navGroups = NAV_GROUPS;
  protected readonly rail = computed(() => !this.layout.compact() && this.layout.rail());
  protected readonly navShown = computed(() => !this.layout.compact() || this.layout.navOpen());
  /** The name this arena knows the owner by, else the login's own name or e-mail. */
  protected readonly ownerName = computed(
    () => this.arenaContext.currentMembership()?.name || this.session.user()?.name || '',
  );
  protected readonly ownerInitials = computed(() =>
    this.ownerName()
      .split(/[\s@.]+/)
      .filter(Boolean)
      .map((word) => word[0])
      .slice(0, 2)
      .join('')
      .toUpperCase(),
  );

  constructor() {
    // Signed out from elsewhere (another tab, or the refresh token was rejected): leave the
    // dashboard instead of keeping the previous login's figures on screen.
    effect(() => {
      if (!this.session.user()) void this.router.navigate(['/sign-in']);
    });
  }
}
