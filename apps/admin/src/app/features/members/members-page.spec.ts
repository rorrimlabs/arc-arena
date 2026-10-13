import { PageTest, startPage } from '../../testing/page-test';

describe('Members', () => {
  let t: PageTest;
  const detail = () => t.doc().querySelector('app-member-detail') as HTMLElement | null;
  const tiles = () =>
    [...detail()!.querySelectorAll('app-stat-tile')].map((e) =>
      [...e.querySelectorAll('span')].map((x) => t.text(x)).join(' '),
    );
  const search = async (q: string) => {
    const input = t.doc().querySelector('input[type="search"]') as HTMLInputElement;
    input.value = q;
    input.dispatchEvent(new Event('input'));
    await t.settle();
  };

  afterEach(() => t?.cleanup());

  it('lists members by latest visit with their 30-day spend', async () => {
    t = await startPage('/members');
    expect(
      t.rows().map((r) => [...t.rowText(r), t.text(r.querySelector('.tabular-nums'))]),
    ).toEqual([
      ['Kiran Rao', '3 visits · last today', '₹420'],
      ['Aditya Shah', '1 visit · last today', '₹0'],
      ['Meera Pillai', '1 visit · last today', '₹150'],
      ['Rahul Verma', '1 visit · last yesterday', '₹120'],
      ['Sana Khan', '0 visits · last —', '₹0'],
    ]);
    expect(t.text(t.doc().querySelector('app-list-pane-header p'))).toBe(
      '5 members · plans not connected yet',
    );
  });

  it('searches by name or phone digits', async () => {
    t = await startPage('/members');
    await search('9846');
    expect(t.rows().map((r) => t.rowText(r)[0])).toEqual(['Meera Pillai']);
    await search('rah');
    expect(t.rows().map((r) => t.rowText(r)[0])).toEqual(['Rahul Verma']);
    await search('zzz');
    expect(t.rows()).toEqual([]);
    expect(t.text(t.doc().querySelector('app-list-detail section'))).toContain('No members match.');
  });

  it('shows a member: masked phone, figures, favourite games and recent bills', async () => {
    t = await startPage('/members?id=c-kiran');
    expect(t.text(detail())).toContain('98••• ••873 · age 25');
    expect(t.text(detail())).not.toContain('9845012873');
    expect(tiles()).toEqual([
      'Visits · 90 days 3',
      'Hours played · 90 days 3h 5m',
      'Spent · 30 days ₹420',
      'Last visit Today',
    ]);
    const rows = [...detail()!.querySelectorAll('app-detail-row')].map((r) => t.text(r));
    expect(rows.slice(0, 2)).toEqual(['EA SPORTS FC 25 1h 35m', 'Mortal Kombat 1 1h 30m']);
    const bills = [...detail()!.querySelectorAll('app-line-row a')] as HTMLAnchorElement[];
    expect(bills.map((a) => t.text(a)?.split(' ')[0])).toEqual(['HEX', 'HEX', 'HEX', 'GHOST']);
    expect(t.text(bills[3])).toContain('Void');
    expect(bills[1].getAttribute('href')).toBe('/sales?id=b-1');
    expect(t.text(detail())).toContain('Age 25 · born 2001');
    expect(t.text(detail())).toContain('Membership plans aren');
  });
});
