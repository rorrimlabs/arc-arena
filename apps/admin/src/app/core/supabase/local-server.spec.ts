import { environment as production } from '../../../environments/environment.production';
import { localServer } from './local-server';

describe('localServer', () => {
  const dev = { production: false, localMailUrl: 'http://127.0.0.1:54434' };

  it('names the local stack and its mailbox', () => {
    expect(localServer({ ...dev, supabaseUrl: 'http://127.0.0.1:54431' })).toEqual({
      address: '127.0.0.1:54431',
      mailUrl: 'http://127.0.0.1:54434',
    });
    expect(localServer({ ...dev, supabaseUrl: 'http://localhost:54431' })?.address).toBe(
      'localhost:54431',
    );
    // A Mac's LAN name, as a tablet on the same network would use it.
    expect(localServer({ ...dev, supabaseUrl: 'http://studio-mac.local:54431' })?.address).toBe(
      'studio-mac.local:54431',
    );
  });

  it('is null for a hosted project, a production build or an unreadable address', () => {
    expect(localServer({ ...dev, supabaseUrl: 'https://abcd.supabase.co' })).toBeNull();
    expect(
      localServer({ ...dev, production: true, supabaseUrl: 'http://127.0.0.1:54431' }),
    ).toBeNull();
    expect(localServer({ ...dev, supabaseUrl: 'not a url' })).toBeNull();
    expect(localServer({ ...dev, supabaseUrl: '' })).toBeNull();
  });

  it('has no mailbox when none is configured', () => {
    expect(
      localServer({ production: false, supabaseUrl: 'http://127.0.0.1:54431' })?.mailUrl,
    ).toBeNull();
    expect(
      localServer({ ...dev, localMailUrl: '  ', supabaseUrl: 'http://127.0.0.1:54431' })?.mailUrl,
    ).toBeNull();
  });

  it('never shows in the production build settings', () => {
    expect(localServer(production)).toBeNull();
  });
});
