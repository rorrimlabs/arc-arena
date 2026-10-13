import { A11yModule } from '@angular/cdk/a11y';
import { CdkMenu, CdkMenuItemRadio, CdkMenuTrigger } from '@angular/cdk/menu';
import { Component, computed, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { ArenaContext } from '../arena/arena-context';
import { Session } from '../auth/session';
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
}
