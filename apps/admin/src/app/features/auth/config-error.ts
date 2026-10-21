import { Component, inject } from '@angular/core';
import { Supabase } from '../../core/supabase/supabase';
import { AuthCard } from './auth-card';

/**
 * Shown for every URL when the build cannot be used as configured (missing, local or secret
 * Supabase settings): nothing else loads, so no request is made with the bad settings.
 */
@Component({
  selector: 'app-config-error',
  imports: [AuthCard],
  template: `
    <app-auth-card
      heading="Setup needed"
      subtitle="This copy of the dashboard cannot connect to its server."
    >
      <p role="alert" class="text-sm leading-[1.45] font-medium text-danger">{{ problem }}</p>
      <p class="text-sm leading-[1.45] text-muted">
        Nothing you enter here can fix this. Ask whoever deploys the dashboard to correct the build
        settings and publish it again.
      </p>
    </app-auth-card>
  `,
})
export class ConfigError {
  protected readonly problem =
    inject(Supabase).configProblem ?? 'This build is not configured correctly.';
}
