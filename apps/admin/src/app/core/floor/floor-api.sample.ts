import { istDayStart } from '../../shared/time/ist';
import { AppError } from '../auth/auth-api';
import { FLOOR_MESSAGES, FloorApi, compatOps } from './floor-api';
import {
  Charge,
  CompatStatus,
  Customer,
  Game,
  GameCompat,
  GameInput,
  Play,
  Station,
  StationInput,
  StationStatus,
  Visit,
} from './floor.models';

function station(id: string, name: string, codes: string[], o: Partial<Station> = {}): Station {
  return {
    id,
    name,
    kind: 'station',
    status: 'available',
    sortOrder: 0,
    activityCodes: codes,
    ...o,
  };
}

function game(
  id: string,
  name: string,
  platforms: string[],
  active = true,
  ageRating: Game['ageRating'] = null,
  media: Game['media'] = null,
): Game {
  return {
    id,
    name,
    aliases: [],
    categoryId: null,
    platforms,
    playerMode: 'local',
    maxLocalPlayers: 4,
    active,
    ageRating,
    media,
  };
}

/**
 * A deterministic floor for tests, lined up with SampleSalesApi (station and member names) and
 * SamplePricingApi (type codes): HEX and VOID are playing, NOVA is out of service, PS4 is removed.
 * Changes are applied in memory like the server would and recorded in `ops`.
 */
export class SampleFloorApi extends FloorApi {
  stationList: Station[];
  gameList: Game[];
  /** Where each game is playable; every sample game is playable on at least one station. */
  compatList: GameCompat[];
  customerList: Customer[];
  playList: Play[];
  visitList: Visit[];
  chargeList: Charge[];
  /** Every write, in order, as `kind` + payload. */
  readonly ops: { kind: string; payload: unknown }[] = [];
  /** Set to make the next call fail with this code. */
  failNext: string | null = null;

