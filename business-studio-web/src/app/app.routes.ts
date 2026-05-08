import { Routes } from '@angular/router';

import { businessAuthGuard } from './core/guards/business-auth.guard';
import { publicOnlyGuard } from './core/guards/public-only.guard';
import { BusinessAuthPageComponent } from './features/business-auth/business-auth-page.component';
import { BusinessOnboardingPageComponent } from './features/business-onboarding/business-onboarding-page.component';
import { BusinessStudioPageComponent } from './features/business-studio/business-studio-page.component';

export const routes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    redirectTo: 'business-register',
  },
  {
    path: 'business-register',
    canActivate: [publicOnlyGuard],
    component: BusinessAuthPageComponent,
  },
  {
    path: 'business-onboarding',
    canActivate: [businessAuthGuard],
    component: BusinessOnboardingPageComponent,
  },
  {
    path: 'business-studio',
    canActivate: [businessAuthGuard],
    component: BusinessStudioPageComponent,
  },
  {
    path: '**',
    redirectTo: 'business-register',
  },
];
