export interface NearbyPlace {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  primaryType: string;
  types: string[];
  rating: number;
  userRatingCount: number;
  openNow?: boolean | null;
  photoUrl?: string | null;
  googleMapsUri?: string | null;
  websiteUrl?: string | null;
  registeredBusinessId?: string;
  registeredBusinessName?: string;
  registeredBusinessStatus?: string;
}

export interface AddressSuggestion {
  title: string;
  addressLine: string;
}

export interface BusinessGoogleProfileLink {
  googleUserEmail: string;
  accountName: string;
  accountDisplayName: string;
  verificationSessionId: string;
  placeId: string;
  locationName: string;
  locationDisplayName: string;
  locationAddress: string;
  locationCity: string;
  website: string;
  phone: string;
  role: string;
}

export interface GoogleBusinessIdentity {
  email: string;
  accessToken: string;
  displayName: string;
}

export interface RegisterDraft {
  businessName: string;
  claimantName: string;
  businessEmail: string;
  password: string;
  place: NearbyPlace | null;
  googleLink: BusinessGoogleProfileLink | null;
}

export interface BusinessUserProfile {
  uid: string;
  email: string;
  emailVerified: boolean;
  displayName: string;
  accountType: 'business' | 'user' | '';
  ownedBusinessId: string;
  businessOnboardingComplete: boolean;
}

export interface VerificationProgressStep {
  title: string;
  detail: string;
  state: 'idle' | 'active' | 'done' | 'error';
}

export interface DocumentVerificationInput {
  claimantName: string;
  businessEmail: string;
  place: NearbyPlace;
  fileName: string;
  mimeType: string;
  fileBase64: string;
  captchaToken?: string;
}

export interface DocumentVerificationReview {
  documentType: string;
  legalEntityName: string;
  tradeName: string;
  issuingAuthority: string;
  city: string;
  countryCode: string;
  vatSignalVerified: boolean;
  registerSignalVerified: boolean;
  officialDocumentVerified: boolean;
  representativeMatch: boolean;
  emailMatch: boolean;
}

export interface DocumentVerificationFailureDetails {
  summary: string;
  reasons: string[];
  suggestedFocus: 'upload' | 'name' | 'email' | 'search';
  matchedSignals: string[];
  missingSignals: string[];
  requiresManualReview?: boolean;
  reviewStatus?: 'rejected' | 'manual_review';
  score?: number;
  auditId?: string;
  extracted: {
    documentType: string;
    legalEntityName: string;
    tradeName: string;
    proprietorName: string;
    issuingAuthority: string;
    street: string;
    postalCode: string;
    city: string;
  };
}

export interface DocumentVerificationResult {
  link: BusinessGoogleProfileLink | null;
  review: DocumentVerificationReview | null;
  details?: DocumentVerificationFailureDetails | null;
  pendingManualReview?: boolean;
  auditId?: string | null;
}

export interface BusinessOnboardingContext {
  claimantName: string;
  businessEmail: string;
  place: NearbyPlace;
  verificationLink: BusinessGoogleProfileLink;
  verificationMode: 'google' | 'document';
  documentReview: DocumentVerificationReview | null;
}

export interface BusinessOnboardingRecoveryResponse {
  businessId: string;
  context: BusinessOnboardingContext | null;
}

export interface StudioBusinessRecord {
  id: string;
  name: string;
  tagline: string;
  shortDescription: string;
  description: string;
  city: string;
  address: string;
  website: string;
  phone: string;
  contactEmail: string;
  legalEntityName: string;
  claimedByName: string;
  claimedByRole: string;
  verificationStatus: string;
  verificationMethod?: string;
  verificationPlaceId?: string;
  verificationNote?: string;
  imageUrl: string;
  followerCount: number;
  reviewCount: number;
  analytics?: {
    views: number;
    saves: number;
    activations: number;
    redemptions: number;
    reach: number;
  } | null;
  documentReview?: DocumentVerificationReview | null;
  googleProfileLink?: BusinessGoogleProfileLink | null;
}

export interface ManualReviewCase {
  auditId: string;
  status: 'manual_review' | 'approved' | 'rejected';
  identityEmail: string;
  identityName: string;
  claimantName: string;
  placeId: string;
  placeName: string;
  placeAddress: string;
  fileName: string;
  score: number;
  createdAtLabel: string;
  summary: string;
  matchedSignals: string[];
  missingSignals: string[];
  extracted: {
    documentType: string;
    legalEntityName: string;
    tradeName: string;
    proprietorName: string;
    issuingAuthority: string;
    street: string;
    postalCode: string;
    city: string;
  };
}

export interface BusinessClaimResponse {
  businessId: string;
  attached: boolean;
  business: StudioBusinessRecord;
}
