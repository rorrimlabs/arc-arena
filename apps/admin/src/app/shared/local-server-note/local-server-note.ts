import { Component, booleanAttribute, inject, input } from '@angular/core';
import { LOCAL_SERVER } from '../../core/supabase/local-server';

/**
 * Says so when this dashboard runs on the local Supabase stack. Accounts made here (an accepted
 * invitation, a password) exist only on that stack, so a staff app on the hosted server answers
 * "don't match a login" for them. Renders nothing on a hosted project.
 */
@Component({
  selector: 'app-local-server-note',
  host: { class: 'contents' },
  template: `
    @if (server; as s) {
      <p
        role="note"
        class="flex items-start gap-2 bg-warning-soft py-2.5 text-[13px] leading-[1.4] font-medium text-warning"
        [class.px-4]="!framed()"
        [class.px-3]="framed()"
        [class.rounded-lg]="framed()"
      >
        <span class="icon text-[18px] leading-none" aria-hidden="true">dns</span>
        <span>
          <strong class="font-bold">Local test server ({{ s.address }}).</strong>
          Logins and invitations made here exist only on this computer. Staff sign in from a staff
          app run on the local server (<code>tool/dev_run.sh</code>); an app built with
          <code>dart_define.prod.json</code> uses the hosted server and won't find them.
          @if (s.mailUrl) {
            Invitation e-mails arrive in the
            <a class="underline" [href]="s.mailUrl" target="_blank" rel="noopener">local mailbox</a>,
            not in real inboxes.
          }
        </span>
      </p>
    }
  `,
})
export class LocalServerNote {
  /** Rounded, for use inside a card (the shell shows it as a full-width bar). */
  readonly framed = input(false, { transform: booleanAttribute });
  protected readonly server = inject(LOCAL_SERVER);
}
