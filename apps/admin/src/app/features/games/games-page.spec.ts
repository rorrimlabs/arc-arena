import { PageTest, startPage } from '../../testing/page-test';

/** The games library lives in Settings; a game opens in its place at `/settings/games/<id>`. */
const GAMES = '/settings/games';

describe('Games', () => {
  let t: PageTest;
  const detail = () => t.doc().querySelector('app-game-detail') as HTMLElement | null;
  /** The library table's rows (shown while no game is open). */
  const table = () => [...t.doc().querySelectorAll('app-games-library tbody tr')] as HTMLElement[];
  /** One row: title, platform, modes, players, age, 30-day play, status. */
  const cells = (r: HTMLElement) => [
    t.text(r.querySelector('th span:not(.icon)')),
    ...[...r.querySelectorAll('td')].map((c) => t.text(c)),
  ];
  const names = () => table().map((r) => cells(r)[0]);
  /** Back from a game to the library table. */
  async function toList() {
    t.button('All games', t.doc().querySelector('app-games-library')!)!.click();
    await t.settle();
  }
  const tiles = () =>
    [...detail()!.querySelectorAll('app-stat-tile')].map((e) =>
      [...e.querySelectorAll('span')].map((x) => t.text(x)).join(' '),
    );

  afterEach(() => t?.cleanup());

  it('lists the catalog with 30-day play; archived games say so and come last', async () => {
    // The old address still opens the library.
    t = await startPage('/games');
    expect(t.url()).toBe(GAMES);
    expect(table().map(cells)).toEqual([
      ['Beat Saber', 'PSVR2', 'Story · Local', '4', '—', '0m', 'Available'],
      ['EA SPORTS FC 25', 'PS5', 'Story · Local', '4', '3+', '2h 35m', 'Available'],
      ['Gran Turismo 7', 'PS5', 'Story · Local', '4', '—', '1h', 'Available'],
      ['Tekken 8', 'PS5', 'Story · Local', '4', '16+', '1h 44m', 'Available'],
      ['Mortal Kombat 1', 'PS5', 'Story · Local', '4', '18+', '1h 30m', 'Archived'],
    ]);
    expect([...t.doc().querySelectorAll('mat-chip-option')].map((c) => t.text(c))).toEqual([
      'All',
      'PS5',
      'PSVR2',
    ]);
  });

  it('searches and filters by platform', async () => {
    t = await startPage(`${GAMES}?platform=PSVR2`);
    expect(names()).toEqual(['Beat Saber']);
    await t.harness.navigateByUrl(GAMES);
    await t.settle();
    const search = t.doc().querySelector('input[type="search"]') as HTMLInputElement;
    search.value = 'tek';
    search.dispatchEvent(new Event('input'));
    await t.settle();
    expect(names()).toEqual(['Tekken 8']);
  });

  it('shows a game: figures, who plays it most, its age rating and media', async () => {
    t = await startPage(`${GAMES}/g-fc`);
    expect(tiles()).toEqual(['Hours · 30 days 3h', 'Sessions · 30 days 3', 'Playing now 1']);
    const fans = [...detail()!.querySelectorAll('app-line-row a')] as HTMLAnchorElement[];
    expect(fans.map((a) => t.text(a))).toEqual([
      'Kiran Rao 2 sessions 1h 35m',
      'Rahul Verma 1 session 1h',
    ]);
    // Members are searched on the server: the link opens the list on that member.
    expect(fans[0].getAttribute('href')).toBe('/members?q=Kiran%20Rao&id=c-kiran');
    expect(t.text(detail()!.querySelector('h3 + div'))).toContain('3+');
    expect(t.text(detail())).toContain('PS5 · Digital');
  });

  it('sets the age rating and media from the detail', async () => {
    t = await startPage(`${GAMES}/g-gt`);
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
    media.click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find((o) => t.text(o) === 'Disc') as HTMLElement
    ).click();
    await t.settle();
    expect(t.floor.ops.at(-1)?.payload).toEqual(
      expect.objectContaining({ ageRating: 12, media: 'disc' }),
    );
    await toList();
    expect(cells(table()[2])).toEqual([
      'Gran Turismo 7',
      'PS5',
      'Story · Local',
      '4',
      '12+',
      '1h',
      'Available',
    ]);
  });

  it('a refused age rating puts the select back to what the server holds', async () => {
    t = await startPage(`${GAMES}/g-gt`);
    const [age] = [...detail()!.querySelectorAll('mat-select')] as HTMLElement[];
    t.floor.failNext = 'forbidden';
    age.click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find((o) => t.text(o) === '12+') as HTMLElement
    ).click();
    await t.settle();
    expect(t.floor.ops).toEqual([]);
    expect(t.text(detail()!.querySelector('[role="alert"]'))).toBe(
      'You need the Settings permission for that',
    );
    expect(t.text(age.querySelector('.mat-mdc-select-value'))).toBe('Not set');
  });

  it('archives a game with the Available switch; it stays in the list, last', async () => {
    t = await startPage(`${GAMES}/g-gt`);
    (detail()!.querySelector('mat-slide-toggle button') as HTMLButtonElement).click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      { kind: 'game.set_active', payload: { id: 'g-gt', active: false } },
    ]);
    expect(t.text(detail()!.querySelector('h3 + div'))).toContain('Archived');
    await toList();
    expect(cells(table()[3])).toEqual([
      'Gran Turismo 7',
      'PS5',
      'Story · Local',
      '4',
      '—',
      '1h',
      'Archived',
    ]);
  });

  const dialogButton = (label: string) =>
    t.button(label, t.dialog()!.querySelector('mat-dialog-actions')!);

  it('deletes a game nothing ever used, after confirming, on the server first', async () => {
    t = await startPage(`${GAMES}/g-beat`);
    t.button('Delete', detail()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('h2'))).toBe('Delete Beat Saber permanently?');
    expect(t.text(t.dialog()!)).toContain('It cannot be undone');
    expect(t.floor.ops).toEqual([]);
    dialogButton('Delete')!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([{ kind: 'game.delete', payload: { id: 'g-beat' } }]);
    expect(t.snack()).toBe('Beat Saber deleted');
    expect(t.url()).toBe(GAMES);
    expect(names()).not.toContain('Beat Saber');
    expect(t.text(detail()?.querySelector('h3') ?? null)).not.toBe('Beat Saber');
  });

  it('a game played before cannot be deleted: it explains why and offers to archive', async () => {
    t = await startPage(`${GAMES}/g-gt`);
    t.button('Delete', detail()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('h2'))).toBe("Gran Turismo 7 can't be deleted");
    expect(t.text(t.dialog()!)).toContain('1 past session or booking use it');
    expect(dialogButton('Delete')).toBeUndefined();
    dialogButton('Archive')!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      { kind: 'game.set_active', payload: { id: 'g-gt', active: false } },
    ]);
    expect(t.snack()).toBe('Gran Turismo 7 archived');
  });

  it('a game being played now cannot be deleted; archiving keeps those sessions running', async () => {
    t = await startPage(`${GAMES}/g-tekken`);
    t.button('Delete', detail()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('It is being played on the floor right now');
    expect(t.text(t.dialog()!)).toContain('those sessions continue');
    dialogButton('Archive')!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      { kind: 'game.set_active', payload: { id: 'g-tekken', active: false } },
    ]);
  });

  it('an archived game with history can only be explained, not deleted again', async () => {
    t = await startPage(`${GAMES}/g-mk`);
    t.button('Delete', detail()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!)).toContain('It is already archived');
    expect(dialogButton('Archive')).toBeUndefined();
    dialogButton('Close')!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([]);
  });

  it('a booking made between the check and the delete: the server refuses, nothing is lost', async () => {
    t = await startPage(`${GAMES}/g-beat`);
    t.button('Delete', detail()!)!.click();
    await t.settle();
    t.floor.bookingsByGame.set('g-beat', 1);
    dialogButton('Delete')!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([]);
    expect(t.text(detail()!.querySelector('[role="alert"]'))).toContain(
      'Sessions or bookings already use it',
    );
    await toList();
    expect(names()).toContain('Beat Saber');
  });

  it('edits a game: title, platforms, player mode and players per station', async () => {
    t = await startPage(`${GAMES}/g-gt`);
    t.button('Edit', detail()!)!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('h2'))).toBe('Edit Gran Turismo 7');
    t.type('Title', 'tekken 8', t.dialog()!);
    dialogButton('Save')!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('[role="alert"]'))).toBe(
      'tekken 8 is already in the list',
    );
    t.type('Title', 'Gran Turismo 7 Spec II', t.dialog()!);
    const select = (label: string) =>
      [...t.dialog()!.querySelectorAll('mat-form-field')]
        .find((f) => t.text(f.querySelector('mat-label')) === label)!
        .querySelector('mat-select') as HTMLElement;
    // Play modes are several: keep Local multiplayer only (it starts with Story mode too).
    select('Play modes').click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find(
        (o) => t.text(o) === 'Story mode',
      ) as HTMLElement
    ).click();
    await t.settle();
    ([...t.doc().querySelectorAll('.cdk-overlay-backdrop')].at(-1) as HTMLElement).click();
    await t.settle();
    select('Players per station').click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find((o) => t.text(o) === '4') as HTMLElement
    ).click();
    await t.settle();
    dialogButton('Save')!.click();
    await t.settle();
    expect(t.floor.ops).toEqual([
      {
        kind: 'game.upsert',
        payload: expect.objectContaining({
          id: 'g-gt',
          name: 'Gran Turismo 7 Spec II',
          platforms: ['PS5'],
          playModes: ['local'],
          maxLocalPlayers: 4,
          active: true,
          baseActive: true,
        }),
      },
    ]);
    expect(t.snack()).toBe('Gran Turismo 7 Spec II saved');
    expect(t.text(detail()!.querySelector('h3'))).toBe('Gran Turismo 7 Spec II');
  });

  it('an edit over an archive made elsewhere is refused, not applied', async () => {
    t = await startPage(`${GAMES}/g-gt`);
    t.button('Edit', detail()!)!.click();
    await t.settle();
    // Another owner archives it while this dialog is open.
    const i = t.floor.gameList.findIndex((g) => g.id === 'g-gt');
    t.floor.gameList[i] = { ...t.floor.gameList[i], active: false };
    t.type('Title', 'GT7', t.dialog()!);
    dialogButton('Save')!.click();
    await t.settle();
    expect(t.text(t.dialog()!.querySelector('[role="alert"]'))).toBe(
      'It was archived or restored elsewhere meanwhile. Check it and save again',
    );
    expect(t.floor.ops).toEqual([]);
    expect(t.floor.gameList[i].active).toBe(false);
  });

  it('adds a game, refusing a blank or taken title', async () => {
    t = await startPage(GAMES);
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
          playModes: ['single'],
          maxLocalPlayers: 1,
          active: true,
          ageRating: 3,
          media: 'digital',
        }),
      },
    ]);
    expect(t.snack()).toBe('Hades II added');
    expect(t.text(detail()!.querySelector('h3'))).toBe('Hades II');
  });
  const stationRows = () =>
    [...detail()!.querySelectorAll('app-game-stations mat-form-field')].map((f) => [
      t.text(f.parentElement!.querySelector('[id^="compat-"]')),
      t.text(f.querySelector('.mat-mdc-select-value')),
    ]);
  const warning = () => t.text(detail()!.querySelector('app-game-stations [role="note"]'));

  it('shows where a game is playable, station by station', async () => {
    t = await startPage(`${GAMES}/g-gt`);
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
    t = await startPage(`${GAMES}/g-gt`);
    const hex = detail()!.querySelectorAll('app-game-stations mat-select')[0] as HTMLElement;
    hex.click();
    await t.settle();
    (
      [...t.doc().querySelectorAll('mat-option')].find(
        (o) => t.text(o) === 'Playable',
      ) as HTMLElement
    ).click();
    await t.settle();
    // No notes key: the server keeps the note staff wrote on the floor app.
    expect(t.floor.ops).toEqual([
      {
        kind: 'game.set_compat',
        payload: { game_id: 'g-gt', resource_id: 's-hex', status: 'playable' },
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
      payload: { game_id: 'g-gt', resource_id: 's-rift', status: 'not_installed' },
    });
  });

  it('warns when staff cannot start a game on any station', async () => {
    t = await startPage(`${GAMES}/g-gt`, 1440, ({ floor }) => {
      floor.compatList = floor.compatList.filter((c) => c.gameId !== 'g-gt');
    });
    expect(warning()).toContain("Staff can't start this game anywhere yet");
    await toList();
    expect(cells(table()[2])).toEqual([
      'Gran Turismo 7',
      'PS5',
      'Story · Local',
      '4',
      '—',
      '1h',
      'No station',
    ]);
    // Archived games are not offered to staff, so they are not flagged.
    expect(cells(table()[4])).toEqual([
      'Mortal Kombat 1',
      'PS5',
      'Story · Local',
      '4',
      '18+',
      '1h 30m',
      'Archived',
    ]);
  });

  it('adds a game playable on the stations picked, in one push', async () => {
    t = await startPage(GAMES);
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
        payload: { game_id: id, resource_id: 's-hex', status: 'playable' },
      },
      {
        kind: 'game.set_compat',
        payload: { game_id: id, resource_id: 's-rift', status: 'playable' },
      },
    ]);
    expect(t.snack()).toBe('Hades II added · playable on 2 stations');
    expect(t.text(detail()!.querySelector('h3'))).toBe('Hades II');
    expect(warning()).toBeUndefined();
    expect(
      stationRows()
        .filter(([, s]) => s === 'Playable')
        .map(([n]) => n),
    ).toEqual(['HEX', 'RIFT']);
  });

  it('a game added without stations is never marked playable, and says so', async () => {
    t = await startPage(GAMES);
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
