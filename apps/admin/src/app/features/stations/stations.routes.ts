import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const STATIONS_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Stations · ARQ',
    loadComponent: () => import('./stations-page').then((m) => m.StationsPage),
  },
];
