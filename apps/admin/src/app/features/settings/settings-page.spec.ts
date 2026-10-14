import { PageTest, startPage } from '../../testing/page-test';

describe('Settings', () => {
  let t: PageTest;

  afterEach(() => t?.cleanup());

  it('lists the groups and opens Arena on a wide screen', async () => {
    t = await startPage('/settings');
    expect(t.rows().map(t.rowText)).toEqual([
      ['Arena', 'Name, area, hours'],
      ['Billing', 'GST, invoices, payment, discounts'],
      ['Billing rules', 'Rounding, grace, minimum charge'],
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

  describe('billing rules', () => {
    const rules = () => t.doc().querySelector('app-billing-rules') as HTMLElement;
    const bar = () => t.doc().querySelector('app-unsaved-bar') as HTMLElement | null;
    /** Each select's label and shown value. */
    const values = () =>
      [...rules().querySelectorAll('mat-form-field')].map(
        (f) =>
          `${t.text(f.querySelector('mat-label'))}: ${t.text(f.querySelector('.mat-mdc-select-value'))}`,
      );
    async function pick(label: string, option: string) {
      const field = [...rules().querySelectorAll('mat-form-field')].find(
        (f) => t.text(f.querySelector('mat-label')) === label,
      );
      (field!.querySelector('.mat-mdc-select-trigger') as HTMLElement).click();
      await t.settle();
      const opt = [...t.doc().querySelectorAll('mat-option')].find((o) => t.text(o) === option);
      (opt as HTMLElement).click();
      await t.settle();
    }

    it('shows the arena’s rules (the defaults until it saves its own)', async () => {
      t = await startPage('/settings?id=rules');
      expect(t.text(rules().querySelector('h2'))).toBe('Billing rules');
      expect(t.text(rules().querySelector('h2 + div'))).toBe(
        'Per minute (exact) · bills rounded to nearest ₹1',
      );
      expect(values()).toEqual([
        'Charge partial time: Per minute (exact)',
        'Grace period: None',
        'Minimum charge: None',
        'If they leave early: Bill the time actually played',
        'Round the final bill to: ₹1',
        'Rounding direction: To the nearest',
        'Round once or per segment: Once, on the session total',
        'Part-used block: Charge the whole block',
        'Group across several systems: Each system billed for its own controllers',
        'Cleaning gap between sessions: None',
      ]);
      expect(bar()).toBeNull();
    });

    it('saves the whole policy with policy.save; block rounding shows for blocks only', async () => {
      t = await startPage('/settings?id=rules');
      await pick('Charge partial time', 'In 15-minute blocks');
      expect(values()[1]).toBe('Block rounding: Always round up');
      await pick('Block rounding', 'Round to nearest');
      await pick('Grace period', '5 min');
      await pick('Round the final bill to', '₹10');
      await pick('Group across several systems', 'Pay once for the controllers bought');
      (rules().querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
      await t.settle();
      t.button('Save', bar()!)!.click();
      await t.settle();
      await t.settle();
      expect(t.snack()).toBe('Billing rules saved · new sessions use them');
      expect(t.pricing.ops).toEqual([
        {
          kind: 'policy.save',
          payload: {
            policy: {
              billing_unit: 'block_15',
              block_rounding: 'nearest',
              grace_minutes: 5,
              minimum_charge_minutes: 0,
              early_exit: 'actual',
              rounding_scope: 'session',
              late_arrival: 'actual',
              vr_unit_rounding: 'up',
              money_rounding_paise: 1000,
              money_rounding_dir: 'nearest',
              payment_timing: 'either',
              allow_extend_past_close: true,
              cleaning_gap_minutes: 0,
              group_billing_mode: 'shared_controller_pool',
            },
          },
        },
      ]);
      expect(bar()).toBeNull();
      expect(values()[0]).toBe('Charge partial time: In 15-minute blocks');
    });

    it('keeps rules the editor does not offer, and shows a saved value outside the choices', async () => {
      t = await startPage('/settings?id=rules', 1440, (apis) => {
        apis.pricing.policy = {
          ...apis.pricing.policy,
          lateArrival: 'planned',
          paymentTiming: 'end',
          graceMinutes: 7,
        };
      });
      expect(values()[1]).toBe('Grace period: 7 min');
      await pick('Minimum charge', '10 min');
      t.button('Save', bar()!)!.click();
      await t.settle();
      const policy = (t.pricing.ops[0].payload as { policy: Record<string, unknown> }).policy;
      expect(policy).toMatchObject({
        late_arrival: 'planned',
        payment_timing: 'end',
        grace_minutes: 7,
        minimum_charge_minutes: 10,
      });
    });

    it('discard puts the saved rules back; a refusal keeps the draft', async () => {
      t = await startPage('/settings?id=rules');
      await pick('If they leave early', 'Bill the full booked duration');
      t.pricing.failNext = 'forbidden';
      t.button('Save', bar()!)!.click();
      await t.settle();
      expect(t.text(rules().querySelector('[role="alert"]'))).toBe(
        'You need the Settings permission for that',
      );
      expect(bar()).not.toBeNull();
      t.button('Discard', bar()!)!.click();
      await t.settle();
      expect(values()[3]).toBe('If they leave early: Bill the time actually played');
      expect(bar()).toBeNull();
      expect(t.pricing.ops).toEqual([]);
    });
  });
});
