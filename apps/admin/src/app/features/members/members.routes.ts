import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const MEMBERS_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Members · ARQ',
    loadComponent: () => import('./members-page').then((m) => m.MembersPage),
  },
];
