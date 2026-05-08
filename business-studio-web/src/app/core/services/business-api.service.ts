import { Injectable, inject } from '@angular/core';
import { businessFunctionsBaseUrl } from '../firebase.config';
import {
  AddressSuggestion,
  BusinessClaimResponse,
  BusinessGoogleProfileLink,
  BusinessOnboardingRecoveryResponse,
  DocumentVerificationFailureDetails,
  DocumentVerificationInput,
  DocumentVerificationReview,
  DocumentVerificationResult,
  GoogleBusinessIdentity,
  NearbyPlace,
} from '../models/business.models';
import { FirebaseAuthService } from './firebase-auth.service';

@Injectable({ providedIn: 'root' })
export class BusinessApiService {
  private readonly auth = inject(FirebaseAuthService);

  async searchBusinessSuggestions(queryText: string): Promise<AddressSuggestion[]> {
    const payload = await this.postJson<{ suggestions?: AddressSuggestion[] }>(
      'googleMapsAddressSuggestions',
      {
        query: queryText,
      },
    );

    return Array.isArray(payload.suggestions) ?payload.suggestions : [];
  }

  async searchBusinesses(queryText: string): Promise<NearbyPlace[]> {
    const payload = await this.postJson<{ places?: NearbyPlace[] }>('googleMapsBusinessSearch', {
      query: queryText,
    });

    const places = Array.isArray(payload.places) ?payload.places : [];
    if (!places.length) {
      throw new Error(
        'Für diese Suche hat Google Places gerade keine passenden Standorte geliefert. Versuche Name plus Stadt oder Straße.',
      );
    }

    return places;
  }

  async verifyGoogleBusinessPlace(
    place: NearbyPlace,
    identity: GoogleBusinessIdentity,
  ): Promise<BusinessGoogleProfileLink> {
    const payload = await this.postJson<{
      link?: BusinessGoogleProfileLink;
      locations?: BusinessGoogleProfileLink[];
    }>('googleBusinessAccessibleLocations', {
      accessToken: identity.accessToken,
      googleEmail: identity.email,
      placeId: place.id,
    });

    const matches = Array.isArray(payload.locations)
      ?payload.locations
      : payload.link
        ?[payload.link]
        : [];

    const exactMatch = matches.find((entry) => entry.placeId === place.id);
    if (!exactMatch) {
      throw new Error(
        'Dieses Google-Business-Konto hat keinen bestätigten Verwaltungszugriff auf genau diesen Standort.',
      );
    }

    return exactMatch;
  }

  async verifyGoogleBusinessCompanyIdentity(
    place: NearbyPlace,
    identity: GoogleBusinessIdentity,
  ): Promise<BusinessGoogleProfileLink> {
    const website = String(place.websiteUrl || '').trim();
    if (!website) {
      throw new Error(
        'Für diesen Standort ist keine offizielle Website hinterlegt. Die alternative Google-Unternehmensprüfung ist deshalb gerade nicht möglich.',
      );
    }

    const payload = await this.postJson<{ link?: BusinessGoogleProfileLink }>(
      'googleBusinessVerifyCompanyIdentity',
      {
        accessToken: identity.accessToken,
        googleEmail: identity.email,
        placeId: place.id,
        placeName: place.name,
        placeAddress: place.address,
        placeCity: inferCityFromAddress(place.address),
        website,
      },
    );

    if (!payload.link) {
      throw new Error(
        'Die bestätigte Unternehmens-Identität konnte für diesen Standort gerade nicht sauber übernommen werden.',
      );
    }

    return payload.link;
  }

  async verifyBusinessDocuments(
    input: DocumentVerificationInput,
  ): Promise<DocumentVerificationResult> {
    const payload = await this.postJson<DocumentVerificationResult>(
      'verifyBusinessEvidenceDocument',
      {
        claimantName: input.claimantName,
        claimedBusinessEmail: input.businessEmail,
        placeId: input.place.id,
        placeName: input.place.name,
        placeAddress: input.place.address,
        fileName: input.fileName,
        mimeType: input.mimeType,
        fileBase64: input.fileBase64,
        captchaToken: input.captchaToken || '',
      },
    );

    if (!payload.link && !payload.pendingManualReview) {
      throw new Error(
        'Die Dokumentenprüfung konnte keine sichere Business-Identität für diesen Standort bestätigen.',
      );
    }

    return {
      link: payload.link ?? null,
      review: payload.review ?? null,
      details: payload.details ?? null,
      pendingManualReview: payload.pendingManualReview ?? false,
      auditId: payload.auditId ?? null,
    };
  }

  async claimBusinessStudio(input: {
    firebaseIdToken: string;
    claimantName: string;
    place: NearbyPlace;
    link: BusinessGoogleProfileLink;
    documentReview?: DocumentVerificationReview | null;
  }): Promise<BusinessClaimResponse> {
    const user = this.auth.currentUser;
    if (!user?.email) {
      throw new Error('Keine aktive Business-Session vorhanden.');
    }
    if (!user.emailVerified) {
      throw new Error('Bitte bestätige zuerst die E-Mail deines Business-Kontos.');
    }

    return this.postJson<BusinessClaimResponse>('claimBusinessStudio', {
      firebaseIdToken: input.firebaseIdToken,
      claimantName: input.claimantName,
      place: input.place,
      link: input.link,
      documentReview: input.documentReview ?? null,
    });
  }

