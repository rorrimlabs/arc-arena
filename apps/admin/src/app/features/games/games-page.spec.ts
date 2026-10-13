import { PageTest, startPage } from '../../testing/page-test';

describe('Games', () => {
  let t: PageTest;
  const detail = () => t.doc().querySelector('app-game-detail') as HTMLElement | null;
  const tiles = () =>
    [...detail()!.querySelectorAll('app-stat-tile')].map((e) =>
      [...e.querySelectorAll('span')].map((x) => t.text(x)).join(' '),
    );

  afterEach(() => t?.cleanup());

  it('lists the catalog with 30-day play; hidden games say unavailable', async () => {
    t = await startPage('/games');
    expect(t.rows().map(t.rowText)).toEqual([
      ['Beat Saber', 'PSVR2 · 0m'],
      ['EA SPORTS FC 25', 'PS5 · 2h 35m', '3+'],
      ['Gran Turismo 7', 'PS5 · 1h'],
      ['Mortal Kombat 1', 'PS5 · unavailable · 1h 30m', '18+'],
      ['Tekken 8', 'PS5 · 1h 44m', '16+'],
    ]);
    expect([...t.doc().querySelectorAll('mat-chip-option')].map((c) => t.text(c))).toEqual([
      'All',
      'PS5',
      'PSVR2',
    ]);
  });

  it('searches and filters by platform', async () => {
    t = await startPage('/games?platform=PSVR2');
    expect(t.rows().map((r) => t.rowText(r)[0])).toEqual(['Beat Saber']);
    await t.harness.navigateByUrl('/games');
    await t.settle();
    const search = t.doc().querySelector('input[type="search"]') as HTMLInputElement;
    search.value = 'tek';
    search.dispatchEvent(new Event('input'));
    await t.settle();
    expect(t.rows().map((r) => t.rowText(r)[0])).toEqual(['Tekken 8']);
  });

  it('shows a game: figures, who plays it most, its age rating and media', async () => {
    t = await startPage('/games?id=g-fc');
    expect(tiles()).toEqual(['Hours · 30 days 3h', 'Sessions · 30 days 3', 'Playing now 1']);
    const fans = [...detail()!.querySelectorAll('app-line-row a')] as HTMLAnchorElement[];
    expect(fans.map((a) => t.text(a))).toEqual([
      'Kiran Rao 2 sessions 1h 35m',
      'Rahul Verma 1 session 1h',
    ]);
    expect(fans[0].getAttribute('href')).toBe('/members?id=c-kiran');
    expect(t.text(detail()!.querySelector('h2 + div'))).toContain('3+');
    expect(t.text(detail())).toContain('PS5 · Digital');
  });

  it('sets the age rating and media from the detail', async () => {
    t = await startPage('/games?id=g-gt');
    const [age, media] = [...detail()!.querySelectorAll('mat-select')] as HTMLElement[];
    expect(age.getAttribute('aria-disabled')).toBe('false');
    age.click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find((o) => t.text(o) === '12+') as HTMLElement
    ).click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      {
        kind: 'game.upsert',
        payload: expect.objectContaining({
          id: 'g-gt',
          name: 'Gran Turismo 7',
          ageRating: 12,
          media: null,
        }),
      },
    ]);
    expect(t.snack()).toBe('Gran Turismo 7 saved');
    expect(t.rowText(t.rows()[2])).toEqual(['Gran Turismo 7', 'PS5 · 1h', '12+']);
    media.click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find((o) => t.text(o) === 'Disc') as HTMLElement
    ).click();
    await t.settle();
    expect(t.floor.ops.at(-1)?.payload).toEqual(
      expect.objectContaining({ ageRating: 12, media: 'disc' }),
    );
  });

  it('hides a game from staff with the Available switch', async () => {
    t = await startPage('/games?id=g-gt');
    (detail()!.querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      { kind: 'game.set_active', payload: { id: 'g-gt', active: false } },
    ]);
    expect(t.rowText(t.rows()[2])).toEqual(['Gran Turismo 7', 'PS5 · unavailable · 1h']);
  });

  it('Remove hides the game after confirming', async () => {
    t = await startPage('/games?id=g-tekken');
    t.button('Remove', detail()!)!.click();
    await t.settle();
    t.button('Remove', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      { kind: 'game.set_active', payload: { id: 'g-tekken', active: false } },
    ]);
    expect(t.snack()).toBe('Tekken 8 removed');
  });

  it('adds a game, refusing a blank or taken title', async () => {
    t = await startPage('/games');
    t.button('Add')!.click();
    await t.settle();
    const add = () => t.button('Add', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    const alert = () => t.text(t.dialog()!.querySelector('[role="alert"]'));
    add();
    await t.settle();
    expect(alert()).toBe('Enter a title');
    t.type('Title', 'tekken 8', t.dialog()!);
    add();
    await t.settle();
    expect(alert()).toBe('tekken 8 is already in the list');
    t.type('Title', 'Hades II', t.dialog()!);
    add();
    await t.settle();
    expect(t.floor.ops).toEqual([
      {
        kind: 'game.upsert',
        payload: expect.objectContaining({
          name: 'Hades II',
          platforms: ['PS5'],
          active: true,
          ageRating: 3,
          media: 'digital',
        }),
      },
    ]);
    expect(t.snack()).toBe('Hades II added');
    expect(t.text(detail()!.querySelector('h2'))).toBe('Hades II');
  });
  const stationRows = () =>
    [...detail()!.querySelectorAll('app-game-stations mat-form-field')].map((f) => [
      t.text(f.parentElement!.querySelector('[id^="compat-"]')),
      t.text(f.querySelector('.mat-mdc-select-value')),
    ]);
  const warning = () => t.text(detail()!.querySelector('app-game-stations [role="note"]'));

  it('shows where a game is playable, station by station', async () => {
    t = await startPage('/games?id=g-gt');
    expect(stationRows()).toEqual([
      ['HEX', 'Not playable'],
      ['VOID', 'Not installed'],
      ['GHOST', 'Not installed'],
      ['RIFT', 'Playable'],
      ['NOVA', 'Not installed'],
      ['VR Bay', 'Not installed'],
    ]);
    expect(warning()).toBeUndefined();
  });

  it('marking a station Playable pushes game.set_compat for that pair', async () => {
    t = await startPage('/games?id=g-gt');
    const hex = detail()!.querySelectorAll('app-game-stations mat-select')[0] as HTMLElement;
    hex.click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find(
        (o) => t.text(o) === 'Playable',
      ) as HTMLElement
    ).click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      {
        kind: 'game.set_compat',
        payload: { game_id: 'g-gt', resource_id: 's-hex', status: 'playable', notes: null },
      },
    ]);
    expect(t.snack()).toBe('Gran Turismo 7 on HEX: Playable');
    expect(stationRows()[0]).toEqual(['HEX', 'Playable']);

    const rift = detail()!.querySelectorAll('app-game-stations mat-select')[3] as HTMLElement;
    rift.click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find(
        (o) => t.text(o) === 'Not installed',
      ) as HTMLElement
    ).click();
    await t.settle();
    expect(t.floor.ops.at(-1)).toEqual({
      kind: 'game.set_compat',
      payload: { game_id: 'g-gt', resource_id: 's-rift', status: 'not_installed', notes: null },
    });
  });

  it('warns when staff cannot start a game on any station', async () => {
    t = await startPage('/games?id=g-gt', 1440, ({ floor }) => {
      floor.compatList = floor.compatList.filter((c) => c.gameId !== 'g-gt');
    });
    expect(warning()).toContain("Staff can't start this game anywhere yet");
    expect(t.rowText(t.rows()[2])).toEqual(['Gran Turismo 7', 'PS5 · 1h', 'No station']);
    // Hidden games are not offered to staff, so they are not flagged.
    expect(t.rowText(t.rows()[3])).toEqual([
      'Mortal Kombat 1',
      'PS5 · unavailable · 1h 30m',
      '18+',
    ]);
  });

  it('adds a game playable on the stations picked, in one push', async () => {
    t = await startPage('/games');
    t.button('Add')!.click();
    await t.settle();
    t.type('Title', 'Hades II', t.dialog()!);
    const field = [...t.dialog()!.querySelectorAll('mat-form-field')].find(
      (f) => t.text(f.querySelector('mat-label')) === 'Playable on',
    )!;
    (field.querySelector('mat-select') as HTMLElement).click();
    await t.settle();
    const options = [...t.doc().querySelectorAll('mat-option')];
    expect(options.map((o) => t.text(o))).toEqual([
      'HEX',
      'VOID',
      'GHOST',
      'RIFT',
      'NOVA',
      'VR Bay',
    ]);
    for (const name of ['HEX', 'RIFT']) {
      (options.find((o) => t.text(o) === name) as HTMLElement).click();
      await t.settle();
    }
    t.button('Add', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();

    const id = (t.floor.ops[0]?.payload as { id: string }).id;
    expect(t.floor.ops).toEqual([
      { kind: 'game.upsert', payload: expect.objectContaining({ name: 'Hades II' }) },
      {
        kind: 'game.set_compat',
        payload: { game_id: id, resource_id: 's-hex', status: 'playable', notes: null },
      },
      {
        kind: 'game.set_compat',
        payload: { game_id: id, resource_id: 's-rift', status: 'playable', notes: null },
      },
    ]);
    expect(t.snack()).toBe('Hades II added · playable on 2 stations');
    expect(t.text(detail()!.querySelector('h2'))).toBe('Hades II');
    expect(warning()).toBeUndefined();
    expect(
      stationRows()
        .filter(([, s]) => s === 'Playable')
        .map(([n]) => n),
    ).toEqual(['HEX', 'RIFT']);
  });

  it('a game added without stations is never marked playable, and says so', async () => {
    t = await startPage('/games');
    t.button('Add')!.click();
    await t.settle();
    t.type('Title', 'Hades II', t.dialog()!);
    t.button('Add', t.dialog()!.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    expect(t.floor.ops.map((o) => o.kind)).toEqual(['game.upsert']);
    expect(warning()).toContain("Staff can't start this game anywhere yet");
    expect(stationRows().every(([, s]) => s === 'Not installed')).toBe(true);
  });
});
