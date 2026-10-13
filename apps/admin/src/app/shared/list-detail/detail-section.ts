import { Component, input } from '@angular/core';
import { MatCard } from '@angular/material/card';

/** One card in a detail pane (`dt.sections`): optional heading and subtitle over its rows. */
@Component({
  selector: 'app-detail-section',
  imports: [MatCard],
  template: `
    <mat-card appearance="outlined">
      <div class="flex flex-col gap-4 p-5">
        @if (heading()) {
          <div class="flex flex-col gap-1.25">
            <h3 class="text-base leading-[1.2] font-semibold">{{ heading() }}</h3>
            @if (subtitle()) {
              <p class="text-[13px] leading-[1.4] text-muted">{{ subtitle() }}</p>
            }
          </div>
        }
        <div class="flex flex-col gap-4"><ng-content /></div>
      </div>
    </mat-card>
  `,
})
export class DetailSection {
  readonly heading = input('');
  readonly subtitle = input('');
}
