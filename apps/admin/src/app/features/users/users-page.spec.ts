import { BreakpointObserver } from '@angular/cdk/layout';
import { TestBed } from '@angular/core/testing';
import { MATERIAL_ANIMATIONS } from '@angular/material/core';
import { Router, provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { of } from 'rxjs';
import { vi } from 'vitest';
import { routes } from '../../app.routes';
import { ArenaApi } from '../../core/arena/arena-api';
import { SampleArenaApi } from '../../core/arena/arena-api.sample';
import { AuthApi } from '../../core/auth/auth-api';
import { SampleAuthApi } from '../../core/auth/auth-api.sample';
import { UsersApi } from './data/users-api';
import { SampleUsersApi } from './data/users-api.sample';

/** Pretend the window is `width` px wide (the Layout service reads the CDK breakpoints). */
function breakpoints(width: number) {
  const matches = (query: string) => {
    const min = /min-width:\s*([\d.]+)px/.exec(query);
    const max = /max-width:\s*([\d.]+)px/.exec(query);
    return (!min || width >= +min[1]) && (!max || width <= +max[1]);
  };
  return {
    isMatched: matches,
    observe: (q: string) => of({ matches: matches(q), breakpoints: {} }),
  };
}

describe('Users', () => {
  let harness: RouterTestingHarness;
  let api: SampleUsersApi;
  let arenas: SampleArenaApi;

  async function start(url: string, width = 1440) {
    api = new SampleUsersApi();
    arenas = new SampleArenaApi();
    TestBed.configureTestingModule({
      providers: [
        provideRouter(routes, withComponentInputBinding()),
        { provide: AuthApi, useValue: new SampleAuthApi() },
        { provide: ArenaApi, useValue: arenas },
        { provide: UsersApi, useValue: api },
        { provide: BreakpointObserver, useValue: breakpoints(width) },
        { provide: MATERIAL_ANIMATIONS, useValue: { animationsDisabled: true } },
      ],
    });
    harness = await RouterTestingHarness.create();
    await harness.navigateByUrl(url);
    await settle();
  }

  async function settle() {
    await harness.fixture.whenStable();
    await new Promise((r) => setTimeout(r));
    await harness.fixture.whenStable();
  }

  const doc = () => harness.routeNativeElement?.ownerDocument as Document;
  const section = (key: string) => doc().querySelector(`section[aria-labelledby="users-${key}"]`);
  const rowsIn = (key: string) =>
    [...(section(key)?.querySelectorAll('app-list-row a') ?? [])] as HTMLElement[];
  const rowText = (r: HTMLElement) =>
    [...r.querySelectorAll('span.truncate, app-status-pill')].map((e) => e.textContent?.trim());
  const detail = () => doc().querySelector('app-user-detail') as HTMLElement | null;
  const button = (label: string, scope: ParentNode = doc()) =>
    [...scope.querySelectorAll('button')].find((b) => b.textContent?.includes(label)) as
      HTMLButtonElement | undefined;
  const snack = () => doc().querySelector('mat-snack-bar-container')?.textContent?.trim();
  const dialog = () => doc().querySelector('mat-dialog-container') as HTMLElement;

  function type(label: string, value: string) {
    const field = [...doc().querySelectorAll('mat-form-field')].find((f) =>
      f.querySelector('mat-label')?.textContent?.includes(label),
    );
    const input = field?.querySelector('input') as HTMLInputElement;
    input.value = value;
    input.dispatchEvent(new Event('input'));
  }

  afterEach(() =>
    doc()
      ?.querySelectorAll('.cdk-overlay-container')
      .forEach((c) => c.remove()),
  );

  it('lists owners and staff in their own sections', async () => {
    await start('/users');
    expect(section('owners')?.querySelector('h2')?.textContent?.trim()).toBe('Owners · 1');
    expect(rowsIn('owners').map(rowText)).toEqual([['Arjun Mehra', 'arjun@404arena.in', 'Owner']]);
    expect(section('staff')?.querySelector('h2')?.textContent?.trim()).toBe('Staff · 3');
    expect(rowsIn('staff').map(rowText)).toEqual([
      ['Priya Nair', 'priya@404arena.in', 'Active'],
      ['Rohan Das', 'rohan@404arena.in', 'Active'],
      ['Kavya Iyer', 'kavya@404arena.in', 'Active'],
    ]);
  });

  it('wide: shows the first user until one is picked; the pick is in the URL', async () => {
    await start('/users');
    expect(detail()?.textContent).toContain('Owner account');
    rowsIn('staff')[0].click();
    await settle();
    expect(TestBed.inject(Router).url).toBe('/users?id=u1');
    expect(detail()?.querySelector('h2')?.textContent?.trim()).toBe('Priya Nair');
    expect(detail()?.textContent).toContain('₹48,120');
    expect(rowsIn('staff')[0].getAttribute('aria-current')).toBe('true');
  });

  it('narrow: the detail opens over the list and closes back to it', async () => {
    await start('/users', 1024);
    expect(detail()).toBeNull();
    rowsIn('staff')[1].click();
    await settle();
    expect(doc().querySelector('[role="dialog"][aria-label="User"]')).not.toBeNull();
    (doc().querySelector('button[aria-label="Close"]') as HTMLButtonElement).click();
    await settle();
    expect(detail()).toBeNull();
  });

  it('toggling a staff permission saves it', async () => {
    await start('/users?id=u2');
    const toggles = [
      ...detail()!.querySelectorAll('mat-slide-toggle button'),
    ] as HTMLButtonElement[];
    expect(toggles.map((t) => t.getAttribute('aria-checked'))).toEqual([
      'true',
      'true',
      'false',
      'false',
    ]);
    toggles[2].click(); // Give discounts
    await settle();
    expect(api.users.find((u) => u.userId === 'u2')?.perms).toEqual(['start', 'bill', 'discount']);
  });

  it('deactivating staff asks first, then marks them Off and says they are signed out', async () => {
    await start('/users?id=u3');
    const dialog = () => doc().querySelector('mat-dialog-container') as HTMLElement | null;
    button('Deactivate', detail()!)?.click();
    await settle();
    expect(dialog()?.textContent).toContain('Deactivate Kavya Iyer?');
    button('Cancel', dialog()!)?.click();
    await settle();
    expect(api.users.find((u) => u.userId === 'u3')?.active).toBe(true);

    button('Deactivate', detail()!)?.click();
    await settle();
    button('Deactivate', dialog()!.querySelector('mat-dialog-actions')!)?.click();
    await settle();
    expect(api.users.find((u) => u.userId === 'u3')?.active).toBe(false);
    expect(rowText(rowsIn('staff')[2])).toContain('Off');
    expect(snack()).toBe('Kavya Iyer deactivated · signed out of the floor app');
    expect(button('Reactivate', detail()!)).toBeDefined();
  });

  it('an owner can be renamed but not deactivated or given floor toggles', async () => {
    await start('/users?id=u0');
    expect(button('Edit', detail()!)).toBeDefined();
    expect(button('Deactivate', detail()!)).toBeUndefined();
    expect(detail()!.querySelector('mat-slide-toggle')).toBeNull();
  });

  const invites = () => doc().querySelector('section[aria-labelledby="users-invites"]');
  const inviteRows = () =>
    [...(invites()?.querySelectorAll('li') ?? [])].map((li) =>
      [...li.querySelectorAll('span.truncate, app-status-pill')].map((e) => e.textContent?.trim()),
    );

  it('invite staff: checks the fields and e-mails an invitation, no password', async () => {
    await start('/users');
    button('Invite')?.click();
    await settle();
    expect(dialog().querySelector('h2')?.textContent).toContain('Invite user');
    expect(dialog().textContent).toContain('They choose their own password');
    expect(dialog().textContent).toContain('sign in on the staff app');
    expect(dialog().querySelector('input[type="password"]')).toBeNull();
    expect(dialog().textContent).not.toContain('Starting password');

    button('Send invitation', dialog())?.click();
    await settle();
    expect(dialog().querySelector('[role="alert"]')?.textContent?.trim()).toBe('Enter a name');

    type('Name', 'Farhan Ali');
    type('Email', 'priya@404arena.in');
    button('Send invitation', dialog())?.click();
    await settle();
    expect(dialog().querySelector('[role="alert"]')?.textContent?.trim()).toBe(
      'That email already has access to this arena',
    );
    expect(api.sent).toEqual([]);

    type('Email', 'Farhan@404arena.in');
    button('Send invitation', dialog())?.click();
    await settle();
    await settle();
    expect(doc().querySelector('mat-dialog-container')).toBeNull();
    expect(snack()).toBe('Invitation sent to farhan@404arena.in');
    expect(api.sent).toEqual([
      {
        role: 'staff',
        name: 'Farhan Ali',
        email: 'farhan@404arena.in',
        perms: ['start', 'bill', 'members'],
      },
    ]);
    expect('password' in api.sent[0]).toBe(false);
    // Nobody joins until they accept: the staff list is unchanged, the invitation is pending.
    expect(TestBed.inject(Router).url).toBe('/users');
    expect(section('staff')?.querySelector('h2')?.textContent?.trim()).toBe('Staff · 3');
    expect(inviteRows()[0]).toEqual([
      'farhan@404arena.in',
      'Farhan Ali · Staff · invited by Arjun Mehra',
      'Expires 20 Oct',
    ]);
  });

  it('an owner can invite another owner', async () => {
    await start('/users');
    button('Invite')?.click();
    await settle();
    button('Owner', dialog())?.click();
    await settle();
    expect(dialog().textContent).toContain('manage the arena here with every permission');
    type('Name', 'Anand Paul');
    type('Email', 'anand@404arena.in');
    button('Send invitation', dialog())?.click();
    await settle();
    await settle();
    expect(snack()).toBe('Invitation sent to anand@404arena.in as an owner');
    expect(api.sent.at(-1)?.role).toBe('owner');
    expect(section('owners')?.querySelector('h2')?.textContent?.trim()).toBe('Owners · 1');
    expect(inviteRows()[0]?.[1]).toBe('Anand Paul · Owner · invited by Arjun Mehra');
  });

  it('a refused invitation is explained in the dialog', async () => {
    await start('/users');
    button('Invite')?.click();
    await settle();
    type('Name', 'Farhan Ali');
    type('Email', 'farhan@404arena.in');
    api.failNext = 'email_rate_limited';
    button('Send invitation', dialog())?.click();
    await settle();
    expect(dialog().querySelector('[role="alert"]')?.textContent?.trim()).toBe(
      'Too many e-mails right now. Wait a while, then try again',
    );
  });

  it('lists pending invitations with who invited them and until when', async () => {
    await start('/users');
    expect(invites()?.querySelector('h2')?.textContent?.trim()).toBe('Pending invitations · 2');
    expect(inviteRows()).toEqual([
      ['farah@404arena.in', 'Farah Khan · Staff · invited by Arjun Mehra', 'Expires 19 Oct'],
      ['neha@404arena.in', 'Neha Joshi · Staff', 'Expired'],
    ]);
  });

  it('withdraws an invitation after confirming', async () => {
    await start('/users');
    const withdraw = invites()?.querySelector(
      'button[aria-label="Withdraw the invitation to farah@404arena.in"]',
    ) as HTMLButtonElement;
    withdraw.click();
    await settle();
    expect(dialog().querySelector('h2')?.textContent).toContain(
      'Withdraw the invitation to farah@404arena.in?',
    );
    button('Withdraw', dialog().querySelector('mat-dialog-actions')!)?.click();
    await settle();
    await settle();
    expect(api.invites.map((i) => i.email)).toEqual(['neha@404arena.in']);
    expect(snack()).toBe('Invitation to farah@404arena.in withdrawn');
    expect(inviteRows().map((r) => r[0])).toEqual(['neha@404arena.in']);
  });

  it('a permission change the server adjusted reloads the list', async () => {
    await start('/users?id=u2');
    api.adjustNext = true;
    const list = vi.spyOn(api, 'list');
    const toggles = [
      ...detail()!.querySelectorAll('mat-slide-toggle button'),
    ] as HTMLButtonElement[];
    toggles[2].click(); // Give discounts
    await settle();
    expect(list).toHaveBeenCalledTimes(1);
    expect(api.users.find((u) => u.userId === 'u2')?.perms).toEqual(['start', 'bill']);
    const after = [...detail()!.querySelectorAll('mat-slide-toggle button')] as HTMLButtonElement[];
    expect(after.map((t) => t.getAttribute('aria-checked'))).toEqual([
      'true',
      'true',
      'false',
      'false',
    ]);
  });

  it('owner-level staff (not an owner) cannot choose Owner', async () => {
    await start('/users');
    arenas.memberships = arenas.memberships.map((m) => ({ ...m, role: 'staff' }));
    // The memberships were read at start; reload them as the guard would on the next visit.
    const { ArenaContext } = await import('../../core/arena/arena-context');
    await TestBed.inject(ArenaContext).load(true);
    button('Invite')?.click();
    await settle();
    expect(button('Owner', dialog())).toBeUndefined();
  });
});
