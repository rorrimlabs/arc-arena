import { Service } from '@angular/core';

/**
 * What one signed-in login loaded ends with it: on sign-out (here, in another tab, or a refresh
 * token the server rejected) and when a different login takes over, Session runs every
 * registered clear synchronously, before anything can read the next login's data. Kept free of
 * other services so any store can register.
 */
@Service()
export class LoginScope {
  private readonly clears: (() => void)[] = [];

  /** Registers `clear` for every login change. For root services: kept for the app's lifetime. */
  onEnd(clear: () => void): void {
    this.clears.push(clear);
  }

  /** Called by Session when the signed-in login changes. */
  end(): void {
    for (const clear of this.clears) clear();
  }
}
