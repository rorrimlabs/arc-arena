import { USER_MESSAGES, inviteFailure } from './users-api';

describe('inviteFailure', () => {
  it('a gateway 503 without a function error code is "service unavailable", not a refused invite', () => {
    // Kong's reply when the edge runtime container is missing.
    const err = inviteFailure(503, { message: 'name resolution failed' });
    expect(err.code).toBe('service_unavailable');
    expect(err.message).toBe(USER_MESSAGES['service_unavailable']);
  });

  it('treats 502 and 504 without a code the same way', () => {
    expect(inviteFailure(502, {}).code).toBe('service_unavailable');
    expect(inviteFailure(504, {}).code).toBe('service_unavailable');
  });

  it("keeps the function's own code, whatever the status", () => {
    expect(inviteFailure(502, { error: 'email_failed' }).message).toBe(USER_MESSAGES['email_failed']);
    expect(inviteFailure(500, { error: 'server_error' }).message).toBe(USER_MESSAGES['server_error']);
  });

  it('a gateway 404 (the function is not deployed there) says invitations are not set up', () => {
    // The hosted gateway's reply for a function that was never deployed.
    const err = inviteFailure(404, { message: 'Requested function was not found' });
    expect(err.code).toBe('misconfigured');
    expect(err.message).toBe(USER_MESSAGES['misconfigured']);
  });

  it("the function's own service_unavailable (its database or Auth did not answer)", () => {
    const err = inviteFailure(503, { error: 'service_unavailable', message: 'x' });
    expect(err.message).toBe(USER_MESSAGES['service_unavailable']);
  });

  it('a 500 without a body stays a generic server error', () => {
    expect(inviteFailure(500, {}).code).toBe('server_error');
  });

  it("words forbidden with the server's reason", () => {
    const err = inviteFailure(403, { error: 'forbidden', message: 'only an owner can invite an owner.' });
    expect(err.message).toBe('Only an owner can invite an owner');
  });

  it('falls back to the generic message for an unknown code', () => {
    expect(inviteFailure(400, { error: 'something_new' }).message).toBe(USER_MESSAGES['server_error']);
  });
});
