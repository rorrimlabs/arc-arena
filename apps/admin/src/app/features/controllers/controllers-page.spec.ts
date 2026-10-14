import { PageTest, startPage } from '../../testing/page-test';
import { Controller, applyChange, nextLabel } from './data/controller.models';

describe('Controllers', () => {
  let t: PageTest;
  const detail = () => t.doc().querySelector('app-controller-detail') as HTMLElement | null;
  const headings = () =>
    [...t.doc().querySelectorAll('section[aria-labelledby^="pads-"] h2')].map((h) => t.text(h));
  const field = (label: string, scope: ParentNode) =>
    [...scope.querySelectorAll('mat-form-field')].find(
      (f) => t.text(f.querySelector('mat-label')) === label,
    );
  const bar = () => t.doc().querySelector('app-unsaved-bar') as HTMLElement | null;
  const input = (label: string, scope: ParentNode) =>
    field(label, scope)?.querySelector('input') as HTMLInputElement;

  /** Opens the mat-select labelled `label` inside `scope` and picks the option `option`. */
  async function pick(label: string, option: string, scope: ParentNode) {
    (field(label, scope)?.querySelector('.mat-mdc-select-trigger') as HTMLElement).click();
    await t.settle();
    const opt = [...t.doc().querySelectorAll('mat-option')].find((o) => t.text(o) === option);
    (opt as HTMLElement).click();
    await t.settle();
  }

  afterEach(() => t?.cleanup());

  it('lists pads under the station they are at; a lent one says where it belongs', async () => {
    t = await startPage('/controllers');
    expect(headings()).toEqual([
      'HEX · 1 of 1 usable',
      'VOID · 2 of 3 usable',
      'GHOST · 0 of 1 usable',
      'RIFT · 1 of 1 usable',
    ]);
    expect(t.rows().map(t.rowText)).toEqual([
      ['HEX-1', 'At home', 'Usable'],
      ['HEX-2', 'Belongs to HEX · on loan', 'Usable'],
      ['VOID-1', 'At home', 'Usable'],
      ['VOID-2', 'Left stick drift', 'Faulty'],
      ['GHOST-1', 'At home', 'Missing'],
      ['RIFT-1', 'At home', 'Usable'],
    ]);
    // Wide screen: the first pad is shown.
    expect(t.text(detail()?.querySelector('h2'))).toBe('HEX-1');
  });

  it('shows where a lent pad is and where it goes back to', async () => {
    t = await startPage('/controllers?id=c-hex-2');
    expect(t.text(detail()!.querySelector('h2 + div'))).toBe('Usable At VOID · belongs to HEX');
    const rows = [...detail()!.querySelectorAll('app-detail-row')].map((r) => t.text(r));
    expect(rows).toEqual([
      'Now at VOID',
      'Home HEX',
      'On loan Goes back to HEX when the session ends',
    ]);
  });

  it('a new arena with stations and no pads says what to do', async () => {
    t = await startPage('/controllers', 1440, (apis) => {
      apis.controllers.list = [];
    });
    expect(t.text(t.doc().querySelector('app-list-detail'))).toContain(
      'No controllers yet. Add each pad with the label written on it',
    );
    expect(detail()).toBeNull();
  });

  it('a status change alone is a controller.set_status with its note', async () => {
    t = await startPage('/controllers?id=c-void-1');
    await pick('Status', 'Faulty', detail()!);
    t.type('Note', '  Button sticks ', detail()!);
    await t.settle();
    expect(t.text(field('Status', detail()!)?.querySelector('mat-hint'))).toBe(
      'Broken: no session can use it and no station can borrow it',
    );
    t.button('Save', bar()!)!.click();
    await t.settle();
    await t.settle();
    expect(t.controllers.ops).toEqual([
      {
        kind: 'controller.set_status',
        payload: { id: 'c-void-1', status: 'faulty', notes: 'Button sticks' },
      },
    ]);
    expect(t.snack()).toBe('VOID-1 saved');
    expect(bar()).toBeNull();
    expect(t.rowText(t.rows()[2])).toEqual(['VOID-1', 'Button sticks', 'Faulty']);
  });

  it('a rename is built on a fresh read: a move made on the floor meanwhile is kept', async () => {
    t = await startPage('/controllers?id=c-hex-1');
    // Another device lends HEX-1 to GHOST after the screen loaded.
    t.controllers.list = t.controllers.list.map((c) =>
      c.id === 'c-hex-1'
        ? { ...c, currentId: 's-ghost', loanReturnTo: 's-hex', loanSessionRef: 's:b-9' }
        : c,
    );
    t.type('Label', 'HEX-A', detail()!);
    await t.settle();
    t.button('Save', bar()!)!.click();
    await t.settle();
    await t.settle();
    expect(t.controllers.ops).toEqual([
      {
        kind: 'controller.upsert',
        payload: {
          id: 'c-hex-1',
          label: 'HEX-A',
          home_resource_id: 's-hex',
          current_resource_id: 's-ghost',
          status: 'usable',
          notes: null,
          loan_return_to: 's-hex',
          loan_session_ref: 's:b-9',
        },
      },
    ]);
    expect(t.snack()).toBe('HEX-A saved');
  });

  it('re-homing a lent pad onto the station it stands at settles the loan', async () => {
    t = await startPage('/controllers?id=c-hex-2');
    await pick('Home station', 'VOID', detail()!);
    t.button('Save', bar()!)!.click();
    await t.settle();
    await t.settle();
    expect(t.controllers.ops.at(-1)).toEqual({
      kind: 'controller.upsert',
      payload: {
        id: 'c-hex-2',
        label: 'HEX-2',
        home_resource_id: 's-void',
        current_resource_id: 's-void',
        status: 'usable',
        notes: null,
        loan_return_to: null,
        loan_session_ref: null,
      },
    });
    expect(t.rowText(t.rows()[1])).toEqual(['HEX-2', 'At home', 'Usable']);
  });

  it('refuses a label another pad has (any case), and discard puts the saved values back', async () => {
    t = await startPage('/controllers?id=c-hex-1');
    t.type('Label', 'void-2', detail()!);
    await t.settle();
    t.button('Save', bar()!)!.click();
    await t.settle();
    expect(t.text(detail()!.querySelector('[role="alert"]'))).toBe(
      'A controller is already labelled void-2',
    );
    expect(t.controllers.ops).toEqual([]);
    t.button('Discard', bar()!)!.click();
    await t.settle();
    expect(input('Label', detail()!).value).toBe('HEX-1');
    expect(bar()).toBeNull();
  });

  it('a refusal is shown and nothing is reported saved', async () => {
    t = await startPage('/controllers?id=c-void-1');
    await pick('Status', 'Retired', detail()!);
    t.controllers.failNext = 'forbidden';
    t.button('Save', bar()!)!.click();
    await t.settle();
    expect(t.text(detail()!.querySelector('[role="alert"]'))).toBe('forbidden');
    expect(bar()).not.toBeNull();
  });

  it('adds a pad to a station with the next free label, then opens it', async () => {
    t = await startPage('/controllers?id=c-void-1');
    t.button('Add')!.click();
    await t.settle();
    const dialog = t.dialog()!;
    // The station of the pad on screen is picked; a blank label becomes the next free one.
    expect(input('Label', dialog).placeholder).toBe('VOID-3');
    await pick('Station', 'GHOST', dialog);
    expect(input('Label', dialog).placeholder).toBe('GHOST-2');
    t.button('Add', dialog.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    await t.settle();
    expect(t.dialog()).toBeNull();
    expect(t.snack()).toBe('GHOST-2 added to GHOST');
    const added = t.controllers.list.at(-1)!;
    expect(added).toMatchObject({
      label: 'GHOST-2',
      homeId: 's-ghost',
      currentId: 's-ghost',
      status: 'usable',
    });
    expect(t.url()).toBe(`/controllers?id=${added.id}`);
    expect(t.text(detail()?.querySelector('h2'))).toBe('GHOST-2');
  });

  it('the add dialog refuses a label already in use', async () => {
    t = await startPage('/controllers');
    t.button('Add')!.click();
    await t.settle();
    const dialog = t.dialog()!;
    t.type('Label', 'Hex-1', dialog);
    await t.settle();
    t.button('Add', dialog.querySelector('mat-dialog-actions')!)!.click();
    await t.settle();
    expect(t.text(dialog.querySelector('[role="alert"]'))).toBe(
      'A controller is already labelled Hex-1',
    );
    expect(t.controllers.ops).toEqual([]);
  });

  it('a member without the Settings permission sees the pads but cannot add or save', async () => {
    t = await startPage('/controllers?id=c-hex-1', 1440, (apis) => {
      apis.arena.memberships = apis.arena.memberships.map((m) => ({
        ...m,
        role: 'staff',
        perms: ['money', 'reports'],
      }));
    });
    expect(t.rows().length).toBe(6);
    expect(t.button('Add')!.disabled).toBe(true);
    t.type('Label', 'HEX-Z', detail()!);
    await t.settle();
    expect(t.text(bar())).toContain('Saving needs the Settings permission');
    expect(t.button('Save', bar()!)!.disabled).toBe(true);
  });
});

describe('controller helpers', () => {
  const pad: Controller = {
    id: 'p',
    label: 'HEX-2',
    homeId: 'hex',
    currentId: 'void',
    status: 'usable',
    notes: null,
    loanReturnTo: 'hex',
    loanSessionRef: 's:1',
  };

  it('a new home elsewhere keeps the loan, now owed to the new home', () => {
    expect(applyChange(pad, { homeId: 'ghost' })).toMatchObject({
      homeId: 'ghost',
      currentId: 'void',
      loanReturnTo: 'ghost',
      loanSessionRef: 's:1',
    });
  });

  it('a new home where it stands settles the loan', () => {
    expect(applyChange(pad, { homeId: 'void' })).toMatchObject({
      homeId: 'void',
      loanReturnTo: null,
      loanSessionRef: null,
    });
  });

  it('a rename changes nothing else; a pad not on loan gets no loan on re-homing', () => {
    expect(applyChange(pad, { label: 'X' })).toEqual({ ...pad, label: 'X' });
    const home = { ...pad, currentId: 'hex', loanReturnTo: null, loanSessionRef: null };
    expect(applyChange(home, { homeId: 'ghost' })).toMatchObject({
      homeId: 'ghost',
      currentId: 'hex',
      loanReturnTo: null,
    });
  });

  it('suggests the next free label for a station, skipping labels in use', () => {
    // One pad belongs to HEX (so HEX-2 is next), but HEX-2 is taken: HEX-3.
    expect(
      nextLabel('HEX', 'hex', [pad, { ...pad, id: 'q', label: 'HEX-1', homeId: 'void' }]),
    ).toBe('HEX-3');
  });
});
