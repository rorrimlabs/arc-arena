import { Routes } from '@angular/router';
import { permGuard } from '../../core/arena/arena-context';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

export const ATTENDANCE_ROUTES: Routes = [
  {
    path: '',
    providers: [MATERIAL_DEFAULTS],
    title: 'Attendance · ArenaOS',
    loadComponent: () => import('./attendance-home-page').then((m) => m.AttendanceHomePage),
  },
  {
    // Every entry with every filter, the punch map and the export (opened from Attendance).
    path: 'records',
    providers: [MATERIAL_DEFAULTS],
    title: 'Attendance records · ArenaOS',
    loadComponent: () => import('./attendance-page').then((m) => m.AttendancePage),
  },
  {
    // Staff leave requests waiting for a decision, all requests and balances (from Attendance).
    path: 'leave',
    providers: [MATERIAL_DEFAULTS],
    title: 'Leave · ArenaOS',
    canMatch: [permGuard('leave_approve')],
    loadComponent: () => import('../leave/leave-page').then((m) => m.LeavePage),
  },
];
