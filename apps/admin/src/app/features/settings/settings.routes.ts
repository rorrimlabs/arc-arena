import { Routes } from '@angular/router';
import { capabilityGuard } from '../../core/venue/venue';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const SETTINGS_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Settings · ArenaOS',
    loadComponent: () => import('./settings-page').then((m) => m.SettingsPage),
  },
  {
    // The games library: its own list/detail screen under Settings, for venues with game types.
    path: 'games',
    canMatch: [capabilityGuard('games')],
    loadChildren: () => import('../games/games.routes').then((m) => m.GAMES_ROUTES),
  },
];
