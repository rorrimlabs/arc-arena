import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const PAYROLL_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Payroll · ArenaOS',
    loadComponent: () => import('./payroll-page').then((m) => m.PayrollPage),
  },
  {
    // A run's printable summary (Print → Save as PDF).
    path: 'print',
    providers: [MATERIAL_DEFAULTS],
    title: 'Pay summary · ArenaOS',
    loadComponent: () => import('./print/payroll-print').then((m) => m.PayrollPrint),
  },
];
