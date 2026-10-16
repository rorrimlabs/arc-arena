import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const OVERVIEW_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Overview · ArenaOS',
    loadComponent: () => import('./overview-page').then((m) => m.OverviewPage),
  },
];
