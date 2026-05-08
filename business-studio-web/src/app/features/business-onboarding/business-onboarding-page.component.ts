import { CommonModule } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';

import { BusinessApiService } from '../../core/services/business-api.service';
import { BusinessFlowService } from '../../core/services/business-flow.service';
import { FirebaseAuthService } from '../../core/services/firebase-auth.service';

@Component({
  selector: 'app-business-onboarding-page',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './business-onboarding-page.component.html',
  styleUrl: './business-onboarding-page.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class BusinessOnboardingPageComponent {
  private readonly auth = inject(FirebaseAuthService);
  private readonly flow = inject(BusinessFlowService);
  private readonly api = inject(BusinessApiService);
  private readonly router = inject(Router);

  readonly profile = this.auth.profile;
  readonly currentUser = this.auth.firebaseUser;
  readonly selectedPlace = this.flow.selectedPlace;
  readonly verificationLink = this.flow.verificationLink;
  readonly claimantName = this.flow.claimantName;
  readonly documentReview = this.flow.documentReview;
  readonly businessEmail = computed(
    () => this.verificationLink()?.googleUserEmail || this.currentUser()?.email || '',
  );
  readonly completionBlocker = computed(() => {
    if (!this.selectedPlace() || !this.verificationLink()) {
      return 'Standort und Verifikation fehlen. Oeffne die Registrierung erneut oder lade diese Seite nach erfolgreicher Pruefung neu.';
    }
    if (!this.currentUser()) {
      return 'Melde dich mit deinem Business-Konto an, damit wir das Studio freischalten koennen.';
    }
    if (!this.currentUser()?.emailVerified) {
      return 'Bestaetige zuerst die Business-Mail und aktualisiere danach den Status.';
    }
    return '';
  });
  readonly canFinish = computed(
    () =>
      !!this.selectedPlace() &&
      !!this.verificationLink() &&
      !!this.currentUser() &&
      !!this.currentUser()?.emailVerified,
  );
  readonly busy = signal(false);
  readonly recovering = signal(false);
  readonly error = signal('');

  constructor() {
    void this.recoverOnboardingContext();
  }

  async refreshVerification(): Promise<void> {
    this.error.set('');
    await this.auth.refreshEmailVerification();
    if (!this.currentUser()?.emailVerified) {
      this.error.set('Die Business-Mail ist noch nicht bestaetigt. Bitte oeffne zuerst den Link aus deiner E-Mail.');
    }
  }

  async finishSetup(): Promise<void> {
    const place = this.selectedPlace();
    const link = this.verificationLink();
    const claimantName =
      this.claimantName() || link?.accountDisplayName || link?.googleUserEmail || this.currentUser()?.email || '';
    if (!place || !link || !claimantName) {
      this.error.set('Die Business-Verifikation ist noch nicht vollstaendig. Starte die Freischaltung bitte erneut.');
      return;
    }

    this.busy.set(true);
    this.error.set('');
    try {
      const firebaseIdToken = await this.auth.getIdToken(true);
      const businessId = await this.createOrAttachBusinessStudio(firebaseIdToken, claimantName, place, link);
      if (!businessId) {
        throw new Error(
          'Die Studio-Freischaltung konnte keine Business-Zuordnung erstellen. Bitte pruefe, ob Standort, Nachweis und Business-Mail zur selben Firma gehoeren.',
        );
      }
      await this.auth.markBusinessOnboardingComplete(businessId);
      this.flow.clear();
      await this.router.navigateByUrl('/business-studio');
    } catch (error) {
      this.error.set(normalizeError(error));
    } finally {
      this.busy.set(false);
    }
  }

  async logout(): Promise<void> {
    this.flow.clear();
    await this.auth.logout();
  }

  async continueRegistration(): Promise<void> {
    this.error.set('');
    this.flow.clear();
    await this.router.navigate(['/business-register'], {
      queryParams: {
        continueBusinessRegistration: '1',
        mode: 'business-registration',
      },
    });
  }

  private async recoverOnboardingContext(): Promise<void> {
    await this.auth.waitForBootstrap();
    const profile = this.profile();
    if (profile?.ownedBusinessId) {
      await this.router.navigateByUrl('/business-studio');
      return;
    }
    if (this.flow.restoreOnboardingContext()) {
      return;
    }
    if (!this.currentUser()) {
      return;
    }

    this.recovering.set(true);
    this.error.set('');
    try {
      const firebaseIdToken = await this.auth.getIdToken(true);
      const recovered = await this.api.recoverBusinessOnboardingContext(firebaseIdToken);
      const recoveredBusinessId = String(recovered.businessId || '').trim();
      if (recoveredBusinessId) {
        await this.auth.markBusinessOnboardingComplete(recoveredBusinessId);
        this.flow.clear();
        await this.router.navigateByUrl('/business-studio');
        return;
      }
      if (recovered.context) {
        this.flow.restoreFromServerContext(recovered.context);
        return;
      }
      this.error.set('');
    } catch (error) {
      this.error.set(normalizeError(error));
    } finally {
      this.recovering.set(false);
    }
  }

  private async completeStudioFromVerifiedContext(firebaseIdToken: string): Promise<string> {
    const link = this.verificationLink();
    const place = this.selectedPlace();
    const recovered = await this.api.recoverBusinessOnboardingContext(firebaseIdToken, {
      completeIfPossible: true,
      claimantName: this.claimantName() || this.verificationLink()?.accountDisplayName || this.currentUser()?.email || '',
      verificationSessionId: link?.verificationSessionId || '',
      placeId: place?.id || link?.placeId || '',
      place: place ?? undefined,
      link: link ?? undefined,
      documentReview: this.documentReview(),
    });
    return String(recovered.businessId || '').trim();
  }

  private async createOrAttachBusinessStudio(
    firebaseIdToken: string,
    claimantName: string,
    place: NonNullable<ReturnType<BusinessOnboardingPageComponent['selectedPlace']>>,
    link: NonNullable<ReturnType<BusinessOnboardingPageComponent['verificationLink']>>,
  ): Promise<string> {
    let lastError: unknown = null;

    try {
      const businessId = await this.completeStudioFromVerifiedContext(firebaseIdToken);
      if (businessId) {
        return businessId;
      }
    } catch (error) {
      lastError = error;
    }

    try {
      const businessId = await this.claimStudioFromLegacySession(firebaseIdToken, claimantName, place, link);
      if (businessId) {
        return businessId;
      }
    } catch (error) {
      lastError = error;
    }

    if (lastError) {
      throw lastError;
    }
    return '';
  }

  private async claimStudioFromLegacySession(
    firebaseIdToken: string,
    claimantName: string,
    place: NonNullable<ReturnType<BusinessOnboardingPageComponent['selectedPlace']>>,
    link: NonNullable<ReturnType<BusinessOnboardingPageComponent['verificationLink']>>,
  ): Promise<string> {
    const result = await this.api.claimBusinessStudio({
      firebaseIdToken,
      claimantName,
      place,
      link,
      documentReview: this.documentReview(),
    });
    return resolveBusinessId(result);
  }
}

function normalizeError(error: unknown): string {
  if (error instanceof Error && error.message.trim()) {
    return error.message.trim();
  }
  return 'Das Studio konnte die Freischaltung gerade nicht sauber abschliessen.';
}

function resolveBusinessId(result: unknown): string {
  if (!result || typeof result !== 'object') {
    return '';
  }
  const payload = result as {
    businessId?: unknown;
    business?: { id?: unknown };
    data?: unknown;
    result?: unknown;
  };
  const direct = String(payload.businessId || payload.business?.id || '').trim();
  if (direct) {
    return direct;
  }
  return resolveBusinessId(payload.data) || resolveBusinessId(payload.result);
}
