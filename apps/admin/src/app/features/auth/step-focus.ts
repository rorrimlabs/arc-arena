import { ElementRef, Injector, Signal, afterNextRender, effect, inject } from '@angular/core';

/**
 * When `step` changes after the first render, moves focus to the new step's element marked
 * `data-step-focus`: the control just used went away with the old step. Call in a component's
 * injection context.
 */
export function focusOnStepChange(step: Signal<unknown>): void {
  const host = inject<ElementRef<HTMLElement>>(ElementRef);
  const injector = inject(Injector);
  let first = true;
  effect(() => {
    step();
    if (first) {
      first = false;
      return;
    }
    afterNextRender(
      () => host.nativeElement.querySelector<HTMLElement>('[data-step-focus]')?.focus(),
      { injector },
    );
  });
}
