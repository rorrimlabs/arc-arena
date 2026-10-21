import { Service, inject } from '@angular/core';
import type { Session as AuthSession, SupabaseClient } from '@supabase/supabase-js';
import { isOwnerLevel, toMemberships } from '../arena/arena-api';
import { dbError } from '../supabase/db-error';
import { Captcha } from '../../shared/turnstile/turnstile';
import { Supabase } from '../supabase/supabase';
import { Account, AcceptedInvite, AppError, acceptError, toAccount, toAppError } from './auth-api';

/** The invitee's tokens, to make their sign-in the dashboard's (InviteeAuth.tokens). */
export interface InviteeTokens {
  readonly accessToken: string;
  readonly refreshToken: string;
}

/**
 * The invitee's own sign-in on the invitation page, kept apart from the dashboard's: it lives
 * only in this page's memory, so accepting an invitation in a browser where someone else (the
 * owner who sent it) is signed in never signs that person out or replaces them. Accepting is
 * accept_invite as the invitee; whether they then use this dashboard is the server's answer
 * (their memberships), and taking it over is an explicit step (AcceptInvite → Open dashboard).
 */
@Service({ factory: () => new SupabaseInviteeAuth() })
export abstract class InviteeAuth {
  /** Drops any previous invitee sign-in: each invitation page starts with none. */
  abstract begin(): void;
  /** The invitee signed in on this page, or null. */
  abstract account(): Account | null;
  /** Signs the invitee in from the e-mailed link's session (Supabase Auth's fragment). */
  abstract fromLink(accessToken: string, refreshToken: string): Promise<Account>;
  /** Signs the invitee in with their e-mail and password (a login that already has one). */
  abstract signIn(email: string, password: string): Promise<Account>;
  /** Sets the invitee's password (a new login chooses one before joining). */
  abstract setPassword(password: string): Promise<void>;
  /** accept_invite as the invitee: the membership is created or reactivated exactly once. */
  abstract accept(inviteId: string, token: string): Promise<AcceptedInvite>;
  /** Owner level in that arena now (my_arenas as the invitee): may use this dashboard. */
  abstract canManage(arenaId: string): Promise<boolean>;
  /** The invitee's tokens, to hand to the dashboard's sign-in; null when not signed in. */
  abstract tokens(): InviteeTokens | null;
  /** Ends the invitee's sign-in (on the server too). The dashboard's sign-in is untouched. */
  abstract end(): Promise<void>;
}

class SupabaseInviteeAuth extends InviteeAuth {
  private readonly supabase = inject(Supabase);
  private readonly captcha = inject(Captcha);
  private client: Promise<SupabaseClient> | null = null;
  private session: AuthSession | null = null;

  private get() {
    this.client ??= this.supabase.isolatedClient();
    return this.client;
  }

  begin(): void {
    this.client = null;
    this.session = null;
  }

  account(): Account | null {
    return toAccount(this.session?.user);
  }

  async fromLink(accessToken: string, refreshToken: string): Promise<Account> {
    const { data, error } = await (
      await this.get()
    ).auth.setSession({ access_token: accessToken, refresh_token: refreshToken });
    if (error) throw toAppError(error);
    return this.signedIn(data.session);
  }

  async signIn(email: string, password: string): Promise<Account> {
    const { data, error } = await (await this.get()).auth.signInWithPassword({
      email,
      password,
      options: { captchaToken: this.captcha.take() },
    });
    if (error) throw toAppError(error);
    return this.signedIn(data.session);
  }

  async setPassword(password: string): Promise<void> {
    const { error } = await (await this.get()).auth.updateUser({ password });
    if (error) throw toAppError(error);
  }

  async accept(inviteId: string, token: string): Promise<AcceptedInvite> {
    if (!this.session)
      throw new AppError('forbidden', 'Sign in first, then accept the invitation.');
    const { data, error } = await (
      await this.get()
    ).rpc('accept_invite', { p_invite: inviteId, p_token: token });
    if (error) throw acceptError(error);
    const r = data as { arena_id: string; arena_name: string; role: string };
    return {
      arenaId: String(r.arena_id),
      arenaName: String(r.arena_name ?? ''),
      role: r.role === 'owner' ? 'owner' : 'staff',
    };
  }

  async canManage(arenaId: string): Promise<boolean> {
    const { data, error } = await (await this.get()).rpc('my_arenas');
    if (error) throw dbError(error);
    return toMemberships(data).some((m) => m.arenaId === arenaId && isOwnerLevel(m));
  }

  tokens(): InviteeTokens | null {
    return this.session
      ? { accessToken: this.session.access_token, refreshToken: this.session.refresh_token }
      : null;
  }

  async end(): Promise<void> {
    const client = this.client;
    this.session = null;
    this.client = null;
    // This session only (scope local): the dashboard's own stored session is another one.
    if (client) await (await client).auth.signOut({ scope: 'local' }).catch(() => undefined);
  }

  private signedIn(session: AuthSession | null): Account {
    const account = toAccount(session?.user);
    if (!session || !account) {
      throw new AppError('auth_error', 'Could not sign you in from this link');
    }
    this.session = session;
    return account;
  }
}
