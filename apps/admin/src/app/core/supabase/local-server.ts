import { InjectionToken } from '@angular/core';
import { environment } from '../../../environments/environment';
import { isLocalHost } from './supabase';

/** A dashboard build that signs in to a Supabase stack on this computer, not the hosted project. */
export interface LocalServer {
  /** host:port of the stack's API, e.g. "127.0.0.1:54431". */
  readonly address: string;
  /** The stack's mail catcher, where its invitation e-mails land; null when unknown. */
  readonly mailUrl: string | null;
}

/**
 * The local stack this build talks to, or null for a hosted project (and for every production
 * build). Logins and invitations made on a local stack exist only there: a staff app built with
 * the hosted settings (dart_define.prod.json) cannot sign them in.
 */
export function localServer(config: {
  readonly production: boolean;
  readonly supabaseUrl: string;
  readonly localMailUrl?: string;
}): LocalServer | null {
  if (config.production) return null;
  let url: URL;
  try {
    url = new URL(config.supabaseUrl);
  } catch {
    return null;
  }
  if (!isLocalHost(url.hostname)) return null;
  return { address: url.host, mailUrl: config.localMailUrl?.trim() || null };
}

/** This build's local stack (null on a hosted project); tests provide their own. */
export const LOCAL_SERVER = new InjectionToken<LocalServer | null>('LOCAL_SERVER', {
  providedIn: 'root',
  factory: () => localServer(environment),
});
