import { Routes } from '@angular/router';
import { signedInGuard } from './core/auth/session';
import { NAV_ITEMS } from './core/layout/nav';
import { Shell } from './core/layout/shell';

export const routes: Routes = [
  {
    path: 'sign-in',
    title: 'Sign in · ArenaOS',
    loadComponent: () => import('./features/auth/sign-in').then((m) => m.SignIn),
  },
  {
    path: '',
    component: Shell,
    canMatch: [signedInGuard],
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'overview' },
      // Each screen starts as a placeholder; `/design-build <screen>` replaces its entry with
      // the feature's lazy-loaded routes.
      ...NAV_ITEMS.map((item) => ({
        path: item.path,
        title: `${item.label} · ArenaOS`,
        data: { heading: item.label },
        loadComponent: () => import('./shared/screen-placeholder').then((m) => m.ScreenPlaceholder),
      })),
    ],
  },
  { path: '**', redirectTo: '' },
];