  constructor(now: Date) {
    super();
    /** An instant `daysAgo` IST days back at hh:mm IST. */
    const at = (daysAgo: number, hhmm: string) => {
      const [h, m] = hhmm.split(':').map(Number);
      return new Date(istDayStart(now, daysAgo).getTime() + (h * 60 + m) * 60_000).toISOString();
    };
    const inMin = (m: number) => new Date(now.getTime() + m * 60_000).toISOString();

    this.stationList = [
      station('s-hex', 'HEX', ['PS5'], { sortOrder: 0 }),
      station('s-void', 'VOID', ['PS5'], { sortOrder: 1 }),
      station('s-ghost', 'GHOST', ['PS5'], { sortOrder: 2 }),
      station('s-rift', 'RIFT', ['PS5', 'VR'], { sortOrder: 3 }),
      station('s-nova', 'NOVA', ['PS5'], { sortOrder: 4, status: 'maintenance' }),
      station('s-vr', 'VR Bay', ['VR'], { sortOrder: 5 }),
      station('s-ps4', 'PS4', ['PS5'], { sortOrder: 6, status: 'disabled' }),
    ];
    this.gameList = [
      game('g-fc', 'EA SPORTS FC 25', ['PS5'], true, 3, 'digital'),
      game('g-tekken', 'Tekken 8', ['PS5'], true, 16, 'disc'),
      game('g-gt', 'Gran Turismo 7', ['PS5']),
      game('g-mk', 'Mortal Kombat 1', ['PS5'], false, 18, 'disc'),
      game('g-beat', 'Beat Saber', ['PSVR2']),
    ];
    const playable = (gameId: string, ...stations: string[]): GameCompat[] =>
      stations.map((resourceId) => ({ gameId, resourceId, status: 'playable' }));
    this.compatList = [
      ...playable('g-fc', 's-hex', 's-void', 's-ghost', 's-rift'),
      ...playable('g-tekken', 's-hex', 's-void'),
      ...playable('g-gt', 's-rift'),
      { gameId: 'g-gt', resourceId: 's-hex', status: 'not_playable' },
      ...playable('g-mk', 's-hex'),
      ...playable('g-beat', 's-vr', 's-rift'),
    ];
    this.customerList = [
      { id: 'c-kiran', name: 'Kiran Rao', phone: '9845012873', lastVisitAt: at(0, '17:40') },
      { id: 'c-aditya', name: 'Aditya Shah', phone: '9845744810', lastVisitAt: at(0, '15:45') },
      { id: 'c-meera', name: 'Meera Pillai', phone: '9846476747', lastVisitAt: at(0, '12:10') },
      { id: 'c-rahul', name: 'Rahul Verma', phone: null, lastVisitAt: at(1, '19:00') },
      { id: 'c-sana', name: 'Sana Khan', phone: '9847940621', lastVisitAt: null },
    ].map((c) => ({
      ...c,
      createdAt: at(80, '12:00'),
      birthYear: c.id === 'c-kiran' ? 2001 : null,
    }));

    const play = (
      id: string,
      o: Partial<Play> & Pick<Play, 'billId' | 'customerId' | 'resourceId' | 'startedAt'>,
    ): Play => ({
      id,
      kind: 'single',
      billStatus: 'completed',
      activityCode: 'PS5',
      gameId: null,
      controllers: 1,
      endedAt: null,
      scheduledEndAt: o.startedAt,
      ...o,
    });
    this.playList = [
      // Live: HEX ends in 25 minutes, VOID (a group of two) in 8.
      play('p-live-hex', {
        billId: 'b-live-hex',
        billStatus: 'active',
        customerId: 'c-kiran',
        resourceId: 's-hex',
        gameId: 'g-fc',
        controllers: 2,
        startedAt: inMin(-35),
        scheduledEndAt: inMin(25),
      }),
      ...[1, 2].map((n) =>
        play(`p-live-void-${n}`, {
          kind: 'group',
          billId: 'b-live-void',
          billStatus: 'active',
          customerId: 'c-aditya',
          resourceId: 's-void',
          gameId: 'g-tekken',
          startedAt: inMin(-52),
          scheduledEndAt: inMin(8),
        }),
      ),
      // History.
      play('p-1', {
        billId: 'b-1',
        customerId: 'c-kiran',
        resourceId: 's-hex',
        gameId: 'g-fc',
        startedAt: at(0, '16:40'),
        endedAt: at(0, '17:40'),
      }),
      play('p-2', {
        billId: 'b-2',
        customerId: 'c-meera',
        resourceId: 's-rift',
        gameId: 'g-gt',
        startedAt: at(0, '11:10'),
        endedAt: at(0, '12:10'),
      }),
      play('p-3', {
        billId: 'b-3',
        customerId: 'c-kiran',
        resourceId: 's-hex',
        gameId: 'g-mk',
        startedAt: at(1, '18:00'),
        endedAt: at(1, '19:30'),
      }),
      play('p-4', {
        billId: 'b-4',
        customerId: 'c-rahul',
        resourceId: 's-void',
        gameId: 'g-fc',
        startedAt: at(1, '18:00'),
        endedAt: at(1, '19:00'),
      }),
      play('p-5', {
        billId: 'b-5',
        billStatus: 'voided',
        customerId: 'c-kiran',
        resourceId: 's-ghost',
        gameId: 'g-fc',
        startedAt: at(2, '15:00'),
        endedAt: at(2, '16:00'),
      }),
    ];
    this.visitList = [
      { id: 'b-live-hex', kind: 'single', customerId: 'c-kiran', status: 'active' },
      { id: 'b-live-void', kind: 'group', customerId: 'c-aditya', status: 'active' },
      { id: 'b-1', kind: 'single', customerId: 'c-kiran', status: 'completed', billed: 24000 },
      { id: 'b-2', kind: 'single', customerId: 'c-meera', status: 'completed', billed: 15000 },
      { id: 'b-3', kind: 'single', customerId: 'c-kiran', status: 'completed', billed: 18000 },
      { id: 'b-4', kind: 'single', customerId: 'c-rahul', status: 'completed', billed: 12000 },
      { id: 'b-5', kind: 'single', customerId: 'c-kiran', status: 'voided', billed: 12000 },
    ].map((v): Visit => {
      const plays = this.playList.filter((p) => p.billId === v.id);
      return {
        id: v.id,
        kind: v.kind as Visit['kind'],
        customerId: v.customerId,
        status: v.status as Visit['status'],
        startedAt: plays[0].startedAt,
        endedAt: plays[0].endedAt,
        billedPaise: v.billed ?? null,
      };
    });
    this.chargeList = [
      { billId: 'b-1', resourceId: 's-hex', at: at(0, '16:40'), minutes: 60, paise: 24000 },
      { billId: 'b-2', resourceId: 's-rift', at: at(0, '11:10'), minutes: 60, paise: 15000 },
      { billId: 'b-3', resourceId: 's-hex', at: at(1, '18:00'), minutes: 90, paise: 18000 },
      { billId: 'b-4', resourceId: 's-void', at: at(1, '18:00'), minutes: 60, paise: 12000 },
      { billId: 'b-6', resourceId: 's-vr', at: at(4, '17:00'), minutes: 30, paise: 30000 },
    ].map((c): Charge => ({
      kind: 'single',
      billId: c.billId,
      resourceId: c.resourceId,
      activityCode: c.resourceId === 's-vr' ? 'VR' : 'PS5',
      segmentStart: c.at,
      playedMinutes: c.minutes,
      amountPaise: c.paise,
    }));
  }

