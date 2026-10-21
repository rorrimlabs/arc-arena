import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { ConfigError } from '../../features/auth/config-error';
import { Supabase, configProblem } from './supabase';

/** A legacy JWT key with the given payload (signature irrelevant to the check). */
function jwt(payload: Record<string, unknown>): string {
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(payload)}.c2lnbmF0dXJl`;
}

const HOSTED = 'https://abcdefghijklmnop.supabase.co';
const PUBLISHABLE = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const prod = (supabaseUrl: string, supabaseKey: string) =>
  configProblem({ production: true, supabaseUrl, supabaseKey });
const dev = (supabaseUrl: string, supabaseKey: string) =>
  configProblem({ production: false, supabaseUrl, supabaseKey });

describe('configProblem', () => {
  it('accepts a hosted project with a publishable or legacy anon key', () => {
    expect(prod(HOSTED, PUBLISHABLE)).toBeNull();
    expect(prod(HOSTED, jwt({ role: 'anon', iss: 'supabase' }))).toBeNull();
  });

  it('accepts the local stack in development', () => {
    expect(dev('http://127.0.0.1:54431', PUBLISHABLE)).toBeNull();
    expect(dev('http://localhost:54321', jwt({ role: 'anon' }))).toBeNull();
  });

  it('refuses a build without values (the empty production file)', () => {
    expect(prod('', '')).toContain('environments/environment.production.ts');
    expect(prod(HOSTED, '')).toContain('no Supabase project set');
    expect(dev('', PUBLISHABLE)).toContain('environments/environment.ts');
  });

  it('refuses a production build that is not https or points at a local stack', () => {
    expect(prod('http://abcdefghijklmnop.supabase.co', PUBLISHABLE)).toContain('over https');
    for (const url of [
      'https://localhost:54321',
      'https://127.0.0.1:54321',
      'https://[::1]:54321',
      'https://supabase.local',
    ]) {
      expect(prod(url, PUBLISHABLE)).toContain('local Supabase stack');
    }
    expect(prod('not a url', PUBLISHABLE)).toContain('not a valid web address');
  });

  it('refuses secret and service_role keys, and never repeats the key', () => {
    const secret = 'sb_secret_example-not-a-real-key';
    const service = jwt({ role: 'service_role', iss: 'supabase' });
    for (const [key, word] of [
      [secret, 'secret key'],
      [service, 'service_role key'],
    ] as const) {
      for (const problem of [prod(HOSTED, key), dev('http://127.0.0.1:54431', key)]) {
        expect(problem).toContain(word);
        expect(problem).not.toContain(key);
      }
    }
  });

  it('refuses anything that is not a publishable or anon key', () => {
    expect(prod(HOSTED, 'some-random-string')).toContain('not a publishable key');
    expect(prod(HOSTED, jwt({ role: 'authenticated' }))).toContain('not a publishable key');
    expect(prod(HOSTED, 'a.b.c')).toContain('not a publishable key');
  });
});

describe('Supabase', () => {
  it('this (development) build is configured', () => {
    const supabase = TestBed.inject(Supabase);
    expect(supabase.configProblem).toBeNull();
    expect(supabase.misconfigured).toBe(false);
  });
});

describe('ConfigError', () => {
  it('shows why the build cannot connect, as an alert', () => {
    const problem = 'This build has no Supabase project set.';
    TestBed.configureTestingModule({
      providers: [{ provide: Supabase, useValue: { configProblem: problem, misconfigured: true } }],
    });
    const fixture = TestBed.createComponent(ConfigError);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('h1')?.textContent?.trim()).toBe('Setup needed');
    expect(el.querySelector('[role="alert"]')?.textContent?.trim()).toBe(problem);
    expect(el.querySelector('main')).not.toBeNull();
  });
});
