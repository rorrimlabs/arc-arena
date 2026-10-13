/**
 * Development: the local Supabase stack (`supabase start` in the repo root).
 * Production builds use environment.production.ts (angular.json fileReplacements).
 */
export const environment = {
  supabaseUrl: 'http://127.0.0.1:54431',
  /** Publishable key: safe in a browser — RLS and the client API decide what it can reach. */
  supabaseKey: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
};
