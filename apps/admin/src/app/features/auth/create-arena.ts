import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormField, form, maxLength, required } from '@angular/forms/signals';
import { MatButton } from '@angular/material/button';
import { MatFormField, MatLabel } from '@angular/material/form-field';
import { MatInput } from '@angular/material/input';
import { Router } from '@angular/router';
import { ArenaApi } from '../../core/arena/arena-api';
import { ArenaContext } from '../../core/arena/arena-context';
import { AuthApi, toAppError } from '../../core/auth/auth-api';
import { Session } from '../../core/auth/session';
import { AuthCard } from './auth-card';
import { MATERIAL_DEFAULTS } from '../../shared/material/material-defaults';

const MAX_NAME = 80;

/**
 * A signed-in login with no arena to manage creates its own (create_my_arena: confirmed logins,
 * one arena per login). It starts with the starter catalog; everything is editable afterwards.
 */
@Component({
  selector: 'app-create-arena',
  providers: [MATERIAL_DEFAULTS],
  imports: [AuthCard, FormField, MatFormField, MatLabel, MatInput, MatButton],
  template: `
    <app-auth-card heading="Create your arena" [subtitle]="subtitle()">
      @if (loadFailed()) {
        <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
        <button
          mat-flat-button
          type="button"
          class="arena-cta"
          [disabled]="busy()"
          (click)="check()"
        >
          Try again
        </button>
      } @else if (context.ownsArena()) {
        <p class="text-sm leading-[1.4] text-muted">
          This login already owns an arena, but your access to it is turned off. Ask the operator to
          restore it.
        </p>
      } @else {
        <form class="flex flex-col gap-5" novalidate (submit)="create($event)">
          <mat-form-field appearance="outline" subscriptSizing="dynamic">
            <mat-label>Arena name</mat-label>
            <input matInput autocomplete="organization" [formField]="f.arena" />
          </mat-form-field>
          <mat-form-field appearance="outline" subscriptSizing="dynamic">
            <mat-label>Your name</mat-label>
            <input matInput autocomplete="name" [formField]="f.owner" />
          </mat-form-field>
          @if (error()) {
            <p role="alert" class="text-sm leading-[1.3] font-medium text-danger">{{ error() }}</p>
          }
          <button mat-flat-button type="submit" class="arena-cta" [disabled]="busy()">
            Create arena
          </button>
        </form>
      }
      <button mat-button type="button" class="self-start" (click)="session.signOut()">
        Sign out
      </button>
    </app-auth-card>
  `,
})
export class CreateArena implements OnInit {
  protected readonly session = inject(Session);
  protected readonly context = inject(ArenaContext);
  private readonly arenaApi = inject(ArenaApi);
  private readonly authApi = inject(AuthApi);
  private readonly router = inject(Router);

  protected readonly subtitle = computed(
    () =>
      `Signed in as ${this.session.user()?.email ?? ''}. You will be its owner. It starts with ` +
      'sample stations, rates and games — change them any time. One arena per login.',
  );

  protected readonly model = signal({ arena: '', owner: '' });
  protected readonly f = form(this.model, (p) => {
    required(p.arena, { message: 'Enter the arena name' });
    maxLength(p.arena, MAX_NAME, { message: `Keep the arena name under ${MAX_NAME} characters` });
    required(p.owner, { message: 'Enter your name' });
    maxLength(p.owner, MAX_NAME, { message: `Keep your name under ${MAX_NAME} characters` });
  });
  protected readonly error = signal('');
  protected readonly busy = signal(false);
  protected readonly loadFailed = signal(false);

  ngOnInit(): void {
    void this.check();
  }

  /** Already manages an arena (e.g. opened this page by hand): go to the dashboard. */
  protected async check(): Promise<void> {
    this.busy.set(true);
    try {
      await this.context.load(true);
      this.loadFailed.set(false);
      this.error.set('');
      if (this.context.arenas().length > 0) await this.router.navigateByUrl('/');
    } catch (e) {
      this.loadFailed.set(true);
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }

  protected async create(event: Event): Promise<void> {
    event.preventDefault();
    const first = this.f().errorSummary()[0];
    const arenaName = this.model().arena.trim();
    const ownerName = this.model().owner.trim();
    if (first || !arenaName || !ownerName) {
      this.error.set(first?.message ?? 'Enter the arena name and your name');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    try {
      const id = await this.arenaApi.createArena(arenaName, ownerName);
      // The side nav shows this name; the arena works without it.
      await this.authApi.setName(ownerName).catch(() => undefined);
      await this.session.refresh();
      await this.context.load(true);
      this.context.select(id);
      await this.router.navigate(['/users']);
    } catch (e) {
      this.error.set(toAppError(e).message);
    } finally {
      this.busy.set(false);
    }
  }
}
