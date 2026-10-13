import { Routes } from '@angular/router';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const GAMES_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Games · ArenaOS',
    loadComponent: () => import('./games-page').then((m) => m.GamesPage),
  },
];
