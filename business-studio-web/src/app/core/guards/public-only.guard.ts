import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { FirebaseAuthService } from '../services/firebase-auth.service';

export const publicOnlyGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(FirebaseAuthService);
  const router = inject(Router);

  await auth.waitForBootstrap();

  if (!auth.isAuthenticated()) {
    return true;
  }

  if (!auth.isBusinessAccount()) {
    await auth.forceBusinessIsolation();
    return true;
  }

  const wantsBusinessRegistration =
    state.url.startsWith('/business-register') &&
    (state.url.includes('continueBusinessRegistration=1') || state.url.includes('mode=business-registration'));
  if (!auth.profile()?.ownedBusinessId && wantsBusinessRegistration) {
    return true;
  }

  const target = auth.profile()?.ownedBusinessId
    ? '/business-studio'
    : '/business-onboarding';

  return router.createUrlTree([target], {
    queryParams:
      target === '/business-onboarding' && state.url !== '/business-register'
        ? { redirect: state.url }
        : undefined,
  });
};
