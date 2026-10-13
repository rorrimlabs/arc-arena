import { Service, inject } from '@angular/core';
import type { PostgrestError } from '@supabase/supabase-js';
import { dbError } from '../../../core/arena/arena-api';
import { AppError } from '../../../core/auth/auth-api';
import { Supabase } from '../../../core/supabase/supabase';
import { pushOps } from '../../../core/sync/push-ops';
import { ArenaUser, NewUser, PendingInvite, UserChange } from './user.models';

/**
 * The arena's users (owners and staff): read through arena_staff(); new people join only by
 * invitation — the staff-admin Edge Function e-mails a one-time link (it holds the service-role
 * key; the browser never does) and the person accepts it on /accept-invite with a password they
 * choose. Open invitations are read through arena_invites() and withdrawn with revoke_invite().
 * Changes are a `staff.update` op through sync_push — the same path, permission checks and
 * history as the floor app. Tests provide SampleUsersApi.
 */
@Service({ factory: () => new SupabaseUsersApi() })
export abstract class UsersApi {
  abstract list(arenaId: string): Promise<ArenaUser[]>;
  /** The arena's open invitations, newest first (owner level). */
  abstract listInvites(arenaId: string): Promise<PendingInvite[]>;
  /**
   * E-mails an invitation (a newer one to the same address replaces the open one). The reply is
   * the same whether or not the address already has a login.
   */
  abstract invite(arenaId: string, user: NewUser): Promise<{ inviteId: string; expiresAt: string }>;
  abstract revokeInvite(arenaId: string, inviteId: string): Promise<void>;
  /** `adjusted`: the server saved something other than what was sent (reload the list). */
  abstract update(
    arenaId: string,
    userId: string,
    change: UserChange,
  ): Promise<{ adjusted: boolean }>;
}

/** Refusals of staff.update, invite and withdraw, worded for the Users screen. */
export const USER_MESSAGES: Readonly<Record<string, string>> = {
  owner_profile: 'That login is already an owner of this arena',
  last_settings_holder: 'Someone must keep the Settings permission',
  invalid_permission: 'Unknown permission',
  invalid_role: 'Choose Staff or Owner',
  invalid_email: 'Enter a valid email',
  invalid_name: 'Names must be 1 to 80 characters',
  invalid_input: 'Check the name and email, then try again',
  not_found: 'That person is no longer on the list. Refresh',
  forbidden: 'Only an owner can do that',
  unauthorized: 'Your session has expired. Sign in again',
  origin_not_allowed:
    'This dashboard address may not send invitations. Ask the operator to allow it for the staff-admin function',
  email_rate_limited: 'Too many e-mails right now. Wait a while, then try again',
  email_failed: 'The invitation e-mail could not be sent, so nothing was saved. Try again',
  misconfigured: 'Invitations are not set up on the server yet. Ask the operator',
  server_error: 'Could not create the invitation. Try again',
};

/** Refusals of revoke_invite / arena_invites. */
export const INVITE_MESSAGES: Readonly<Record<string, string>> = {
  not_found: 'That invitation is no longer open. Refresh',
  forbidden: 'You need the Settings permission (an owner, for an owner invitation) to withdraw it',
};

const NETWORK = 'Could not reach the server. Check the connection and try again';

/** "only an owner can invite an owner" → "Only an owner can invite an owner". */
function sentence(hint: string): string {
  const text = hint.trim().replace(/\.$/, '');
  return text.charAt(0).toUpperCase() + text.slice(1);
}

class SupabaseUsersApi extends UsersApi {
  private readonly supabase = inject(Supabase);

  async list(arenaId: string): Promise<ArenaUser[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('arena_staff', { p_arena: arenaId });
    if (error) throw dbError(error);
    return (data as Record<string, unknown>[]).map((r) => ({
      userId: String(r['user_id']),
      name: String(r['name']),
      email: String(r['email'] ?? ''),
      role: r['role'] === 'owner' ? 'owner' : 'staff',
      perms: (r['perms'] as string[] | null) ?? [],
      active: r['active'] === true,
      invited: r['invited'] === true,
      bills30d: Number(r['bills_30d'] ?? 0),
      takings30dPaise: Number(r['takings_30d_paise'] ?? 0),
      refunds30dPaise: Number(r['refunds_30d_paise'] ?? 0),
    }));
  }

  async listInvites(arenaId: string): Promise<PendingInvite[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('arena_invites', { p_arena: arenaId });
    if (error) throw inviteError(error);
    return ((data as Record<string, unknown>[] | null) ?? []).map((r) => ({
      inviteId: String(r['invite_id']),
      email: String(r['email'] ?? ''),
      name: String(r['name'] ?? ''),
      role: r['role'] === 'owner' ? 'owner' : 'staff',
      perms: (r['perms'] as string[] | null) ?? [],
      createdAt: String(r['created_at']),
      expiresAt: String(r['expires_at']),
      expired: r['expired'] === true,
      invitedByName: r['invited_by_name'] == null ? null : String(r['invited_by_name']),
    }));
  }

  async invite(arenaId: string, user: NewUser): Promise<{ inviteId: string; expiresAt: string }> {
    const client = await this.supabase.client();
    const { data, error } = await client.functions.invoke('staff-admin', {
      body: {
        arena_id: arenaId,
        email: user.email,
        name: user.name,
        role: user.role,
        perms: user.perms,
      },
    });
    if (error) {
      if (error.name === 'FunctionsHttpError') {
        const body = (await (error.context as Response).json().catch(() => ({}))) as {
          error?: string;
          message?: string;
        };
        const code = body.error ?? 'server_error';
        // `forbidden` carries the server's reason ("only an owner can grant money or reports").
        if (code === 'forbidden' && body.message) {
          throw new AppError(code, sentence(body.message));
        }
        throw new AppError(code, USER_MESSAGES[code] ?? USER_MESSAGES['server_error']);
      }
      throw new AppError('network', NETWORK);
    }
    const out = data as { invite_id: string; expires_at: string };
    return { inviteId: String(out.invite_id), expiresAt: String(out.expires_at) };
  }

  async revokeInvite(arenaId: string, inviteId: string): Promise<void> {
    const client = await this.supabase.client();
    const { error } = await client.rpc('revoke_invite', { p_arena: arenaId, p_invite: inviteId });
    if (error) throw inviteError(error);
  }

  async update(
    arenaId: string,
    userId: string,
    change: UserChange,
  ): Promise<{ adjusted: boolean }> {
    const [result] = await pushOps(
      await this.supabase.client(),
      arenaId,
      [
        {
          kind: 'staff.update',
          payload: {
            user_id: userId,
            name: change.name,
            perms: change.perms,
            active: change.active,
          },
        },
      ],
      USER_MESSAGES,
    );
    return { adjusted: result?.['adjusted'] === true };
  }
}

function inviteError(e: PostgrestError): AppError {
  const error = dbError(e);
  return INVITE_MESSAGES[error.code]
    ? new AppError(error.code, INVITE_MESSAGES[error.code])
    : error;
}
