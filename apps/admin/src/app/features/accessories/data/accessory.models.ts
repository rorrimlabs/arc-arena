import { PillTone } from '../../../shared/status-pill/status-pill';

export type AccessoryStatus = 'usable' | 'faulty' | 'missing' | 'unavailable' | 'retired';

/**
 * A station accessory (server: controllers): a game pad, VR headset, steering wheel… `homeId` is
 * the station it belongs to, `currentId` where it is now; while lent to another station's session
 * it owes a return (`loanReturnTo`). `kindId` null = a game pad (from before kinds existed).
 */
export interface Accessory {
  readonly id: string;
  /** The name the arena gives it (e.g. HEX-1, "Blue pad"), which staff look for. */
  readonly label: string;
  readonly kindId: string | null;
  readonly homeId: string;
  readonly currentId: string;
  readonly status: AccessoryStatus;
  /** Why it is in its status (e.g. stick drift). */
  readonly notes: string | null;
  /** While on loan: the home station id it goes back to. */
  readonly loanReturnTo: string | null;
  /** While on loan: the session that owes the return (s:<id> or g:<id>). */
  readonly loanSessionRef: string | null;
}

/**
 * What sort of accessory it is (server: accessory_kinds), defined by the owner. Only kinds that
 * count as a controller are handed to players and set the controller-count price.
 */
export interface AccessoryKind {
  readonly id: string;
  readonly name: string;
  readonly countsAsController: boolean;
  readonly sortOrder: number;
  readonly active: boolean;
}

/** One move in an accessory's history (server: controller_moves). */
export interface AccessoryMove {
  readonly id: string;
  readonly fromId: string;
  readonly toId: string;
  /** loan (lent for a session), returnHome, permanent (re-homed). */
  readonly kind: 'loan' | 'returnHome' | 'permanent';
  readonly sessionRef: string | null;
  readonly at: string;
}

/** What an owner changes on an accessory: only the fields given are changed. */
export interface AccessoryChange {
  readonly label?: string;
  readonly kindId?: string | null;
  readonly homeId?: string;
  readonly status?: AccessoryStatus;
  readonly notes?: string | null;
}

/** The floor app's statuses (ControllerStatus), in its order of use. */
export const ACCESSORY_STATUSES: readonly {
  readonly value: AccessoryStatus;
  readonly label: string;
  readonly sub: string;
  readonly tone: PillTone;
}[] = [
  { value: 'usable', label: 'Usable', sub: 'Working: staff can use or lend it', tone: 'primary' },
  {
    value: 'faulty',
    label: 'Faulty',
    sub: 'Broken: no session can use it and no station can borrow it',
    tone: 'danger',
  },
  {
    value: 'unavailable',
    label: 'Unavailable',
    sub: 'Kept off the floor for now (not broken)',
    tone: 'info',
  },
  { value: 'missing', label: 'Missing', sub: "Can't be found: kept on the books", tone: 'warning' },
  { value: 'retired', label: 'Retired', sub: 'Written off: left out of every count', tone: 'info' },
];

export function statusInfo(status: AccessoryStatus) {
  return ACCESSORY_STATUSES.find((s) => s.value === status) ?? ACCESSORY_STATUSES[0];
}

export const MAX_LABEL = 30;

/** "Controller" when it has no kind; the kind's name otherwise. */
export function kindName(a: Pick<Accessory, 'kindId'>, kinds: ReadonlyMap<string, AccessoryKind>) {
  return a.kindId ? (kinds.get(a.kindId)?.name ?? 'Accessory') : 'Controller';
}

/** A pad: no kind, or a kind that counts as a controller (the server's _is_pad). */
export function isPad(a: Pick<Accessory, 'kindId'>, kinds: ReadonlyMap<string, AccessoryKind>) {
  return !a.kindId || kinds.get(a.kindId)?.countsAsController === true;
}

/** Material Symbols icon for an accessory, from its kind's name. */
export function accessoryIcon(name: string): string {
  if (/vr|headset/i.test(name)) return 'view_in_ar';
  if (/wheel|steer|pedal|racing/i.test(name)) return 'trip_origin';
  if (/head ?phone|audio/i.test(name)) return 'headphones';
  if (/cue|ball set|snooker|pool/i.test(name)) return 'sports_bar';
  if (/football|soccer/i.test(name)) return 'sports_soccer';
  if (/cricket|bat\b/i.test(name)) return 'sports_cricket';
  if (/badminton|racket|shuttle/i.test(name)) return 'sports_tennis';
  if (/bib|jersey|vest/i.test(name)) return 'checkroom';
  if (/stick|gun|arcade/i.test(name)) return 'joystick';
  return 'videogame_asset';
}

/**
 * The accessory as controller.upsert will store it: `fresh` (what the server holds right now)
 * with the change applied. A new home on the station it stands at settles a loan; one still lent
 * elsewhere now goes back to its new home (the floor app's setControllerHome).
 */
export function applyChange(fresh: Accessory, change: AccessoryChange): Accessory {
  const next: Accessory = {
    ...fresh,
    label: change.label ?? fresh.label,
    kindId: change.kindId !== undefined ? change.kindId : fresh.kindId,
    status: change.status ?? fresh.status,
    notes: change.notes !== undefined ? change.notes : fresh.notes,
  };
  const homeId = change.homeId;
  if (homeId === undefined || homeId === fresh.homeId) return next;
  const settled = homeId === fresh.currentId;
  return {
    ...next,
    homeId,
    loanReturnTo: settled || fresh.loanReturnTo == null ? null : homeId,
    loanSessionRef: settled ? null : fresh.loanSessionRef,
  };
}

/** Names must not repeat (staff go by them); case is ignored. The server does not check. */
export function labelTaken(
  label: string,
  accessories: readonly Accessory[],
  exceptId?: string,
): boolean {
  const wanted = label.trim().toLowerCase();
  return accessories.some((c) => c.id !== exceptId && c.label.toLowerCase() === wanted);
}

/** The next free "<station>-<n>" for an accessory added to a station. */
export function nextLabel(stationName: string, stationId: string, all: readonly Accessory[]) {
  let n = all.filter((c) => c.homeId === stationId).length + 1;
  while (labelTaken(`${stationName}-${n}`, all)) n++;
  return `${stationName}-${n}`;
}
