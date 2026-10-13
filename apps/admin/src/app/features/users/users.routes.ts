import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const USERS_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Users · ArenaOS',
    loadComponent: () => import('./users-page').then((m) => m.UsersPage),
  },
];
