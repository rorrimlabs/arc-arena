import { Component, inject, input } from '@angular/core';
import { LOCAL_SERVER } from '../../core/supabase/local-server';

/**
 * Says so when this dashboard runs on the local Supabase stack. Accounts made here (an accepted
 * invitation, a password) exist only on that stack, so a staff app on the hosted server answers
 * "don't match a login" for them. Renders nothing on a hosted project.
 *
 * `card`: the full note, inside the signed-out card (sign in, accept invitation…). `nav`: a short
 * version for the side navigation, and `rail`: an icon with a label, for the narrow navigation.
 * The nav variants sit in the navigation column, so they never push a full-height page down.
 */
@Component({
  selector: 'app-local-server-note',
  host: { class: 'contents' },
  template: `
    @if (server; as s) {
      @switch (variant()) {
        @case ('rail') {
          <p
            role="note"
            class="mb-3 flex flex-none flex-col items-center gap-1 rounded-panel border border-border/80 bg-surface-sunken py-2 text-muted"
            [title]="'Local test server (' + s.address + '): logins made here exist only on this computer'"
          >
            <span class="icon text-[20px] leading-none text-subtle" aria-hidden="true">dns</span>
            <span class="text-[11px] leading-none font-semibold text-muted" aria-hidden="true">Local</span>
            <span class="sr-only">
              Local test server ({{ s.address }}). Logins made here exist only on this computer.
            </span>
          </p>
        }
        @case ('nav') {
          <p
            role="note"
            class="mb-3 flex flex-none items-start gap-2 rounded-lg border border-border/80 bg-surface-sunken px-3 py-2 text-xs leading-[1.4] text-muted"
          >
            <span class="icon text-[18px] leading-none text-subtle" aria-hidden="true">dns</span>
            <span>
              <strong class="font-medium text-fg">Local test server ({{ s.address }}).</strong>
              Logins made here exist only on this computer: staff sign in from a staff app on the
              local server, not a <code>dart_define.prod.json</code> build.
              @if (s.mailUrl) {
                <a
                  class="underline text-fg hover:text-primary transition-colors"
                  [href]="s.mailUrl"
                  target="_blank"
                  rel="noopener"
                  >Local mailbox</a
                >
              }
            </span>
          </p>
        }
        @default {
          <p
            role="note"
            class="flex items-start gap-2 rounded-lg border border-border/80 bg-surface-sunken px-3 py-2.5 text-xs leading-[1.45] text-muted"
          >
            <span class="icon text-[16px] leading-none text-subtle" aria-hidden="true">dns</span>
            <span>
              <strong class="font-medium text-fg">Local test server ({{ s.address }}).</strong>
              Logins and invitations made here exist only on this computer. Staff sign in from a
              staff app run on the local server (<code>tool/dev_run.sh</code>, on a simulator or
              emulator); an app built with <code>dart_define.prod.json</code> uses the hosted
              server and won't find them.
              @if (s.mailUrl) {
                Invitation e-mails arrive in the
                <a
                  class="underline text-fg hover:text-primary transition-colors"
                  [href]="s.mailUrl"
                  target="_blank"
                  rel="noopener"
                  >local mailbox</a
                >, not in real inboxes.
              }
            </span>
          </p>
        }
      }
    }
  `,
})
export class LocalServerNote {
  readonly variant = input<'card' | 'nav' | 'rail'>('card');
  protected readonly server = inject(LOCAL_SERVER);
}
