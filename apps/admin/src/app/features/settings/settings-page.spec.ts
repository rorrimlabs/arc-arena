import { PageTest, startPage } from '../../testing/page-test';

describe('Settings', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  it('lists the three groups and opens Arena on a wide screen', async () => {
    t = await startPage('/settings');
    expect(t.rows().map(t.rowText)).toEqual([
      ['Arena', 'Name, area, hours'],
      ['Billing', 'GST, invoices, payment, discounts'],
      ['Sessions', 'Time options and warnings'],
    ]);
    const arena = t.doc().querySelector('app-arena-settings') as HTMLElement;
    expect(t.text(arena.querySelector('h2'))).toBe('Arena');
    const name = arena.querySelector('input') as HTMLInputElement;
    expect(name.value).toBe('404 Arena Koramangala');
    expect(name.disabled).toBe(false);
    expect([...arena.querySelectorAll('input')].slice(0, 3).map((i) => i.value)).toEqual([
      '404 Arena Koramangala',
      'Koramangala',
      '080 4110 2209',
    ]);
  });

  it('saves the arena name, area and phone; the switcher picks up the new name', async () => {
    t = await startPage('/settings?id=arena');
    const arena = t.doc().querySelector('app-arena-settings') as HTMLElement;
    t.type('Arena name', '404 Arena HSR', arena);
    t.type('Area', 'HSR Layout', arena);
    await t.settle();
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.snack()).toBe('Settings saved · the floor app updates on next refresh');
    expect(t.text(arena.querySelector('h2 + div'))).toContain('404 Arena HSR · HSR Layout');
    expect(t.text(t.doc().querySelector('app-shell, app-root'))).toContain('404 Arena HSR');
    expect(t.doc().querySelector('app-unsaved-bar')).toBeNull();
  });

  it('refuses a phone with letters', async () => {
    t = await startPage('/settings?id=arena');
    const arena = t.doc().querySelector('app-arena-settings') as HTMLElement;
    t.type('Phone', 'call me', arena);
    await t.settle();
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.text(arena.querySelector('[role="alert"]'))).toBe(
      'Use 6 to 20 digits, spaces, +, ( ) or - for the phone',
    );
  });

  it('saves opening hours and keeps happy hour', async () => {
    t = await startPage('/settings?id=arena');
    const arena = t.doc().querySelector('app-arena-settings') as HTMLElement;
    const monday = arena.querySelector('mat-slide-toggle button') as HTMLButtonElement;
    expect(monday.getAttribute('aria-checked')).toBe('false');
    monday.click();
    await t.settle();
    t.type('Closes at', '00:00', arena);
    await t.settle();
    const happy = t.pricing.hours.happy;
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.pricing.hours.open['1']).toEqual({ start: 600, end: 1440 });
    expect(t.pricing.hours.open['2']).toEqual({ start: 840, end: 1380 });
    expect(t.pricing.hours.happy).toEqual(happy);
    expect(t.snack()).toBe('Settings saved · the floor app updates on next refresh');
  });

  it('refuses a closing time before the opening time', async () => {
    t = await startPage('/settings?id=arena');
    const arena = t.doc().querySelector('app-arena-settings') as HTMLElement;
    t.type('Closes at', '13:00', arena);
    await t.settle();
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.text(arena.querySelector('[role="alert"]'))).toBe(
      'Tuesday: closing time must be after opening time',
    );
  });

  it('billing: payment switches save the floor options; the last method stays on', async () => {
    t = await startPage('/settings?id=billing');
    const billing = t.doc().querySelector('app-billing-settings') as HTMLElement;
    const rows = () => [...billing.querySelectorAll('app-toggle-row')];
    const labels = rows().map((r) => t.text(r.querySelector('span span')));
    expect(labels).toEqual([
      'Prices include GST',
      'Cash',
      'UPI',
      'Card',
      'Other',
      'Discount needs a reason',
    ]);
    const sw = (label: string) =>
      rows()
        .find((r) => t.text(r.querySelector('span span')) === label)!
        .querySelector('button') as HTMLButtonElement;
    expect(['Cash', 'UPI', 'Card', 'Other'].map((l) => sw(l).getAttribute('aria-checked'))).toEqual(
      ['true', 'true', 'true', 'true'],
    );
    for (const l of ['Cash', 'Card', 'Other']) {
      sw(l).click();
      await t.settle();
    }
    sw('UPI').click(); // the last one: refused
    await t.settle();
    expect(t.snack()).toBe('Keep at least one payment method on');
    expect(sw('UPI').getAttribute('aria-checked')).toBe('true');
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.floorOptions.writes).toEqual([
      { payment_methods: ['upi'], start_presets: [30, 60, 90, 120], warn_minutes: 5 },
    ]);
    // GST, invoices and discounts still await the owner's rules.
    expect(billing.querySelectorAll('app-not-connected').length).toBe(2);
  });

  it('sessions: time options and the warning save the floor options', async () => {
    t = await startPage('/settings?id=sessions');
    const sessions = t.doc().querySelector('app-session-settings') as HTMLElement;
    const chip = (label: string) =>
      [...sessions.querySelectorAll('mat-chip-option')].find((c) => t.text(c) === label)!;
    const selected = () =>
      [...sessions.querySelectorAll('mat-chip-option.mat-mdc-chip-selected')].map((c) => t.text(c));
    expect(selected()).toEqual(['30m', '1h', '1h 30m', '2h', '5 min']);
    (chip('15m').querySelector('button, .mdc-evolution-chip__action') as HTMLElement).click();
    (chip('2h').querySelector('button, .mdc-evolution-chip__action') as HTMLElement).click();
    (chip('10 min').querySelector('button, .mdc-evolution-chip__action') as HTMLElement).click();
    await t.settle();
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.floorOptions.writes.at(-1)).toEqual({
      payment_methods: ['cash', 'upi', 'card', 'other'],
      start_presets: [15, 30, 60, 90],
      warn_minutes: 10,
    });
    expect(t.snack()).toBe('Settings saved · the floor app updates on next refresh');
    expect(sessions.querySelector('app-not-connected')).toBeNull();
  });
});
