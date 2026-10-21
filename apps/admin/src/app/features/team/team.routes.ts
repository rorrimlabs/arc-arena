import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const TEAM_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Team · ArenaOS',
    loadComponent: () => import('./team-page').then((m) => m.TeamPage),
    // The selection, read by the page (childParams): /staff/team/<staff>/<tab>.
    children: [
      { path: ':id', children: [] },
      { path: ':id/:tab', children: [] },
    ],
  },
];
