import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const TEAM_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Team · ArenaOS',
    loadComponent: () => import('./team-page').then((m) => m.TeamPage),
  },
];
