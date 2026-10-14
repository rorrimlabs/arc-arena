import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const CONTROLLERS_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Controllers · ArenaOS',
    loadComponent: () => import('./controllers-page').then((m) => m.ControllersPage),
  },
];
