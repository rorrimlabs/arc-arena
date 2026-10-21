import { Component, input, output } from '@angular/core';
import { MatSlideToggle, MatSlideToggleChange } from '@angular/material/slide-toggle';

let next = 0;

/** A labelled switch inside a detail section (design: `tgl(l, sub, on)`). */
@Component({
  selector: 'app-toggle-row',
  imports: [MatSlideToggle],
  host: { class: 'flex items-center justify-between gap-4' },
  template: `
    <span class="flex flex-col gap-1">
      <span class="text-[15px] leading-[1.3]" [id]="id + '-l'">{{ label() }}</span>
      @if (sub()) {
        <span class="text-[13px] leading-[1.3] text-muted" [id]="id + '-s'">{{ sub() }}</span>
      }
    </span>
    <mat-slide-toggle
      hideIcon
      [checked]="checked()"
      [disabled]="disabled()"
      [aria-labelledby]="id + '-l'"
      [aria-describedby]="sub() ? id + '-s' : ''"
      (change)="changed.emit($event)"
    />
  `,
})
export class ToggleRow {
  readonly label = input.required<string>();
  readonly sub = input('');
  readonly checked = input(false);
  readonly disabled = input(false);
  /** The switch moved; put it back (`event.source.checked`) if the change is refused. */
  readonly changed = output<MatSlideToggleChange>();

  protected readonly id = `toggle-row-${next++}`;
}
