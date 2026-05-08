import { Injectable, computed, signal } from '@angular/core';

import {
  BusinessOnboardingContext,
  BusinessGoogleProfileLink,
  DocumentVerificationReview,
  NearbyPlace,
} from '../models/business.models';

interface BusinessFlowDraft {
  claimantName: string;
  businessEmail: string;
  place: NearbyPlace | null;
  verificationLink: BusinessGoogleProfileLink | null;
  verificationMode: 'google' | 'document' | '';
  documentReview: DocumentVerificationReview | null;
}

const LEGACY_STORAGE_KEY = 'spargo.businessStudio.flowDraft.v1';
const ONBOARDING_CONTEXT_STORAGE_KEY = 'spargo.businessStudio.onboardingContext.v1';

@Injectable({ providedIn: 'root' })
export class BusinessFlowService {
  private readonly state = signal<BusinessFlowDraft>(emptyDraft());

  readonly draft = computed(() => this.state());
  readonly selectedPlace = computed(() => this.state().place);
  readonly claimantName = computed(() => this.state().claimantName);
  readonly businessEmail = computed(() => this.state().businessEmail);
  readonly verificationLink = computed(() => this.state().verificationLink);
  readonly verificationMode = computed(() => this.state().verificationMode);
  readonly documentReview = computed(() => this.state().documentReview);
  readonly isReadyForOnboarding = computed(
    () => !!this.state().place && !!this.state().verificationLink && !!this.state().businessEmail,
  );

  constructor() {
    if (typeof window !== 'undefined') {
      try {
        window.sessionStorage.removeItem(LEGACY_STORAGE_KEY);
      } catch {
        // ignore storage access quirks
      }
    }
    this.restoreOnboardingContext();
  }

  restoreOnboardingContext(): boolean {
    if (this.state().place && this.state().verificationLink) {
      return true;
    }
    if (typeof window === 'undefined') {
      return false;
    }

    try {
      const raw =
        window.localStorage.getItem(ONBOARDING_CONTEXT_STORAGE_KEY) ||
        window.sessionStorage.getItem(ONBOARDING_CONTEXT_STORAGE_KEY);
      if (!raw) {
        return false;
      }
      const parsed = JSON.parse(raw) as Partial<BusinessFlowDraft> | null;
      if (!parsed || typeof parsed !== 'object') {
        return false;
      }

      const next: BusinessFlowDraft = {
        claimantName: typeof parsed.claimantName === 'string' ? parsed.claimantName.trim() : '',
        businessEmail: typeof parsed.businessEmail === 'string' ? parsed.businessEmail.trim().toLowerCase() : '',
        place: parsed.place ?? null,
        verificationLink: parsed.verificationLink ?? null,
        verificationMode:
          parsed.verificationMode === 'google' || parsed.verificationMode === 'document'
            ? parsed.verificationMode
            : '',
        documentReview: parsed.documentReview ?? null,
      };

      if (!next.place || !next.verificationLink) {
        return false;
      }

      this.state.set(next);
      return true;
    } catch {
      return false;
    }
  }

  setSelectedPlace(place: NearbyPlace | null): void {
    this.patchState({
      place,
      verificationLink: null,
      verificationMode: '',
      businessEmail: '',
      documentReview: null,
    });
  }

  setClaimantName(name: string): void {
    this.patchState({ claimantName: name.trim() });
  }

  setBusinessEmail(email: string): void {
    this.patchState({ businessEmail: email.trim().toLowerCase() });
  }

  setVerification(
    link: BusinessGoogleProfileLink,
    mode: 'google' | 'document',
    documentReview: DocumentVerificationReview | null = null,
  ): void {
    this.patchState({
      verificationLink: link,
      verificationMode: mode,
      businessEmail: link.googleUserEmail.trim().toLowerCase(),
      documentReview,
    });
  }

  clearVerification(): void {
    this.patchState({
      verificationLink: null,
      verificationMode: '',
      documentReview: null,
    });
  }

  consumeSnapshot(): BusinessFlowDraft {
    return structuredClone(this.state());
  }

  restoreFromServerContext(context: BusinessOnboardingContext): void {
    this.patchState({
      claimantName: context.claimantName.trim(),
      businessEmail: context.businessEmail.trim().toLowerCase(),
      place: context.place,
      verificationLink: context.verificationLink,
      verificationMode: context.verificationMode,
      documentReview: context.documentReview ?? null,
    });
  }

  clear(): void {
    this.state.set({
      claimantName: '',
      businessEmail: '',
      place: null,
      verificationLink: null,
      verificationMode: '',
      documentReview: null,
    });
    this.clearOnboardingContext();
  }

  private patchState(patch: Partial<BusinessFlowDraft>): void {
    const next = {
      ...this.state(),
      ...patch,
    };
    this.state.set(next);
    this.persistOnboardingContext(next);
  }

  private persistOnboardingContext(next: BusinessFlowDraft): void {
    if (typeof window === 'undefined') {
      return;
    }

    try {
      if (next.place && next.verificationLink && next.businessEmail) {
        const serialized = JSON.stringify(next);
        window.localStorage.setItem(ONBOARDING_CONTEXT_STORAGE_KEY, serialized);
        window.sessionStorage.setItem(ONBOARDING_CONTEXT_STORAGE_KEY, serialized);
      } else {
        this.clearOnboardingContext();
      }
    } catch {
      // ignore storage quirks
    }
  }

  private clearOnboardingContext(): void {
    if (typeof window === 'undefined') {
      return;
    }

    try {
      window.localStorage.removeItem(ONBOARDING_CONTEXT_STORAGE_KEY);
      window.sessionStorage.removeItem(ONBOARDING_CONTEXT_STORAGE_KEY);
    } catch {
      // ignore storage quirks
    }
  }
}

function emptyDraft(): BusinessFlowDraft {
  return {
    claimantName: '',
    businessEmail: '',
    place: null,
    verificationLink: null,
    verificationMode: '',
    documentReview: null,
  };
}
