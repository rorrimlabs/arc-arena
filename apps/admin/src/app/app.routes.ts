import { Routes } from '@angular/router';
import { arenaGuard } from './core/arena/arena-context';
import { signedInGuard, signedOutGuard } from './core/auth/session';
import { NAV_ITEMS } from './core/layout/nav';
import { Shell } from './core/layout/shell';
import { CONFIG_PROBLEM } from './core/supabase/supabase';

/** Screens built so far replace their placeholder here with lazy-loaded feature routes. */
const BUILT: Readonly<Record<string, () => Promise<Routes>>> = {
  overview: () => import('./features/overview/overview.routes').then((m) => m.OVERVIEW_ROUTES),
  sales: () => import('./features/sales/sales.routes').then((m) => m.SALES_ROUTES),
  pricing: () => import('./features/pricing/pricing.routes').then((m) => m.PRICING_ROUTES),
  users: () => import('./features/users/users.routes').then((m) => m.USERS_ROUTES),
  stations: () => import('./features/stations/stations.routes').then((m) => m.STATIONS_ROUTES),
  games: () => import('./features/games/games.routes').then((m) => m.GAMES_ROUTES),
  members: () => import('./features/members/members.routes').then((m) => m.MEMBERS_ROUTES),
  settings: () => import('./features/settings/settings.routes').then((m) => m.SETTINGS_ROUTES),
};

const APP_ROUTES: Routes = [
  {
    // Opened from the invitation e-mail, signed in or not: the page signs the person in itself.
    path: 'accept-invite',
    title: 'Accept invitation · ArenaOS',
    loadComponent: () => import('./features/auth/accept-invite').then((m) => m.AcceptInvite),
  },
  {
    path: 'sign-in',
    title: 'Sign in · ArenaOS',
    canMatch: [signedOutGuard],
    loadComponent: () => import('./features/auth/sign-in').then((m) => m.SignIn),
  },
  {
    path: 'register',
    title: 'Create account · ArenaOS',
    canMatch: [signedOutGuard],
    loadComponent: () => import('./features/auth/register').then((m) => m.Register),
  },
  {
    path: 'create-arena',
    title: 'Create your arena · ArenaOS',
    canMatch: [signedInGuard],
    loadComponent: () => import('./features/auth/create-arena').then((m) => m.CreateArena),
  },
  {
    path: '',
    component: Shell,
    canMatch: [signedInGuard, arenaGuard],
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'overview' },
      // Each screen starts as a placeholder; `/design-build <screen>` adds it to BUILT.
      ...NAV_ITEMS.map((item) =>
        BUILT[item.path]
          ? { path: item.path, loadChildren: BUILT[item.path] }
          : {
              path: item.path,
              title: `${item.label} · ArenaOS`,
              // Overview is a plain page; every other screen is a list/detail frame.
              data: { heading: item.label, kind: item.path === 'overview' ? 'page' : 'list' },
              loadComponent: () =>
                import('./shared/screen-placeholder').then((m) => m.ScreenPlaceholder),
            },
      ),
    ],
  },
  // Signed out (or no arena yet): the guards above send the visitor where they belong.
  { path: '**', redirectTo: '' },
];

/** A build that cannot be used as configured shows only why (core/supabase configProblem). */
const CONFIG_ERROR_ROUTES: Routes = [
  {
    path: '**',
    title: 'Setup needed · ArenaOS',
    loadComponent: () => import('./features/auth/config-error').then((m) => m.ConfigError),
  },
];

export const routes: Routes = CONFIG_PROBLEM ? CONFIG_ERROR_ROUTES : APP_ROUTES;
