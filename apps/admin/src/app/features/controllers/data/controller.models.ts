import { PillTone } from '../../../shared/status-pill/status-pill';

export type ControllerStatus = 'usable' | 'faulty' | 'missing' | 'unavailable' | 'retired';

/**
 * A physical pad (server: controllers). `homeId` is the station it belongs to, `currentId` where
 * it is now; while lent to another station's session it owes a return (`loanReturnTo`).
 */
export interface Controller {
  readonly id: string;
  /** What is written on the pad (e.g. HEX-1), which staff look for. */
  readonly label: string;
  readonly homeId: string;
  readonly currentId: string;
  readonly status: ControllerStatus;
  /** Why it is in its status (e.g. stick drift). */
  readonly notes: string | null;
  /** While on loan: the home station id it goes back to. */
  readonly loanReturnTo: string | null;
  /** While on loan: the session that owes the return (s:<id> or g:<id>). */
  readonly loanSessionRef: string | null;
}

/** What an owner changes on a pad from the dashboard: only the fields given are changed. */
export interface ControllerChange {
  readonly label?: string;
  readonly homeId?: string;
  readonly status?: ControllerStatus;
  readonly notes?: string | null;
}

/** The floor app's statuses (ControllerStatus), in its order of use. */
export const CONTROLLER_STATUSES: readonly {
  readonly value: ControllerStatus;
  readonly label: string;
  readonly sub: string;
  readonly tone: PillTone;
}[] = [
  {
    value: 'usable',
    label: 'Usable',
    sub: 'Working: staff can give it to a player',
    tone: 'primary',
  },
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

export function statusInfo(status: ControllerStatus) {
  return CONTROLLER_STATUSES.find((s) => s.value === status) ?? CONTROLLER_STATUSES[0];
}

export const MAX_LABEL = 30;

/**
 * The pad as controller.upsert will store it: `fresh` (what the server holds right now) with the
 * change applied. A new home on the station it stands at settles a loan; a pad still lent
 * elsewhere now goes back to its new home (the floor app's setControllerHome).
 */
export function applyChange(fresh: Controller, change: ControllerChange): Controller {
  const next: Controller = {
    ...fresh,
    label: change.label ?? fresh.label,
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

/** Labels must not repeat (staff go by them); case is ignored. The server does not check. */
export function labelTaken(
  label: string,
  controllers: readonly Controller[],
  exceptId?: string,
): boolean {
  const wanted = label.trim().toLowerCase();
  return controllers.some((c) => c.id !== exceptId && c.label.toLowerCase() === wanted);
}

/** The next free "<station>-<n>" for a pad added to a station. */
export function nextLabel(stationName: string, stationId: string, all: readonly Controller[]) {
  let n = all.filter((c) => c.homeId === stationId).length + 1;
  while (labelTaken(`${stationName}-${n}`, all)) n++;
  return `${stationName}-${n}`;
}
