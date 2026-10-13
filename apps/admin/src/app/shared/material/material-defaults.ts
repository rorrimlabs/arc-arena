import { Provider } from '@angular/core';
import { MAT_FORM_FIELD_DEFAULT_OPTIONS } from '@angular/material/form-field';
import { MAT_ICON_DEFAULT_OPTIONS } from '@angular/material/icon';

/**
 * Material defaults for the design: outlined fields without required markers (hints and errors
 * take space only when shown), and <mat-icon> in Material Symbols Outlined (index.html).
 *
 * Provide these in each lazy feature route (`providers`) and in each dialog component — not in
 * app.config: importing the tokens there pulls Material and @angular/forms into the initial
 * bundle. Dialogs need their own copy because MatDialog builds them from the root injector.
 */
export const MATERIAL_DEFAULTS: Provider[] = [
  {
    provide: MAT_FORM_FIELD_DEFAULT_OPTIONS,
    useValue: { appearance: 'outline', subscriptSizing: 'dynamic', hideRequiredMarker: true },
  },
  { provide: MAT_ICON_DEFAULT_OPTIONS, useValue: { fontSet: 'material-symbols-outlined' } },
];
