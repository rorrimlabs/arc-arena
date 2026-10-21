import { Signal, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, NavigationEnd, Params, Router } from '@angular/router';
import { filter, map } from 'rxjs';

/**
 * The path params of the routes below the calling page's route, merged (e.g. `section` and `tab`
 * of `/settings/:section/:tab`). Component input binding only binds a route's own params, and a
 * page keeps its list mounted by matching its selection as componentless child routes.
 */
export function childParams(): Signal<Params> {
  const route = inject(ActivatedRoute);
  const read = (): Params => {
    const params: Params = {};
    // The snapshot tree, not route.firstChild: on a first visit the child routes are not
    // activated yet while the page is constructed (their snapshot is still unset).
    for (let r = route.snapshot?.firstChild; r; r = r.firstChild) Object.assign(params, r.params);
    return params;
  };
  return toSignal(
    inject(Router).events.pipe(
      filter((e) => e instanceof NavigationEnd),
      map(read),
    ),
    { initialValue: read() },
  );
}
