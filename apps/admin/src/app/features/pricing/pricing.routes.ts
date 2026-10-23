import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const PRICING_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Pricing · ARQ',
    loadComponent: () => import('./pricing-page').then((m) => m.PricingPage),
  },
];
