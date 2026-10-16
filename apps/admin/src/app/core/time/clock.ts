import { Service } from '@angular/core';

/** "Now" for date ranges and labels; tests provide a fixed one. */
@Service()
export class Clock {
  now(): Date {
    return new Date();
  }
}
