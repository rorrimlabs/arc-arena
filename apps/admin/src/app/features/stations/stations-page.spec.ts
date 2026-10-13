import { PageTest, startPage } from '../../testing/page-test';

describe('Stations', () => {
  let t: PageTest;
  const detail = () => t.doc().querySelector('app-station-detail') as HTMLElement | null;
  const tiles = () =>
    [...detail()!.querySelectorAll('app-stat-tile')].map((e) =>
      [...e.querySelectorAll('span')].map((x) => t.text(x)).join(' '),
    );
  const chips = () => [...t.doc().querySelectorAll('mat-chip-option')].map((c) => t.text(c));

  afterEach(() => t?.cleanup());

  it('lists stations with what is on now; removed ones are left out', async () => {
    t = await startPage('/stations');
    expect(t.rows().map(t.rowText)).toEqual([
      ['HEX', 'EA SPORTS FC 25 · 25m left', 'Playing'],
      ['VOID', 'Tekken 8 · 8m left', 'Playing'],
      ['GHOST', 'PlayStation 5', 'Free'],
      ['RIFT', 'PlayStation 5, VR', 'Free'],
      ['NOVA', 'PlayStation 5', 'Out of service'],
      ['VR Bay', 'VR', 'Free'],
    ]);
    expect(chips()).toEqual(['All 6', 'PlayStation 5 5', 'VR 2']);
  });

  it('still lists stations when the price list fails, and says why', async () => {
    t = await startPage('/stations?id=s-hex', 1440, (apis) => {
      apis.pricing.failNext = 'function_missing';
    });
    expect(t.text(t.doc().querySelector('[role="alert"]'))).toBe(
      "Type names and prices couldn't load: function_missing",
    );
    expect(t.rows().map((r) => t.rowText(r)[0])).toEqual([
      'HEX',
      'VOID',
      'GHOST',
      'RIFT',
      'NOVA',
      'VR Bay',
    ]);
    expect([...t.doc().querySelectorAll('mat-chip-option')].map((c) => t.text(c))).toEqual([
      'All 6',
      'PS5 5',
      'VR 2',
    ]);
    expect(t.text(detail())).toContain("PS5 · price couldn't load");
    expect(t.text(detail())).not.toContain('no price yet');
  });

  it('filters by type from the URL', async () => {
    t = await startPage('/stations?type=VR');
    expect(t.rows().map((r) => t.rowText(r)[0])).toEqual(['RIFT', 'VR Bay']);
  });

  it('shows a station: figures, now playing and recent bills linked to Sales', async () => {
    t = await startPage('/stations?id=s-hex');
    expect(t.text(detail()!.querySelector('h2'))).toBe('HEX');
    expect(t.text(detail())).toContain('PlayStation 5 · ₹150 / hr');
    expect(tiles()).toEqual([
      'Takings today ₹240',
      'Sessions today 2',
      'Hours · 30 days 3h',
      'Takings · 30 days ₹420',
    ]);
    expect(t.text(detail())).toContain('Now playing');
    expect(t.text(detail())).toContain('Time left 25 min');
    const bills = [...detail()!.querySelectorAll('app-line-row a')] as HTMLAnchorElement[];
    expect(bills.map((a) => t.text(a))).toEqual([
      expect.stringContaining('Kiran Rao'),
      expect.stringContaining('Kiran Rao'),
      expect.stringContaining('Kiran Rao'),
    ]);
    expect(bills[0].getAttribute('href')).toBe('/sales?id=b-live-hex');
    expect(t.text(bills[1])).toContain('₹240');
  });

  it('adds a station with the next free name', async () => {
    t = await startPage('/stations');
    t.button('Add')!.click();
    await t.settle();
    expect(t.text(t.dialog())).toContain('Charged at ₹150 an hour.');
    t.button('Add', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    expect(t.floor.ops.at(-1)).toEqual({
      kind: 'resource.upsert',
      payload: expect.objectContaining({
        name: 'PS5-7',
        activityCodes: ['PS5'],
        status: 'available',
      }),
    });
    expect(t.snack()).toBe('PS5-7 added');
    expect(t.text(t.doc().querySelector('app-station-detail h2'))).toBe('PS5-7');
  });

  it('refuses a station name that is taken', async () => {
    t = await startPage('/stations');
    t.button('Add')!.click();
    await t.settle();
    t.type('Name', 'hex', t.dialog()!);
    t.button('Add', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('[role="alert"]'))).toBe('hex already exists');
    expect(t.floor.ops).toEqual([]);
  });

  it('a station with two types keeps both when renamed', async () => {
    t = await startPage('/stations?id=s-rift');
    expect(t.text(detail()!.querySelector('mat-select'))).toContain('PlayStation 5, VR');
    t.type('Name', 'RIFT 2', detail()!);
    await t.settle();
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      {
        kind: 'resource.upsert',
        payload: expect.objectContaining({ name: 'RIFT 2', activityCodes: ['PS5', 'VR'] }),
      },
    ]);
  });

  it('renames from the unsaved-changes bar', async () => {
    t = await startPage('/stations?id=s-ghost');
    t.type('Name', 'SPECTRE', detail()!);
    await t.settle();
    t.button('Save', t.doc().querySelector('app-unsaved-bar')!)!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      {
        kind: 'resource.upsert',
        payload: expect.objectContaining({ id: 's-ghost', name: 'SPECTRE', status: 'available' }),
      },
    ]);
    expect(t.snack()).toBe('Station saved');
  });

  it('takes a free station out of service, but not one with a live session', async () => {
    t = await startPage('/stations?id=s-hex');
    (detail()!.querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
    await t.settle();
    expect(t.snack()).toBe('HEX has a live session · end it on the floor first');
    expect(t.floor.ops).toEqual([]);

    await t.harness.navigateByUrl('/stations?id=s-ghost');
    await t.settle();
    (detail()!.querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      { kind: 'resource.set_status', payload: { id: 's-ghost', status: 'maintenance' } },
    ]);
    expect(t.snack()).toBe('GHOST taken out of service');
  });

  it('removes a free station after confirming (it stays in past bills)', async () => {
    t = await startPage('/stations?id=s-rift');
    t.button('Remove', detail()!)!.click();
    await t.settle();
    expect(t.text(t.dialog())).toContain('Remove RIFT?');
    t.button('Remove', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      { kind: 'resource.set_status', payload: { id: 's-rift', status: 'disabled' } },
    ]);
    expect(t.rows().map((r) => t.rowText(r)[0])).not.toContain('RIFT');
  });

  it('will not remove a station with a live session', async () => {
    t = await startPage('/stations?id=s-void');
    t.button('Remove', detail()!)!.click();
    await t.settle();
    expect(t.dialog()).toBeNull();
    expect(t.snack()).toBe('VOID has a live session · end it first');
  });

  it('narrow: the station opens over the list', async () => {
    t = await startPage('/stations', 1024);
    expect(detail()).toBeNull();
    t.rows()[2].click();
    await t.settle();
    expect(t.doc().querySelector('[role="dialog"][aria-label="Station"]')).not.toBeNull();
    expect(t.url()).toBe('/stations?id=s-ghost');
  });
});
