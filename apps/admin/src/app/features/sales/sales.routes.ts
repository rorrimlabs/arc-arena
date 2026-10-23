import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const SALES_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Sales · ARQ',
    loadComponent: () => import('./sales-page').then((m) => m.SalesPage),
  },
];
