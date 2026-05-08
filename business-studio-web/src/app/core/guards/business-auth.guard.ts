import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { FirebaseAuthService } from '../services/firebase-auth.service';

export const businessAuthGuard: CanActivateFn = async (_route, state) => {
  const auth = inject(FirebaseAuthService);
  const router = inject(Router);

  await auth.waitForBootstrap();

  if (!auth.isAuthenticated()) {
    return router.createUrlTree(['/business-register'], {
      queryParams: { redirect: state.url },
    });
  }

  if (!auth.isBusinessAccount()) {
    await auth.forceBusinessIsolation();
    return router.createUrlTree(['/business-register'], {
      queryParams: { mismatch: 'user-account' },
    });
  }

  return true;
};
