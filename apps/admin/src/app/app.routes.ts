import { Routes } from '@angular/router';
import { arenaGuard } from './core/arena/arena-context';
import { signedInGuard, signedOutGuard } from './core/auth/session';
import { NAV_ITEMS } from './core/layout/nav';
import { Shell } from './core/layout/shell';

/** Screens built so far replace their placeholder here with lazy-loaded feature routes. */
const BUILT: Readonly<Record<string, () => Promise<Routes>>> = {
  sales: () => import('./features/sales/sales.routes').then((m) => m.SALES_ROUTES),
  users: () => import('./features/users/users.routes').then((m) => m.USERS_ROUTES),
};

export const routes: Routes = [
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
              data: { heading: item.label },
              loadComponent: () =>
                import('./shared/screen-placeholder').then((m) => m.ScreenPlaceholder),
            },
      ),
    ],
  },
  // Signed out (or no arena yet): the guards above send the visitor where they belong.
  { path: '**', redirectTo: '' },
];
