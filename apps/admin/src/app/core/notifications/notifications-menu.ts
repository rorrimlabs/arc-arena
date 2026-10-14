import { CdkMenu, CdkMenuItem } from '@angular/cdk/menu';
import { Component, inject } from '@angular/core';
import { AdminNotificationsStore } from './admin-notifications.store';

@Component({
  selector: 'app-notifications-menu',
  imports: [CdkMenu, CdkMenuItem],
  template: `
    <div
      cdkMenu
      class="flex w-88 max-w-[calc(100vw-2rem)] flex-col rounded-menu bg-surface-raised text-fg shadow-raised border border-border"
    >
      <div class="flex items-center justify-between border-b border-border px-4 py-3">
        <div class="flex items-center gap-2">
          <span class="text-sm font-semibold leading-none">Operational Alerts</span>
          @if (store.unreadCount() > 0) {
            <span
              class="grid size-5 place-items-center rounded-full bg-primary-soft text-[11px] font-bold text-primary-text"
            >
              {{ store.unreadCount() }}
            </span>
          }
        </div>
        @if (store.unreadCount() > 0) {
          <button
            type="button"
            class="text-xs font-medium text-muted hover:text-fg hover:underline outline-none"
            (click)="store.clearAll()"
          >
            Clear all
          </button>
        }
      </div>

      <div class="flex max-h-96 flex-col overflow-y-auto divide-y divide-border">
        @for (item of store.notifications(); track item.id) {
          <div class="flex items-start gap-3 p-3 hover:bg-info-soft transition-colors">
            <div
              class="grid size-8 flex-none place-items-center rounded-card"
              [class.bg-danger-soft]="item.type === 'time_completed'"
              [class.text-danger]="item.type === 'time_completed'"
              [class.bg-warning-soft]="item.type === 'ending_soon'"
              [class.text-warning]="item.type === 'ending_soon'"
              [class.bg-primary-soft]="item.type === 'session_ended'"
              [class.text-primary-text]="item.type === 'session_ended'"
            >
              <span class="icon text-lg leading-none" aria-hidden="true">
                @if (item.type === 'time_completed') {
                  alarm_on
                } @else if (item.type === 'ending_soon') {
                  hourglass_bottom
                } @else {
                  check_circle
                }
              </span>
            </div>

            <div class="flex min-w-0 flex-1 flex-col gap-0.5">
              <span class="truncate text-xs font-semibold leading-snug">{{ item.title }}</span>
              <span class="text-[11px] leading-tight text-muted">{{ item.subtitle }}</span>
            </div>

            <button
              type="button"
              class="grid size-7 flex-none place-items-center rounded-full text-muted hover:bg-surface-sunken hover:text-fg outline-none"
              title="Dismiss alert"
              aria-label="Dismiss alert"
              (click)="store.dismiss(item.id)"
            >
              <span class="icon text-base leading-none" aria-hidden="true">close</span>
            </button>
          </div>
        } @empty {
          <div class="flex flex-col items-center justify-center gap-2 py-8 px-4 text-center">
            <span class="icon text-3xl text-subtle" aria-hidden="true">notifications_none</span>
            <span class="text-xs font-medium text-muted">No pending alerts</span>
            <span class="text-[11px] text-subtle">
              Live session endings and status updates appear here.
            </span>
          </div>
        }
      </div>
    </div>
  `,
})
export class NotificationsMenu {
  protected readonly store = inject(AdminNotificationsStore);
}
