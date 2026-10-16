import { Component, input } from '@angular/core';
import { MatCard } from '@angular/material/card';

/** A small KPI tile from the detail pane (`dt.stats`): muted label over a display-font value. */
@Component({
  selector: 'app-stat-tile',
  imports: [MatCard],
  template: `
    <mat-card appearance="outlined">
      <div class="flex flex-col gap-2 px-4 py-3.5">
        <span class="text-[12.5px] leading-none font-medium text-muted">{{ label() }}</span>
        <span class="font-display text-[22px] leading-none font-bold tabular-nums">{{
          value()
        }}</span>
      </div>
    </mat-card>
  `,
})
export class StatTile {
  readonly label = input.required<string>();
  readonly value = input.required<string>();
}