  async recoverBusinessOnboardingContext(
    firebaseIdToken: string,
    options: {
      completeIfPossible?: boolean;
      claimantName?: string;
      verificationSessionId?: string;
      placeId?: string;
      place?: NearbyPlace;
      link?: BusinessGoogleProfileLink;
      documentReview?: DocumentVerificationReview | null;
    } = {},
  ): Promise<BusinessOnboardingRecoveryResponse> {
    return this.postJson<BusinessOnboardingRecoveryResponse>('recoverBusinessOnboardingContext', {
      firebaseIdToken,
      completeIfPossible: options.completeIfPossible === true,
      claimantName: options.claimantName || '',
      verificationSessionId: options.verificationSessionId || '',
      placeId: options.placeId || '',
      place: options.place ?? null,
      link: options.link ?? null,
      documentReview: options.documentReview ?? null,
    });
  }

  async repairBusinessStudioProfile(firebaseIdToken: string): Promise<BusinessClaimResponse> {
    return this.postJson<BusinessClaimResponse>('repairBusinessStudioProfile', {
      firebaseIdToken,
    });
  }

  async upsertBusinessStudioDeal<T>(input: {
    firebaseIdToken: string;
    id?: string | null;
    payload: unknown;
  }): Promise<{ id: string; item: T }> {
    return this.postJson<{ id: string; item: T }>('upsertBusinessStudioDeal', {
      firebaseIdToken: input.firebaseIdToken,
      id: input.id || '',
      payload: input.payload,
    });
  }

  async deleteBusinessStudioDeal(input: {
    firebaseIdToken: string;
    id: string;
  }): Promise<{ id: string; deleted: boolean }> {
    return this.postJson<{ id: string; deleted: boolean }>('deleteBusinessStudioDeal', input);
  }

  async upsertBusinessStudioStory<T>(input: {
    firebaseIdToken: string;
    id?: string | null;
    payload: unknown;
  }): Promise<{ id: string; item: T }> {
    return this.postJson<{ id: string; item: T }>('upsertBusinessStudioStory', {
      firebaseIdToken: input.firebaseIdToken,
      id: input.id || '',
      payload: input.payload,
    });
  }

  async deleteBusinessStudioStory(input: {
    firebaseIdToken: string;
    id: string;
  }): Promise<{ id: string; deleted: boolean }> {
    return this.postJson<{ id: string; deleted: boolean }>('deleteBusinessStudioStory', input);
  }

  async generateBusinessStudioContent(input: {
    firebaseIdToken: string;
    kind: 'profile' | 'deal' | 'story';
    draft: unknown;
  }): Promise<{
    profile?: {
      tagline?: string;
      shortDescription?: string;
      website?: string;
      phone?: string;
      contactEmail?: string;
      legalEntityName?: string;
    };
    deal?: {
      title?: string;
      subtitle?: string;
      description?: string;
      savingsPercent?: number;
      availabilityLabel?: string;
      imageUrl?: string;
    };
    story?: {
      label?: string;
      subtitle?: string;
      body?: string;
      ctaLabel?: string;
      imageUrl?: string;
    };
  }> {
    return this.postJson('generateBusinessStudioContent', input);
  }

  async deleteOwnedBusinessAccount(input: {
    firebaseIdToken: string;
    confirmation: string;
  }): Promise<{
    deleted: boolean;
    businessId: string;
    counts: Record<string, number>;
  }> {
    return this.postJson('deleteOwnedBusinessAccount', input);
  }

  private async postJson<T>(functionName: string, body: unknown): Promise<T> {
    const response = await fetch(`${businessFunctionsBaseUrl}/${functionName}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    const payload = (await response.json().catch(() => ({}))) as {
      error?: string;
      detail?: string;
      message?: string;
      details?: DocumentVerificationFailureDetails;
    } & T;
    if (!response.ok) {
      const error = new Error(
        payload.error?.trim() ||
          payload.message?.trim() ||
          payload.detail?.trim() ||
          'Die Business-Aktion konnte gerade nicht abgeschlossen werden.',
      ) as Error & { details?: DocumentVerificationFailureDetails };
      if (payload.details) {
        error.details = payload.details;
      }
      throw error;
    }

    return payload;
  }
}

function inferCityFromAddress(address: string): string {
  const parts = String(address || '').split(',').map((part) => part.trim()).filter(Boolean);
  if (parts.length >= 2) {
    return parts[parts.length - 2].replace(/^\d{5}\s+/, '').trim();
  }
  const postalMatch = String(address || '').match(/\b\d{5}\s+([^,]+)/);
  return postalMatch?.[1]?.trim() || '';
}