  async stations(): Promise<Station[]> {
    this.fail();
    return [...this.stationList].sort((a, b) => a.sortOrder - b.sortOrder);
  }

  async games(): Promise<Game[]> {
    this.fail();
    return [...this.gameList].sort((a, b) => a.name.localeCompare(b.name));
  }

  async gameResources(): Promise<GameCompat[]> {
    this.fail();
    return this.compatList.map((c) => ({ ...c }));
  }

  async customers(): Promise<Customer[]> {
    this.fail();
    return [...this.customerList].sort((a, b) => a.name.localeCompare(b.name));
  }

  async plays(_arenaId: string, since: Date): Promise<Play[]> {
    this.fail();
    return this.playList.filter((p) => !p.endedAt || Date.parse(p.startedAt) >= since.getTime());
  }

  async charges(_arenaId: string, from: Date, to: Date): Promise<Charge[]> {
    this.fail();
    return this.chargeList.filter((c) => {
      const t = Date.parse(c.segmentStart);
      return t >= from.getTime() && t < to.getTime();
    });
  }

  async visits(_arenaId: string, since: Date): Promise<Visit[]> {
    this.fail();
    return this.visitList.filter(
      (v) => v.status === 'active' || Date.parse(v.startedAt) >= since.getTime(),
    );
  }

  async saveStation(_arenaId: string, s: StationInput): Promise<void> {
    this.fail();
    const clash = this.stationList.find(
      (x) => x.id !== s.id && x.name.toLowerCase() === s.name.toLowerCase(),
    );
    if (clash) throw new AppError('duplicate', FLOOR_MESSAGES['duplicate']);
    this.ops.push({ kind: 'resource.upsert', payload: s });
    const next: Station = { ...s, activityCodes: [...s.activityCodes] };
    const i = this.stationList.findIndex((x) => x.id === s.id);
    if (i < 0) this.stationList.push(next);
    else this.stationList[i] = next;
  }

  async setStationStatus(_arenaId: string, id: string, status: StationStatus): Promise<void> {
    this.fail();
    const i = this.stationList.findIndex((x) => x.id === id);
    if (i < 0) throw new AppError('not_found', FLOOR_MESSAGES['not_found']);
    this.ops.push({ kind: 'resource.set_status', payload: { id, status } });
    this.stationList[i] = { ...this.stationList[i], status };
  }

  async saveGame(
    _arenaId: string,
    g: GameInput,
    playableOn: readonly string[] = [],
  ): Promise<void> {
    this.fail();
    if (this.gameList.some((x) => x.id !== g.id && x.name.toLowerCase() === g.name.toLowerCase())) {
      throw new AppError('duplicate', FLOOR_MESSAGES['duplicate']);
    }
    this.ops.push({ kind: 'game.upsert', payload: g });
    const next: Game = { ...g, aliases: [...g.aliases], platforms: [...g.platforms] };
    const i = this.gameList.findIndex((x) => x.id === g.id);
    if (i < 0) this.gameList.push(next);
    else this.gameList[i] = next;
    for (const resourceId of playableOn) this.compat(g.id, resourceId, 'playable');
  }

  async setGameCompat(
    _arenaId: string,
    gameId: string,
    resourceId: string,
    status: CompatStatus,
  ): Promise<void> {
    this.fail();
    if (!this.gameList.some((g) => g.id === gameId)) {
      throw new AppError('not_found', FLOOR_MESSAGES['not_found']);
    }
    this.compat(gameId, resourceId, status);
  }

  /** Records the real op (compatOps) and upserts the pair like the server does. */
  private compat(gameId: string, resourceId: string, status: CompatStatus): void {
    this.ops.push(...compatOps(gameId, resourceId, status));
    const row: GameCompat = { gameId, resourceId, status };
    const i = this.compatList.findIndex((c) => c.gameId === gameId && c.resourceId === resourceId);
    if (i < 0) this.compatList.push(row);
    else this.compatList[i] = row;
  }

  async setGameActive(_arenaId: string, id: string, active: boolean): Promise<void> {
    this.fail();
    const i = this.gameList.findIndex((x) => x.id === id);
    if (i < 0) throw new AppError('not_found', FLOOR_MESSAGES['not_found']);
    this.ops.push({ kind: 'game.set_active', payload: { id, active } });
    this.gameList[i] = { ...this.gameList[i], active };
  }

  private fail(): void {
    const code = this.failNext;
    if (!code) return;
    this.failNext = null;
    throw new AppError(code, FLOOR_MESSAGES[code] ?? code);
  }
}
