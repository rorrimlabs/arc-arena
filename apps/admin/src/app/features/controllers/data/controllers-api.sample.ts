import { AppError } from '../../../core/auth/auth-api';
import { CONTROLLER_MESSAGES, ControllersApi, controllerOps, statusOps } from './controllers-api';
import { Controller, ControllerStatus } from './controller.models';

function pad(id: string, label: string, home: string, o: Partial<Controller> = {}): Controller {
  return {
    id,
    label,
    homeId: home,
    currentId: home,
    status: 'usable',
    notes: null,
    loanReturnTo: null,
    loanSessionRef: null,
    ...o,
  };
}

/**
 * Deterministic pads on SampleFloorApi's stations: HEX-2 is lent to VOID (its group session owes
 * the return), VOID-2 is faulty, GHOST-1 missing. Writes apply in memory like the server would and
 * are recorded in `ops`.
 */
export class SampleControllersApi extends ControllersApi {
  list: Controller[] = [
    pad('c-hex-1', 'HEX-1', 's-hex'),
    pad('c-hex-2', 'HEX-2', 's-hex', {
      currentId: 's-void',
      loanReturnTo: 's-hex',
      loanSessionRef: 'g:b-live-void',
    }),
    pad('c-void-1', 'VOID-1', 's-void'),
    pad('c-void-2', 'VOID-2', 's-void', { status: 'faulty', notes: 'Left stick drift' }),
    pad('c-ghost-1', 'GHOST-1', 's-ghost', { status: 'missing' }),
    pad('c-rift-1', 'RIFT-1', 's-rift'),
  ];
  /** Every write, in order, as `kind` + payload. */
  readonly ops: { kind: string; payload: unknown }[] = [];
  /** Set to make the next call fail with this code. */
  failNext: string | null = null;

  constructor(empty = false) {
    super();
    if (empty) this.list = [];
  }

  async controllers(): Promise<Controller[]> {
    this.fail();
    return [...this.list].sort((a, b) => a.label.localeCompare(b.label));
  }

  async controller(_arenaId: string, id: string): Promise<Controller | null> {
    this.fail();
    return this.list.find((c) => c.id === id) ?? null;
  }

  async save(_arenaId: string, c: Controller): Promise<void> {
    this.fail();
    this.ops.push(...controllerOps(c));
    const existing = this.list.find((x) => x.id === c.id);
    this.list = existing ? this.list.map((x) => (x.id === c.id ? { ...c } : x)) : [...this.list, c];
  }

  async setStatus(
    _arenaId: string,
    id: string,
    status: ControllerStatus,
    notes: string | null,
  ): Promise<void> {
    this.fail();
    this.ops.push(...statusOps(id, status, notes));
    if (!this.list.some((c) => c.id === id)) {
      throw new AppError('not_found', CONTROLLER_MESSAGES['not_found']);
    }
    this.list = this.list.map((c) => (c.id === id ? { ...c, status, notes } : c));
  }

  private fail(): void {
    const code = this.failNext;
    if (!code) return;
    this.failNext = null;
    throw new AppError(code, CONTROLLER_MESSAGES[code] ?? code);
  }
}
