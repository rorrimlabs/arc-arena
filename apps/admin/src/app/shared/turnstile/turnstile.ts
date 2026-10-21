import { DOCUMENT, isPlatformBrowser } from '@angular/common';
import {
  Component,
  DestroyRef,
  ElementRef,
  PLATFORM_ID,
  Service,
  afterNextRender,
  computed,
  inject,
  signal,
  viewChild,
} from '@angular/core';
import { environment } from '../../../environments/environment';

/** The part of Cloudflare's Turnstile API the dashboard uses. */
interface TurnstileApi {
  render(
    el: HTMLElement,
    options: {
      sitekey: string;
      theme?: 'auto' | 'light' | 'dark';
      callback: (token: string) => void;
      'expired-callback': () => void;
      'error-callback': () => void;
    },
  ): string;
  reset(id: string): void;
  remove(id: string): void;
}

const SCRIPT = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';

/**
 * Bot protection for the public Auth calls (sign-up, sign-in, password reset, invitations):
 * Supabase Auth refuses them without a CAPTCHA token once CAPTCHA is turned on for the project.
 * Off while `environment.turnstileSiteKey` is empty (the local stack has no CAPTCHA). The
 * widget on the page ([Turnstile]) puts its token here; the Auth call takes it, and since a
 * token works once, the widget is reset for the next try.
 */
@Service()
export class Captcha {
  readonly siteKey: string = (environment as { turnstileSiteKey?: string }).turnstileSiteKey ?? '';
  readonly enabled = this.siteKey !== '';
  private readonly token = signal<string | null>(null);
  /** True when a form may submit: CAPTCHA is off, or the widget has a token. */
  readonly ready = computed(() => !this.enabled || this.token() !== null);
  private resetWidget: (() => void) | null = null;

  /** Called by the widget. */
  set(token: string | null, reset: (() => void) | null): void {
    this.token.set(token);
    this.resetWidget = reset;
  }

  /** The token for one Auth call (undefined when CAPTCHA is off); the widget then starts over. */
  take(): string | undefined {
    if (!this.enabled) return undefined;
    const token = this.token() ?? undefined;
    this.token.set(null);
    this.resetWidget?.();
    return token;
  }
}

let loading: Promise<TurnstileApi> | null = null;

function loadTurnstile(document: Document): Promise<TurnstileApi> {
  const win = document.defaultView as (Window & { turnstile?: TurnstileApi }) | null;
  if (win?.turnstile) return Promise.resolve(win.turnstile);
  loading ??= new Promise<TurnstileApi>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = SCRIPT;
    script.async = true;
    script.onload = () => (win?.turnstile ? resolve(win.turnstile) : reject(new Error('turnstile')));
    script.onerror = () => {
      loading = null;
      reject(new Error('turnstile'));
    };
    document.head.appendChild(script);
  });
  return loading;
}

/** The Turnstile check, placed in a form above its submit button; nothing when CAPTCHA is off. */
@Component({
  selector: 'app-turnstile',
  template: `
    @if (captcha.enabled) {
      <div #box class="min-h-[65px]"></div>
      @if (failed()) {
        <p role="alert" class="text-[13px] leading-[1.45] text-danger">
          The security check couldn't load. Check the connection and reload the page.
        </p>
      }
    }
  `,
})
export class Turnstile {
  protected readonly captcha = inject(Captcha);
  private readonly box = viewChild<ElementRef<HTMLElement>>('box');
  protected readonly failed = signal(false);
  private widget: string | null = null;
  private api: TurnstileApi | null = null;

  constructor() {
    const document = inject(DOCUMENT);
    const browser = isPlatformBrowser(inject(PLATFORM_ID));
    afterNextRender(async () => {
      const el = this.box()?.nativeElement;
      if (!browser || !this.captcha.enabled || !el) return;
      try {
        const api = (this.api = await loadTurnstile(document));
        const reset = () => this.widget && api.reset(this.widget);
        this.widget = api.render(el, {
          sitekey: this.captcha.siteKey,
          theme: 'auto',
          callback: (token) => this.captcha.set(token, reset),
          'expired-callback': () => this.captcha.set(null, reset),
          'error-callback': () => this.captcha.set(null, reset),
        });
      } catch {
        this.failed.set(true);
      }
    });
    inject(DestroyRef).onDestroy(() => {
      if (this.widget) this.api?.remove(this.widget);
      this.captcha.set(null, null);
    });
  }
}
