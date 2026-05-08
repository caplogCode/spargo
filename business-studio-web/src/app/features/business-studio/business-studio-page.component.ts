import { CommonModule } from '@angular/common';
import { CUSTOM_ELEMENTS_SCHEMA, ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import {
  personCircleOutline,
  searchOutline,
  settingsOutline,
  sparklesOutline,
} from 'ionicons/icons';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

import {
  DocumentVerificationReview,
  ManualReviewCase,
  StudioBusinessRecord,
} from '../../core/models/business.models';
import { BusinessApiService } from '../../core/services/business-api.service';
import { FirebaseAuthService } from '../../core/services/firebase-auth.service';

type StudioSection =
  | 'overview'
  | 'analytics'
  | 'offers'
  | 'stories'
  | 'redemptions'
  | 'documents'
  | 'ops'
  | 'profile'
  | 'settings';

type StudioDealSummary = {
  id: string;
  title: string;
  subtitle: string;
  description: string;
  savingsLabel: string;
  availabilityLabel: string;
  validUntilLabel: string;
  statusLabel: string;
  rawStatus: 'live' | 'paused' | 'archived';
  views: number;
  saves: number;
  activations: number;
  imageUrl: string;
};

type StudioStorySummary = {
  id: string;
  label: string;
  subtitle: string;
  body: string;
  ctaLabel: string;
  itemCount: number;
  imageUrl: string;
  statusLabel: string;
};

type StudioRedemptionSummary = {
  id: string;
  couponId: string;
  code: string;
  statusLabel: string;
  dealTitle: string;
  activatedLabel: string;
  expiresLabel: string;
};

type ProfileDraft = {
  website: string;
  phone: string;
  contactEmail: string;
  legalEntityName: string;
  tagline: string;
  shortDescription: string;
};

type DealDraft = {
  title: string;
  subtitle: string;
  description: string;
  savingsPercent: number;
  validityDays: number;
  availabilityLabel: string;
  imageUrl: string;
};

type StoryDraft = {
  label: string;
  subtitle: string;
  body: string;
  ctaLabel: string;
  durationHours: number;
  imageUrl: string;
};

type StudioNavItem = {
  section: StudioSection;
  title: string;
  subtitle: string;
};

type StudioAiSuggestion = {
  title: string;
  detail: string;
  actionLabel: string;
  section: StudioSection;
  tone: 'critical' | 'opportunity' | 'ready';
};

@Component({
  selector: 'app-business-studio-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './business-studio-page.component.html',
  styleUrl: './business-studio-page.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class BusinessStudioPageComponent {
  private readonly auth = inject(FirebaseAuthService);
  private readonly api = inject(BusinessApiService);
  private readonly router = inject(Router);

  readonly searchIcon = searchOutline;
  readonly settingsIcon = settingsOutline;
  readonly profileIcon = personCircleOutline;
  readonly sparklesIcon = sparklesOutline;
  readonly profile = this.auth.profile;
  readonly business = signal<StudioBusinessRecord | null>(null);
  readonly deals = signal<StudioDealSummary[]>([]);
  readonly stories = signal<StudioStorySummary[]>([]);
  readonly redemptions = signal<StudioRedemptionSummary[]>([]);
  readonly manualReviews = signal<ManualReviewCase[]>([]);
  readonly activeSection = signal<StudioSection>('overview');
  readonly themeMode = signal<'light' | 'dark'>('light');
  readonly dashboardSearch = signal('');
  readonly offerFilter = signal<'all' | 'live' | 'paused' | 'archived'>('all');
  readonly redemptionFilter = signal<'all' | 'active' | 'redeemed' | 'expired'>('all');
  readonly redemptionMode = signal<'desk' | 'team'>('desk');
  readonly editingProfile = signal(false);
  readonly editingDealId = signal<string | null>(null);
  readonly editingStoryId = signal<string | null>(null);
  readonly savingProfile = signal(false);
  readonly creatingDeal = signal(false);
  readonly creatingStory = signal(false);
  readonly savingDeal = signal(false);
  readonly savingStory = signal(false);
  readonly deletingBusinessAccount = signal(false);
  readonly deleteBusinessConfirmation = signal('');
  readonly generatingStudioAi = signal<'profile' | 'deal' | 'story' | ''>('');
  readonly loading = signal(true);
  readonly error = signal('');
  readonly success = signal('');
  readonly profileDraft = signal<ProfileDraft>({
    website: '',
    phone: '',
    contactEmail: '',
    legalEntityName: '',
    tagline: '',
    shortDescription: '',
  });
  readonly dealDraft = signal<DealDraft>({
    title: '',
    subtitle: '',
    description: '',
    savingsPercent: 15,
    validityDays: 7,
    availabilityLabel: 'Diese Woche',
    imageUrl: '',
  });
  readonly storyDraft = signal<StoryDraft>({
    label: '',
    subtitle: '',
    body: '',
    ctaLabel: 'Mehr sehen',
    durationHours: 24,
    imageUrl: '',
  });
  readonly navItems = computed<StudioNavItem[]>(() => [
    { section: 'overview', title: 'Übersicht', subtitle: 'Dashboard' },
    { section: 'analytics', title: 'Analytics', subtitle: 'Leistung' },
    { section: 'offers', title: 'Gutscheine', subtitle: `${this.liveOfferCount()} aktiv` },
      { section: 'stories', title: 'Stories', subtitle: `${this.liveStoryCount()} live` },
      { section: 'redemptions', title: 'Einlösungen', subtitle: `${this.activeRedemptionCount()} offen` },
      { section: 'documents', title: 'Dokumente', subtitle: 'KI & Nachweise' },
      { section: 'ops', title: 'Ops & Review', subtitle: `${this.pendingManualReviewCount()} offen` },
      { section: 'profile', title: 'Business', subtitle: 'Profil und Signale' },
      { section: 'settings', title: 'Einstellungen', subtitle: 'Theme und Studio' },
    ]);
  readonly greeting = computed(() => this.profile()?.displayName || this.profile()?.email || 'Business Team');
  readonly businessCityLabel = computed(() => {
    const business = this.business();
    if (!business) {
      return '';
    }
    return resolveBusinessCity(business);
  });
  readonly businessAddressLabel = computed(() => {
    const business = this.business();
    if (!business) {
      return '';
    }
    return resolveBusinessAddress(business);
  });
  readonly resolvedReview = computed<DocumentVerificationReview | null>(() => {
    const business = this.business();
    if (!business) {
      return null;
    }

    if (business.documentReview) {
      return business.documentReview;
    }

    if (isVerifiedBusiness(business)) {
      const method = business.verificationMethod || '';
      const googleLink = business.googleProfileLink;
      const isDocumentProof = method === 'registryDocumentProof';
      const isGoogleProof = method === 'googleBusinessProfile';

      return {
        documentType: isDocumentProof
          ? 'Amtlicher Business-Nachweis'
          : isGoogleProof
            ? 'Verifizierte Google-Places-Zuordnung'
            : 'Verifizierte Business-Zuordnung',
        legalEntityName: business.legalEntityName || business.name,
        tradeName: business.name,
        issuingAuthority: isDocumentProof
          ? 'Dokumentenprüfung und Studio-Sicherheit'
          : isGoogleProof
            ? 'Google Places und sparGO Sicherheitsprüfung'
            : 'sparGO Sicherheitsprüfung',
        city: this.businessAddressLabel() || this.businessCityLabel() || business.city || googleLink?.locationCity || '',
        countryCode: 'DE',
        vatSignalVerified: isDocumentProof,
        registerSignalVerified: true,
        officialDocumentVerified: isDocumentProof,
        representativeMatch: true,
        emailMatch: true,
      };
    }

    return null;
  });
  readonly isDocumentVerificationReview = computed(() =>
    this.business()?.verificationMethod === 'registryDocumentProof',
  );
  readonly verificationSourceLabel = computed(() =>
    this.isDocumentVerificationReview()
      ? 'Aus OCR und Dokumentenprüfung'
      : 'Aus Google Places, Business-Konto und Sicherheitsprüfung',
  );
  readonly completionItems = computed(() => {
    const business = this.business();
    if (!business) {
      return [];
    }

    return [
      {
        label: 'Rechtliche Zuordnung',
        done: !!business.legalEntityName || isVerifiedBusiness(business),
      },
      {
        label: 'Kontakt-E-Mail',
        done: !!business.contactEmail,
      },
      {
        label: 'Website',
        done: !!business.website,
      },
      {
        label: 'Verifizierungsnachweis',
        done: isVerifiedBusiness(business) || !!this.resolvedReview(),
      },
    ];
  });
  readonly completionRatio = computed(() => {
    const items = this.completionItems();
    if (!items.length) {
      return 0;
    }

    const done = items.filter((item) => item.done).length;
    return Math.round((done / items.length) * 100);
  });
  readonly verificationTitle = computed(() => {
    const method = this.business()?.verificationMethod || '';
    if (method === 'registryDocumentProof') {
      return 'Dokumente und KI bestätigt';
    }
    if (method === 'googleBusinessProfile') {
      return 'Studio aktiv';
    }
    return 'Business bestätigt';
  });
  readonly primaryActionLabel = computed(() =>
    this.completionRatio() < 100 ? 'Profil vervollständigen' : 'Studio prüfen',
  );
  readonly liveOfferCount = computed(() => this.deals().length);
  readonly liveStoryCount = computed(() => this.stories().length);
  readonly filteredStories = computed(() => {
    const query = this.dashboardSearch().trim().toLowerCase();
    if (!query) {
      return this.stories();
    }
    return this.stories().filter((story) =>
      [story.label, story.subtitle, story.body, story.ctaLabel]
        .join(' ')
        .toLowerCase()
        .includes(query),
    );
  });
  readonly filteredDeals = computed(() => {
    const filter = this.offerFilter();
    const query = this.dashboardSearch().trim().toLowerCase();
    const scoped =
      filter === 'all'
        ? this.deals()
        : this.deals().filter((deal) => deal.rawStatus === filter);
    if (!query) {
      return scoped;
    }
    return scoped.filter((deal) =>
      [deal.title, deal.subtitle, deal.description, deal.savingsLabel]
        .join(' ')
        .toLowerCase()
        .includes(query),
    );
  });
  readonly filteredRedemptions = computed(() => {
    const filter = this.redemptionFilter();
    const query = this.dashboardSearch().trim().toLowerCase();
    const scoped =
      filter === 'all'
        ? this.redemptions()
        : this.redemptions().filter(
            (item) =>
              item.statusLabel.toLowerCase() ===
              redemptionFilterLabel(filter).toLowerCase(),
          );
    if (!query) {
      return scoped;
    }
    return scoped.filter((item) =>
      [item.dealTitle, item.couponId, item.code, item.statusLabel]
        .join(' ')
        .toLowerCase()
        .includes(query),
    );
  });
  readonly storyPreview = computed(() => {
    const draft = this.storyDraft();
    return {
      title: draft.label.trim() || 'Story Preview',
      subtitle: draft.subtitle.trim() || 'Kurze Zeile für den Feed',
      body: draft.body.trim() || 'Hier siehst du sofort, wie sich deine Story im vorhandenen App-Flow lesen wird.',
      ctaLabel: draft.ctaLabel.trim() || 'Mehr sehen',
      imageUrl: draft.imageUrl.trim(),
    };
  });
  readonly activeRedemptionCount = computed(() =>
    this.redemptions().filter((item) => item.statusLabel === 'Aktiv').length,
  );
  readonly pendingManualReviewCount = computed(() => this.manualReviews().length);
  readonly redeemedRedemptionCount = computed(() =>
    this.redemptions().filter((item) => item.statusLabel === 'Eingelöst').length,
  );
  readonly expiredRedemptionCount = computed(() =>
    this.redemptions().filter((item) => item.statusLabel === 'Abgelaufen').length,
  );
  readonly activeSectionTitle = computed(() => {
    switch (this.activeSection()) {
      case 'offers':
        return 'Gutscheine steuern';
      case 'analytics':
        return 'Analytics und Performance';
      case 'stories':
        return 'Story-Feed steuern';
      case 'documents':
        return 'Dokumente und KI-Signale';
      case 'profile':
        return 'Profil und Signale prüfen';
      case 'ops':
        return 'Manual Review und Ops';
      case 'settings':
        return 'Studio-Einstellungen';
      case 'redemptions':
        return 'Einlösungen im Blick';
      default:
        return 'Studio-Übersicht';
    }
  });
  readonly activeSectionDescription = computed(() => {
    switch (this.activeSection()) {
      case 'offers':
        return 'Live-Angebote, Performance und Aktivierungen direkt an einem Ort.';
      case 'analytics':
        return 'Reichweite, Saves, Aktivierungen und Team-Leistung als ruhige Arbeitsübersicht.';
      case 'stories':
        return 'Aktuelle Story-Serien, Updates und kurze Live-Formate im Blick.';
      case 'documents':
        return 'OCR, KI-Review und die übernommene Business-Zuordnung transparent zusammengeführt.';
      case 'profile':
        return 'Verifizierung, KI-Review und Profilsignale sauber zusammengeführt.';
      case 'ops':
        return 'Grenzfälle, manuelle Prüfungen und Audit-Signale liegen hier als operative Arbeitsfläche bereit.';
      case 'settings':
        return 'Theme, Studio-Verhalten und grundlegende Schalter zentral verwalten.';
      case 'redemptions':
        return 'Aktive und bereits eingelöste Gutscheine sofort sauber nachvollziehen.';
      default:
        return 'Die wichtigsten Studio-Bereiche direkt oben erreichbar.';
    }
  });
  readonly totalViews = computed(() =>
    this.business()?.analytics?.views ??
    this.deals().reduce((sum, deal) => sum + deal.views, 0),
  );
  readonly totalSaves = computed(() =>
    this.business()?.analytics?.saves ??
    this.deals().reduce((sum, deal) => sum + deal.saves, 0),
  );
  readonly totalActivations = computed(() =>
    this.business()?.analytics?.activations ??
    this.deals().reduce((sum, deal) => sum + deal.activations, 0),
  );
  readonly totalRedemptions = computed(() =>
    this.business()?.analytics?.redemptions ??
    Math.round(this.deals().reduce((sum, deal) => sum + deal.activations, 0) * 0.42),
  );
  readonly totalReach = computed(() =>
    this.business()?.analytics?.reach ?? Math.max(this.totalViews() * 3, 0),
  );
  readonly analyticsBars = computed(() => {
    const entries = [
      { label: 'Reichweite', value: this.totalReach(), tone: 'reach' },
      { label: 'Ansichten', value: this.totalViews(), tone: 'views' },
      { label: 'Saves', value: this.totalSaves(), tone: 'saves' },
      { label: 'Aktivierungen', value: this.totalActivations(), tone: 'activations' },
      { label: 'Einlösungen', value: this.totalRedemptions(), tone: 'redemptions' },
    ];
    const max = Math.max(...entries.map((entry) => entry.value), 1);
    return entries.map((entry) => ({
      ...entry,
      height: Math.max(8, Math.round((entry.value / max) * 100)),
    }));
  });
  readonly studioHealthScore = computed(() =>
    Math.min(
      100,
      Math.round(
        this.completionRatio() * 0.45 +
          Math.min(this.liveOfferCount(), 3) * 10 +
          Math.min(this.liveStoryCount(), 3) * 8 +
          Math.min(this.redemptionRate(), 20),
      ),
    ),
  );
  readonly studioHealthConic = computed(() =>
    `conic-gradient(var(--bs-accent) ${this.studioHealthScore() * 3.6}deg, var(--gray-a4, rgba(0,0,0,.08)) 0deg)`,
  );
  readonly liveRedemptionCount = computed(() => this.redemptions().length);
  readonly activationRate = computed(() => {
    const views = this.totalViews();
    if (!views) {
      return 0;
    }
    return Math.round((this.totalActivations() / views) * 1000) / 10;
  });
  readonly redemptionRate = computed(() => {
    const activations = this.totalActivations();
    if (!activations) {
      return 0;
    }
    return Math.round((this.totalRedemptions() / activations) * 1000) / 10;
  });
  readonly topSignals = computed(() => [
    {
      label: 'Live Gutscheine',
      value: `${this.liveOfferCount()}`,
      detail: `${this.filteredDeals()[0]?.title || 'Bereit für die nächste Aktion'}`,
    },
    {
      label: 'Story Präsenz',
      value: `${this.liveStoryCount()}`,
      detail: `${this.filteredStories()[0]?.label || 'Noch keine Story im Fokus'}`,
    },
      {
        label: 'Offene Einlösungen',
        value: `${this.activeRedemptionCount()}`,
        detail: `${this.filteredRedemptions()[0]?.dealTitle || 'Keine offene Einlösung sichtbar'}`,
      },
      {
        label: 'Manual Review',
        value: `${this.pendingManualReviewCount()}`,
        detail: `${this.manualReviews()[0]?.placeName || 'Keine offene manuelle Prüfung'}`,
      },
    ]);
  readonly aiStudioSuggestions = computed<StudioAiSuggestion[]>(() => {
    const business = this.business();
    if (!business) {
      return [];
    }

    const suggestions: StudioAiSuggestion[] = [];
    const city = this.businessCityLabel();
    const address = this.businessAddressLabel();

    if (!city || !address) {
      suggestions.push({
        title: 'Standortdaten vervollständigen',
        detail: 'Die Verifizierung ist da, aber Ort oder Adresse fehlen im Profil. Ich übernehme die stärksten Google- und Nachweis-Signale in dein Business-Profil.',
        actionLabel: 'Profil mit KI ergänzen',
        section: 'profile',
        tone: 'critical',
      });
    }

    if (!business.tagline || !business.shortDescription || !business.website || !business.phone) {
      suggestions.push({
        title: 'Profil verkaufsbereit machen',
        detail: 'Tagline, Beschreibung, Website und Telefon werden aus Business-Name, Standort und Verifikationsdaten sinnvoll vorgeschlagen.',
        actionLabel: 'Profil-Vorschlag anwenden',
        section: 'profile',
        tone: 'opportunity',
      });
    }

    if (!this.liveOfferCount()) {
      suggestions.push({
        title: 'Ersten Gutschein vorbereiten',
        detail: 'Aus Business-Typ, Standort und Profil entsteht ein sofort editierbarer Gutschein-Entwurf statt einer leeren Maske.',
        actionLabel: 'Gutschein generieren',
        section: 'offers',
        tone: 'opportunity',
      });
    }

    if (!this.liveStoryCount()) {
      suggestions.push({
        title: 'Story für den lokalen Feed',
        detail: 'Eine kurze lokale Story bringt dein verifiziertes Business direkt in einen verständlichen Kunden-Flow.',
        actionLabel: 'Story generieren',
        section: 'stories',
        tone: 'ready',
      });
    }

    return suggestions.slice(0, 4);
  });

  constructor() {
    const savedTheme = localStorage.getItem('spargo-business-studio-theme');
    if (savedTheme === 'dark' || savedTheme === 'light') {
      this.themeMode.set(savedTheme);
    }
    void this.loadBusiness();
  }

  async logout(): Promise<void> {
    await this.auth.logout();
  }

  updateDashboardSearch(value: string): void {
    this.dashboardSearch.set(value);
  }

  setThemeMode(mode: 'light' | 'dark'): void {
    this.themeMode.set(mode);
    localStorage.setItem('spargo-business-studio-theme', mode);
  }

  updateDeleteBusinessConfirmation(value: string): void {
    this.deleteBusinessConfirmation.set(value);
  }

  startDealCreate(): void {
    this.dealDraft.set({
      title: '',
      subtitle: '',
      description: '',
      savingsPercent: 15,
      validityDays: 7,
      availabilityLabel: 'Diese Woche',
      imageUrl: '',
    });
    this.creatingDeal.set(true);
    this.editingDealId.set(null);
    this.success.set('');
    this.error.set('');
    this.setSection('offers');
  }

  startStoryCreate(): void {
    this.storyDraft.set({
      label: '',
      subtitle: '',
      body: '',
      ctaLabel: 'Mehr sehen',
      durationHours: 24,
      imageUrl: '',
    });
    this.creatingStory.set(true);
    this.editingStoryId.set(null);
    this.success.set('');
    this.error.set('');
    this.setSection('stories');
  }

  cancelDealCreate(): void {
    this.creatingDeal.set(false);
    this.editingDealId.set(null);
  }

  cancelStoryCreate(): void {
    this.creatingStory.set(false);
    this.editingStoryId.set(null);
  }

  startDealEdit(deal: StudioDealSummary): void {
    this.dealDraft.set({
      title: deal.title,
      subtitle: deal.subtitle,
      description: deal.description,
      savingsPercent: Number.parseInt(deal.savingsLabel, 10) || 0,
      validityDays: 7,
      availabilityLabel: deal.availabilityLabel,
      imageUrl: deal.imageUrl,
    });
    this.editingDealId.set(deal.id);
    this.creatingDeal.set(true);
    this.success.set('');
    this.error.set('');
    this.setSection('offers');
  }

  startStoryEdit(story: StudioStorySummary): void {
    this.storyDraft.set({
      label: story.label,
      subtitle: story.subtitle,
      body: story.body,
      ctaLabel: story.ctaLabel,
      durationHours: 24,
      imageUrl: story.imageUrl,
    });
    this.editingStoryId.set(story.id);
    this.creatingStory.set(true);
    this.success.set('');
    this.error.set('');
    this.setSection('stories');
  }

  updateDealDraft<K extends keyof DealDraft>(key: K, value: DealDraft[K]): void {
    this.dealDraft.update((draft) => ({
      ...draft,
      [key]: key === 'savingsPercent' || key === 'validityDays' ? Number(value) || 0 : value,
    }));
  }

  updateStoryDraft<K extends keyof StoryDraft>(key: K, value: StoryDraft[K]): void {
    this.storyDraft.update((draft) => ({
      ...draft,
      [key]: key === 'durationHours' ? Number(value) || 0 : value,
    }));
  }

  setOfferFilter(filter: 'all' | 'live' | 'paused' | 'archived'): void {
    this.offerFilter.set(filter);
  }

  setRedemptionFilter(filter: 'all' | 'active' | 'redeemed' | 'expired'): void {
    this.redemptionFilter.set(filter);
  }

  setRedemptionMode(mode: 'desk' | 'team'): void {
    this.redemptionMode.set(mode);
  }

  startProfileEdit(): void {
    const business = this.business();
    if (!business) {
      return;
    }

    this.profileDraft.set({
      website: business.website,
      phone: business.phone,
      contactEmail: business.contactEmail,
      legalEntityName: business.legalEntityName,
      tagline: business.tagline,
      shortDescription: business.shortDescription,
    });
    this.editingProfile.set(true);
    this.success.set('');
    this.error.set('');
    this.setSection('profile');
  }

  cancelProfileEdit(): void {
    this.editingProfile.set(false);
  }

  updateProfileDraft<K extends keyof ProfileDraft>(key: K, value: ProfileDraft[K]): void {
    this.profileDraft.update((draft) => ({
      ...draft,
      [key]: value,
    }));
  }

  async applyAiProfileEnhancements(): Promise<void> {
    if (this.business() && (!this.businessCityLabel() || !this.businessAddressLabel())) {
      await this.repairBusinessProfileNow();
    }

    const business = this.business();
    const user = this.auth.currentUser;
    if (!business || !user) {
      return;
    }

    this.editingProfile.set(true);
    this.setSection('profile');
    this.generatingStudioAi.set('profile');
    this.success.set('Studio-Assistent bereitet dein Business-Profil vor...');
    this.error.set('');
    try {
      const result = await this.api.generateBusinessStudioContent({
        firebaseIdToken: await user.getIdToken(true),
        kind: 'profile',
        draft: this.profileDraft(),
      });
      const googleLink = business.googleProfileLink;
      this.profileDraft.update((draft) => ({
        ...draft,
        ...(result.profile ?? {}),
        website: result.profile?.website || draft.website || business.website || googleLink?.website || '',
        phone: result.profile?.phone || draft.phone || business.phone || googleLink?.phone || '',
        contactEmail: result.profile?.contactEmail || draft.contactEmail || business.contactEmail || this.profile()?.email || '',
        legalEntityName: result.profile?.legalEntityName || draft.legalEntityName || business.legalEntityName || business.name,
      }));
      await this.saveProfile();
      this.editingProfile.set(false);
      this.setSection('profile');
      this.success.set('Gemini hat das Business-Profil ergänzt und gespeichert.');
      this.error.set('');
    } catch (error) {
      this.error.set(humanizeStudioError(error, 'Gemini konnte das Profil gerade nicht ergänzen.'));
    } finally {
      this.generatingStudioAi.set('');
    }
  }

  async applyAiDealSuggestion(): Promise<void> {
    const business = this.business();
    const user = this.auth.currentUser;
    if (!business || !user) {
      return;
    }

    this.creatingDeal.set(true);
    this.editingDealId.set(null);
    this.setSection('offers');
    this.generatingStudioAi.set('deal');
    this.success.set('Studio-Assistent bereitet einen Gutschein-Entwurf vor...');
    this.error.set('');
    try {
      const result = await this.api.generateBusinessStudioContent({
        firebaseIdToken: await user.getIdToken(true),
        kind: 'deal',
        draft: this.dealDraft(),
      });
      this.dealDraft.update((draft) => ({
        ...draft,
        ...(result.deal ?? {}),
        imageUrl: result.deal?.imageUrl || draft.imageUrl || business.imageUrl || '',
      }));
      this.success.set('Gemini hat einen Gutschein-Entwurf vorbereitet.');
      this.error.set('');
    } catch (error) {
      this.error.set(humanizeStudioError(error, 'Gemini konnte gerade keinen Gutschein vorbereiten.'));
    } finally {
      this.generatingStudioAi.set('');
    }
  }

  async applyAiStorySuggestion(): Promise<void> {
    const business = this.business();
    const user = this.auth.currentUser;
    if (!business || !user) {
      return;
    }

    this.creatingStory.set(true);
    this.editingStoryId.set(null);
    this.setSection('stories');
    this.generatingStudioAi.set('story');
    this.success.set('Studio-Assistent bereitet eine Story vor...');
    this.error.set('');
    try {
      const result = await this.api.generateBusinessStudioContent({
        firebaseIdToken: await user.getIdToken(true),
        kind: 'story',
        draft: this.storyDraft(),
      });
      this.storyDraft.update((draft) => ({
        ...draft,
        ...(result.story ?? {}),
        imageUrl: result.story?.imageUrl || draft.imageUrl || business.imageUrl || '',
      }));
      this.success.set('Gemini hat eine Story vorbereitet.');
      this.error.set('');
    } catch (error) {
      this.error.set(humanizeStudioError(error, 'Gemini konnte gerade keine Story vorbereiten.'));
    } finally {
      this.generatingStudioAi.set('');
    }
  }

  async runAiSuggestion(suggestion: StudioAiSuggestion): Promise<void> {
    if (suggestion.section === 'offers') {
      await this.applyAiDealSuggestion();
      return;
    }
    if (suggestion.section === 'stories') {
      await this.applyAiStorySuggestion();
      return;
    }
    await this.repairBusinessProfileNow();
    await this.applyAiProfileEnhancements();
  }

  async repairBusinessProfileNow(): Promise<void> {
    const business = this.business();
    const user = this.auth.currentUser;
    if (!business || !user) {
      return;
    }

    try {
      const repaired = await this.api.repairBusinessStudioProfile(await user.getIdToken(true));
      const nextBusiness = normalizeStudioBusinessRepair(repaired.business, business);
      this.business.set(nextBusiness);
      this.profileDraft.set({
        website: nextBusiness.website,
        phone: nextBusiness.phone,
        contactEmail: nextBusiness.contactEmail,
        legalEntityName: nextBusiness.legalEntityName,
        tagline: nextBusiness.tagline,
        shortDescription: nextBusiness.shortDescription,
      });
      this.success.set('Business-Daten aus der Verifizierung synchronisiert.');
      this.error.set('');
    } catch (error) {
      this.error.set(humanizeStudioError(error, 'Die Business-Daten konnten gerade nicht synchronisiert werden.'));
    }
  }

  async saveProfile(): Promise<void> {
    const business = this.business();
    if (!business) {
      return;
    }

    const draft = this.profileDraft();
    this.savingProfile.set(true);
    this.error.set('');
    this.success.set('');

    try {
      await setDoc(
        doc(this.auth.firestoreInstance, 'businesses', business.id),
        {
          website: draft.website.trim(),
          phone: draft.phone.trim(),
          contactEmail: draft.contactEmail.trim().toLowerCase(),
          legalEntityName: draft.legalEntityName.trim(),
          tagline: draft.tagline.trim(),
          shortDescription: draft.shortDescription.trim(),
          ...(this.businessCityLabel() ? { city: this.businessCityLabel() } : {}),
          ...(this.businessAddressLabel()
            ? {
                branches: [
                  {
                    id: `branch_${business.verificationPlaceId || business.id}`,
                    name: business.name,
                    address: this.businessAddressLabel(),
                    city: this.businessCityLabel(),
                    phone: draft.phone.trim() || business.phone,
                  },
                ],
              }
            : {}),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );

      this.business.update((current) =>
        current
          ? {
              ...current,
              website: draft.website.trim(),
              phone: draft.phone.trim(),
              contactEmail: draft.contactEmail.trim().toLowerCase(),
              legalEntityName: draft.legalEntityName.trim(),
              tagline: draft.tagline.trim(),
              shortDescription: draft.shortDescription.trim(),
              city: this.businessCityLabel(),
              address: this.businessAddressLabel(),
            }
          : current,
      );
      this.editingProfile.set(false);
      this.success.set('Profil gespeichert und direkt im Studio aktualisiert.');
      this.scrollToSection('studio-profile');
    } catch (error) {
      this.error.set(
        humanizeStudioError(error, 'Das Profil konnte gerade nicht gespeichert werden.'),
      );
      this.scrollToSection('studio-profile');
    } finally {
      this.savingProfile.set(false);
    }
  }

  async saveDeal(): Promise<void> {
    const business = this.business();
    const profile = this.profile();
    const user = this.auth.currentUser;
    if (!business || !profile?.uid || !user) {
      return;
    }

    const draft = this.dealDraft();
    this.savingDeal.set(true);
    this.error.set('');
    this.success.set('');

    try {
      const editingId = this.editingDealId();
      const savingsPercent = Math.max(0, Number(draft.savingsPercent) || 0);
      const validityDays = Math.max(1, Math.min(90, Number(draft.validityDays) || 7));
      const payload = {
        title: draft.title.trim(),
        subtitle: draft.subtitle.trim(),
        description: draft.description.trim(),
        savingsPercent,
        validityDays,
        availabilityLabel: draft.availabilityLabel.trim() || 'Aktiv',
        imageUrl: draft.imageUrl.trim(),
      };

      const saved = await this.api.upsertBusinessStudioDeal<StudioDealSummary>({
        firebaseIdToken: await user.getIdToken(true),
        id: editingId,
        payload,
      });
      const nextDeal = saved.item;

      this.deals.update((items) =>
        editingId
          ? items.map((item) => (item.id === editingId ? { ...item, ...nextDeal } : item))
          : [nextDeal, ...items],
      );
      this.creatingDeal.set(false);
      this.editingDealId.set(null);
      this.success.set(editingId ? 'Gutschein wurde aktualisiert.' : 'Gutschein wurde direkt im Studio angelegt.');
      this.scrollToSection('studio-offers');
    } catch (error) {
      this.error.set(
        humanizeStudioError(error, 'Der Gutschein konnte gerade nicht angelegt werden.'),
      );
      this.scrollToSection('studio-offers');
    } finally {
      this.savingDeal.set(false);
    }
  }

  async saveStory(): Promise<void> {
    const business = this.business();
    const profile = this.profile();
    const user = this.auth.currentUser;
    if (!business || !profile?.uid || !user) {
      return;
    }

    const draft = this.storyDraft();
    this.savingStory.set(true);
    this.error.set('');
    this.success.set('');

    try {
      const editingId = this.editingStoryId();
      const durationHours = Math.max(1, Math.min(24, Number(draft.durationHours) || 24));
      const payload = {
        label: draft.label.trim(),
        subtitle: draft.subtitle.trim(),
        body: draft.body.trim(),
        ctaLabel: draft.ctaLabel.trim() || 'Mehr sehen',
        durationHours,
        imageUrl: draft.imageUrl.trim(),
      };

      const saved = await this.api.upsertBusinessStudioStory<StudioStorySummary>({
        firebaseIdToken: await user.getIdToken(true),
        id: editingId,
        payload,
      });
      const nextStory = saved.item;

      this.stories.update((items) =>
        editingId
          ? items.map((item) => (item.id === editingId ? { ...item, ...nextStory } : item))
          : [nextStory, ...items],
      );
      this.creatingStory.set(false);
      this.editingStoryId.set(null);
      this.success.set(editingId ? 'Story wurde aktualisiert.' : 'Story wurde direkt im Studio vorbereitet.');
      this.scrollToSection('studio-stories');
    } catch (error) {
      this.error.set(
        humanizeStudioError(error, 'Die Story konnte gerade nicht angelegt werden.'),
      );
      this.scrollToSection('studio-stories');
    } finally {
      this.savingStory.set(false);
    }
  }

  async deleteDeal(deal: StudioDealSummary): Promise<void> {
    if (!confirm(`Gutschein "${deal.title}" wirklich löschen?`)) {
      return;
    }

    try {
      const user = this.auth.currentUser;
      if (!user) {
        throw new Error('Keine aktive Business-Session vorhanden.');
      }
      await this.api.deleteBusinessStudioDeal({
        firebaseIdToken: await user.getIdToken(true),
        id: deal.id,
      });
      this.deals.update((items) => items.filter((item) => item.id !== deal.id));
      this.success.set('Gutschein gelöscht.');
      this.error.set('');
    } catch (error) {
      this.error.set(
        humanizeStudioError(error, 'Der Gutschein konnte gerade nicht gelöscht werden.'),
      );
    }
  }

  async deleteStory(story: StudioStorySummary): Promise<void> {
    if (!confirm(`Story "${story.label}" wirklich löschen?`)) {
      return;
    }

    try {
      const user = this.auth.currentUser;
      if (!user) {
        throw new Error('Keine aktive Business-Session vorhanden.');
      }
      await this.api.deleteBusinessStudioStory({
        firebaseIdToken: await user.getIdToken(true),
        id: story.id,
      });
      this.stories.update((items) => items.filter((item) => item.id !== story.id));
      this.success.set('Story gelöscht.');
      this.error.set('');
    } catch (error) {
      this.error.set(
        humanizeStudioError(error, 'Die Story konnte gerade nicht gelöscht werden.'),
      );
    }
  }

  async deleteEntireBusinessAccount(): Promise<void> {
    const business = this.business();
    const user = this.auth.currentUser;
    const confirmation = this.deleteBusinessConfirmation().trim();
    if (!business || !user) {
      this.error.set('Keine aktive Business-Session vorhanden.');
      return;
    }
    if (confirmation.toUpperCase() !== 'BUSINESS LÖSCHEN' && confirmation.toUpperCase() !== 'BUSINESS LOESCHEN') {
      this.error.set('Bitte bestätige die endgültige Löschung exakt mit BUSINESS LÖSCHEN.');
      this.scrollToSection('studio-settings');
      return;
    }
    if (!confirm(`Business "${business.name}" inklusive Konto, Gutscheinen, Stories und Daten endgültig löschen?`)) {
      return;
    }

    this.deletingBusinessAccount.set(true);
    this.error.set('');
    this.success.set('');
    try {
      await this.api.deleteOwnedBusinessAccount({
        firebaseIdToken: await user.getIdToken(true),
        confirmation,
      });
      this.business.set(null);
      this.deals.set([]);
      this.stories.set([]);
      this.redemptions.set([]);
      this.manualReviews.set([]);
      await this.auth.logout().catch(() => undefined);
      await this.router.navigateByUrl('/business-register');
    } catch (error) {
      this.error.set(
        humanizeStudioError(error, 'Das Business konnte gerade nicht vollständig gelöscht werden.'),
      );
      this.scrollToSection('studio-settings');
    } finally {
      this.deletingBusinessAccount.set(false);
    }
  }

  async openPrimaryAction(): Promise<void> {
    if (this.completionRatio() < 100) {
      this.setSection('profile');
      return;
    }

    this.setSection('offers');
  }

  async markRedemptionRedeemed(redemption: StudioRedemptionSummary): Promise<void> {
    if (!redemption.id || redemption.id.startsWith('demo-')) {
      this.redemptions.update((items) =>
        items.map((item) =>
          item.id === redemption.id
            ? { ...item, statusLabel: 'Eingelöst', activatedLabel: 'Heute' }
            : item,
        ),
      );
      this.success.set('Einlösung wurde im Studio bestätigt.');
      this.scrollToSection('studio-redemptions');
      return;
    }

    try {
      await updateDoc(doc(this.auth.firestoreInstance, 'redemptions', redemption.id), {
        status: 'redeemed',
        redeemedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      this.redemptions.update((items) =>
        items.map((item) =>
          item.id === redemption.id
            ? { ...item, statusLabel: 'Eingelöst', activatedLabel: 'Heute' }
            : item,
        ),
      );
      this.success.set('Einlösung wurde im Studio bestätigt.');
      this.scrollToSection('studio-redemptions');
    } catch (error) {
      this.error.set(
        error instanceof Error && error.message.trim()
          ? error.message.trim()
          : 'Die Einlösung konnte gerade nicht bestätigt werden.',
      );
      this.scrollToSection('studio-redemptions');
    }
  }

  async setDealLifecycle(
    deal: StudioDealSummary,
    nextStatus: 'live' | 'paused' | 'archived',
  ): Promise<void> {
    const nextLabel = nextStatus === 'paused' ? 'Pausiert' : nextStatus === 'archived' ? 'Archiviert' : 'Live';
    if (!deal.id || deal.id.startsWith('demo-')) {
      this.deals.update((items) =>
        items.map((item) =>
          item.id === deal.id ? { ...item, rawStatus: nextStatus, statusLabel: nextLabel } : item,
        ),
      );
      this.success.set(`Gutschein ist jetzt ${nextLabel.toLowerCase()}.`);
      this.scrollToSection('studio-offers');
      return;
    }

    try {
      await updateDoc(doc(this.auth.firestoreInstance, 'deals', deal.id), {
        isPaused: nextStatus === 'paused',
        archived: nextStatus === 'archived',
        updatedAt: serverTimestamp(),
      });
      this.deals.update((items) =>
        items.map((item) =>
          item.id === deal.id ? { ...item, rawStatus: nextStatus, statusLabel: nextLabel } : item,
        ),
      );
      this.success.set(`Gutschein ist jetzt ${nextLabel.toLowerCase()}.`);
      this.scrollToSection('studio-offers');
    } catch (error) {
      this.error.set(
        error instanceof Error && error.message.trim()
          ? error.message.trim()
          : 'Der Gutscheinstatus konnte gerade nicht geändert werden.',
      );
      this.scrollToSection('studio-offers');
    }
  }

  setSection(section: StudioSection): void {
    this.activeSection.set(section);
    const target = {
      overview: 'studio-overview',
      analytics: 'studio-analytics',
      offers: 'studio-offers',
      stories: 'studio-stories',
      documents: 'studio-documents',
      ops: 'studio-ops',
      profile: 'studio-profile',
      settings: 'studio-settings',
      redemptions: 'studio-redemptions',
    }[section];
    this.scrollToSection(target);
  }

  scrollToSection(id: string): void {
    const target = document.getElementById(id);
    if (!(target instanceof HTMLElement)) {
      return;
    }

    target.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
      inline: 'nearest',
    });
  }

  private async loadBusiness(): Promise<void> {
    const businessId = this.profile()?.ownedBusinessId;
    if (!businessId) {
      await this.router.navigateByUrl('/business-onboarding');
      return;
    }

    try {
      const snapshot = await getDoc(doc(this.auth.firestoreInstance, 'businesses', businessId));
      const data = snapshot.data() ?? {};
      const googleProfileLink = objectRecord(data['googleProfileLink']);
      let resolvedBusiness: StudioBusinessRecord = {
        id: snapshot.id,
        name:
          String(data['name'] ?? '').trim() ||
          String(googleProfileLink?.['locationDisplayName'] ?? googleProfileLink?.['locationName'] ?? '').trim() ||
          'Dein Business',
        tagline: String(data['tagline'] ?? '').trim(),
        shortDescription: String(data['shortDescription'] ?? '').trim(),
        description: String(data['description'] ?? '').trim(),
        city: resolveCityFromBusinessData(data),
        address:
          resolveAddressFromBusinessData(data),
        website: String(data['website'] ?? googleProfileLink?.['website'] ?? '').trim(),
        phone: String(data['phone'] ?? googleProfileLink?.['phone'] ?? '').trim(),
        contactEmail: String(data['contactEmail'] ?? this.profile()?.email ?? '').trim(),
        legalEntityName:
          String(data['legalEntityName'] ?? '').trim() ||
          String(googleProfileLink?.['locationDisplayName'] ?? googleProfileLink?.['locationName'] ?? '').trim(),
        claimedByName: String(data['claimedByName'] ?? '').trim(),
        claimedByRole: String(data['claimedByRole'] ?? '').trim(),
        verificationStatus: String(data['verificationStatus'] ?? '').trim(),
        verificationMethod: String(data['verificationMethod'] ?? '').trim(),
        verificationPlaceId: String(data['verificationPlaceId'] ?? '').trim(),
        verificationNote: String(data['verificationNote'] ?? '').trim(),
        imageUrl: String(data['imageUrl'] ?? '').trim(),
        followerCount: Number(data['followerCount'] ?? 0),
        reviewCount: Number(data['reviewCount'] ?? 0),
        analytics:
          data['analytics'] && typeof data['analytics'] === 'object'
            ? {
                views: Number(data['analytics']['views'] ?? 0),
                saves: Number(data['analytics']['saves'] ?? 0),
                activations: Number(data['analytics']['activations'] ?? 0),
                redemptions: Number(data['analytics']['redemptions'] ?? 0),
                reach: Number(data['analytics']['reach'] ?? 0),
              }
            : null,
        documentReview:
          data['documentReview'] && typeof data['documentReview'] === 'object'
            ? (data['documentReview'] as StudioBusinessRecord['documentReview'])
            : null,
        googleProfileLink: googleProfileLink
          ? (googleProfileLink as unknown as StudioBusinessRecord['googleProfileLink'])
          : null,
      };
      resolvedBusiness = await this.repairBusinessFromServerIfNeeded(resolvedBusiness);
      this.business.set(resolvedBusiness);
      await this.repairBusinessLocationIfNeeded(snapshot.id, data, resolvedBusiness);
      this.profileDraft.set({
        website: resolvedBusiness.website,
        phone: resolvedBusiness.phone,
        contactEmail: resolvedBusiness.contactEmail,
        legalEntityName: resolvedBusiness.legalEntityName,
        tagline: resolvedBusiness.tagline,
        shortDescription: resolvedBusiness.shortDescription,
      });
      await this.loadStudioCollections(resolvedBusiness);
    } catch (error) {
      this.error.set(
        error instanceof Error && error.message.trim()
          ? error.message.trim()
          : 'Das Business Studio konnte die Live-Daten gerade nicht laden.',
      );
    } finally {
      this.loading.set(false);
    }
  }

  private async repairBusinessFromServerIfNeeded(
    business: StudioBusinessRecord,
  ): Promise<StudioBusinessRecord> {
    if (resolveBusinessCity(business) && isPreciseStreetAddress(resolveBusinessAddress(business)) && business.website && business.phone) {
      return business;
    }

    const user = this.auth.currentUser;
    if (!user) {
      return business;
    }

    try {
      const token = await user.getIdToken();
      const repaired = await this.api.repairBusinessStudioProfile(token);
      return normalizeStudioBusinessRepair(repaired.business, business);
    } catch {
      return business;
    }
  }

  private async repairBusinessLocationIfNeeded(
    businessId: string,
    rawData: Record<string, unknown>,
    business: StudioBusinessRecord,
  ): Promise<void> {
    const rawCity = String(rawData['city'] ?? '').trim();
    const rawAddress = String(firstBranch(rawData)?.['address'] ?? '').trim();
    const nextCity = resolveBusinessCity(business);
    const nextAddress = resolveBusinessAddress(business);
    const patch: Record<string, unknown> = {};

    if (nextCity && cleanLocationValue(rawCity) !== nextCity) {
      patch['city'] = nextCity;
    }
    if (nextAddress && cleanLocationValue(rawAddress) !== nextAddress) {
      const branch = firstBranch(rawData) ?? {};
      patch['branches'] = [
        {
          ...branch,
          id: `branch_${business.verificationPlaceId || business.id}`,
          name: business.name,
          address: nextAddress,
          city: nextCity,
          phone: business.phone || String(branch['phone'] ?? '').trim(),
        },
      ];
    }

    if (!Object.keys(patch).length) {
      return;
    }

    try {
      await updateDoc(doc(this.auth.firestoreInstance, 'businesses', businessId), {
        ...patch,
        updatedAt: serverTimestamp(),
      });
    } catch {
      // The UI already uses the repaired location; Firestore cleanup can retry on the next load.
    }
  }

  private async loadStudioCollections(business: StudioBusinessRecord): Promise<void> {
    const db = this.auth.firestoreInstance;
    try {
      const [dealSnapshot, storySnapshot, redemptionSnapshot] = await Promise.all([
        getDocs(query(collection(db, 'deals'), where('businessId', '==', business.id), limit(80))),
        getDocs(query(collection(db, 'stories'), where('businessId', '==', business.id), limit(80))),
        getDocs(query(collection(db, 'redemptions'), where('businessId', '==', business.id), limit(80))),
      ]);
      const deals = [...dealSnapshot.docs].sort(compareSnapshotDateDesc).map((entry) => {
        const data = entry.data();
        return {
          id: entry.id,
          title: String(data['title'] ?? 'Gutschein').trim(),
          subtitle: String(data['subtitle'] ?? '').trim(),
          description: String(data['description'] ?? '').trim(),
          savingsLabel: `${Number(data['savingsPercent'] ?? 0) || 0}% Vorteil`,
          availabilityLabel: String(data['availabilityLabel'] ?? 'Aktiv').trim(),
          validUntilLabel: formatDateLabel(data['validUntil']),
          statusLabel: dealStatusLabel(Boolean(data['isPaused']), Boolean(data['archived'])),
          rawStatus: dealRawStatus(Boolean(data['isPaused']), Boolean(data['archived'])),
          views: Number(data['stats']?.views ?? 0),
          saves: Number(data['stats']?.saves ?? 0),
          activations: Number(data['stats']?.activations ?? 0),
          imageUrl: String(data['imageUrl'] ?? '').trim(),
        } satisfies StudioDealSummary;
      });

      const stories = [...storySnapshot.docs].sort(compareSnapshotDateDesc).map((entry) => {
        const data = entry.data();
        const items = Array.isArray(data['items']) ? data['items'] : [];
        const firstItem = items[0] && typeof items[0] === 'object' ? items[0] : {};
        return {
          id: entry.id,
          label: String(data['label'] ?? 'Story').trim(),
          subtitle: String(data['subtitle'] ?? data['timeLabel'] ?? 'Gerade veröffentlicht').trim(),
          body: String((firstItem as { body?: string }).body ?? '').trim(),
          ctaLabel: String((firstItem as { ctaLabel?: string }).ctaLabel ?? 'Mehr sehen').trim(),
          itemCount: items.length,
          imageUrl: String((firstItem as { imageUrl?: string }).imageUrl ?? '').trim(),
          statusLabel: 'Live',
        } satisfies StudioStorySummary;
      });

      const redemptions = redemptionSnapshot.docs.map((entry) => {
        const data = entry.data();
        return {
          id: entry.id,
          couponId: String(data['couponId'] ?? 'Coupon').trim(),
          code: String(data['code'] ?? '').trim(),
          statusLabel: redemptionStatusLabel(String(data['status'] ?? 'active').trim()),
          dealTitle: resolveDealTitle(String(data['dealId'] ?? '').trim(), deals),
          activatedLabel: formatDateLabel(data['activatedAt']),
          expiresLabel: formatDateLabel(data['expiresAt']),
        } satisfies StudioRedemptionSummary;
      });

      const manualReviewDocs = await this.loadManualReviewDocs(business);
      const manualReviews = manualReviewDocs.map((entry) => {
        const data = entry.data();
        const details =
          data['details'] && typeof data['details'] === 'object'
            ? (data['details'] as Record<string, unknown>)
            : {};
        const extracted =
          details['extracted'] && typeof details['extracted'] === 'object'
            ? (details['extracted'] as Record<string, unknown>)
            : {};
        return {
          auditId: String(data['auditId'] ?? entry.id).trim(),
          status: 'manual_review',
          identityEmail: String(data['identityEmail'] ?? '').trim(),
          identityName: String(data['identityName'] ?? '').trim(),
          claimantName: String(data['claimantName'] ?? '').trim(),
          placeId: String(data['placeId'] ?? '').trim(),
          placeName: String(data['placeName'] ?? '').trim(),
          placeAddress: String(data['placeAddress'] ?? '').trim(),
          fileName: String(data['fileName'] ?? '').trim(),
          score: Number(data['score'] ?? 0),
          createdAtLabel: formatDateLabel(data['createdAt']),
          summary: String(details['summary'] ?? 'Grenzfall für die manuelle Prüfung.').trim(),
          matchedSignals: Array.isArray(details['matchedSignals'])
            ? details['matchedSignals'].map((item) => String(item).trim()).filter(Boolean)
            : [],
          missingSignals: Array.isArray(details['missingSignals'])
            ? details['missingSignals'].map((item) => String(item).trim()).filter(Boolean)
            : [],
          extracted: {
            documentType: String(extracted['documentType'] ?? '').trim(),
            legalEntityName: String(extracted['legalEntityName'] ?? '').trim(),
            tradeName: String(extracted['tradeName'] ?? '').trim(),
            proprietorName: String(extracted['proprietorName'] ?? '').trim(),
            issuingAuthority: String(extracted['issuingAuthority'] ?? '').trim(),
            street: String(extracted['street'] ?? '').trim(),
            postalCode: String(extracted['postalCode'] ?? '').trim(),
            city: String(extracted['city'] ?? '').trim(),
          },
        } satisfies ManualReviewCase;
      });

      this.deals.set(deals);
      this.stories.set(stories);
      this.redemptions.set(redemptions);

      this.manualReviews.set(manualReviews);
    } catch {
      this.deals.set([]);
      this.stories.set([]);
      this.redemptions.set([]);
      this.manualReviews.set([]);
    }
  }

  private async loadManualReviewDocs(business: StudioBusinessRecord) {
    if (!business.verificationPlaceId) {
      return [];
    }

    try {
      return (
        await getDocs(
          query(
            collection(this.auth.firestoreInstance, '_businessDocumentReviews'),
            where('placeId', '==', business.verificationPlaceId),
            where('status', '==', 'manual_review'),
            limit(12),
          ),
        )
      ).docs;
    } catch {
      return [];
    }
  }
}

function isVerifiedBusiness(business: StudioBusinessRecord): boolean {
  return (
    business.verificationStatus.trim().toLowerCase() === 'verified' ||
    !!business.verificationMethod?.trim() ||
    !!business.verificationPlaceId?.trim() ||
    !!business.googleProfileLink?.verificationSessionId?.trim()
  );
}

function normalizeStudioBusinessRepair(
  repaired: StudioBusinessRecord,
  fallback: StudioBusinessRecord,
): StudioBusinessRecord {
  const merged = {
    ...fallback,
    ...repaired,
    analytics: repaired.analytics ?? fallback.analytics ?? null,
    documentReview: repaired.documentReview ?? fallback.documentReview ?? null,
    googleProfileLink: repaired.googleProfileLink ?? fallback.googleProfileLink ?? null,
  };
  return {
    ...merged,
    city: resolveBusinessCity(merged),
    address: resolveBusinessAddress(merged),
    website: repaired.website || fallback.website || repaired.googleProfileLink?.website || '',
    phone: repaired.phone || fallback.phone || repaired.googleProfileLink?.phone || '',
    contactEmail: repaired.contactEmail || fallback.contactEmail,
    legalEntityName: repaired.legalEntityName || fallback.legalEntityName || repaired.name || fallback.name,
  };
}

function resolveBusinessCity(business: StudioBusinessRecord): string {
  const candidates = [
    business.googleProfileLink?.locationCity,
    inferCityFromAddress(business.address),
    business.city,
  ];
  const resolved = candidates.map((item) => cleanLocationValue(item)).find(Boolean) || '';
  return isCityOnlyAddress(resolved, business.city) ? '' : resolved;
}

function resolveBusinessAddress(business: StudioBusinessRecord): string {
  const candidates = [
    business.address,
    business.googleProfileLink?.locationAddress,
  ];
  return candidates.map((item) => cleanLocationValue(item)).find(Boolean) || '';
}

function resolveCityFromBusinessData(data: Record<string, unknown>): string {
  const branch = firstBranch(data);
  const googleProfileLink = objectRecord(data['googleProfileLink']);
  const candidates = [
    googleProfileLink ? String(googleProfileLink['locationCity'] ?? '').trim() : '',
    inferCityFromAddress(String(branch?.['address'] ?? '').trim()),
    String(data['city'] ?? '').trim(),
  ];
  return candidates.map((item) => cleanLocationValue(item)).find(Boolean) || '';
}

function resolveAddressFromBusinessData(data: Record<string, unknown>): string {
  const branch = firstBranch(data);
  const googleProfileLink = objectRecord(data['googleProfileLink']);
  const candidates = [
    String(branch?.['address'] ?? '').trim(),
    googleProfileLink ? String(googleProfileLink['locationAddress'] ?? '').trim() : '',
  ];
  const resolved = candidates.map((item) => cleanLocationValue(item)).find(Boolean) || '';
  return isCityOnlyAddress(resolved, String(data['city'] ?? '').trim()) ? '' : resolved;
}

function firstBranch(data: Record<string, unknown>): Record<string, unknown> | null {
  const branches = Array.isArray(data['branches']) ? data['branches'] : [];
  return objectRecord(branches[0]);
}

function objectRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function cleanLocationValue(value: unknown): string {
  const normalized = String(value ?? '').trim();
  if (
    !normalized ||
    /^deutschlandweit$/i.test(normalized) ||
    /^dein viertel$/i.test(normalized) ||
    /^adresse\s+(folgt|wird)/i.test(normalized) ||
    /^ort\s+wird/i.test(normalized) ||
    /^standort\s+(folgt|verifiziert)$/i.test(normalized)
  ) {
    return '';
  }
  return normalized;
}

function isPreciseStreetAddress(value: string): boolean {
  const clean = cleanLocationValue(value);
  return /\d/.test(clean) && /[a-zäöüß]/i.test(clean) && /(?:straße|str\.|strasse|weg|allee|platz|ring|damm|ufer|gasse|chaussee|markt)\b/i.test(clean);
}

function isCityOnlyAddress(address: string, city: string): boolean {
  const cleanAddress = cleanLocationValue(address).toLowerCase();
  if (!cleanAddress) {
    return true;
  }
  if (isPreciseStreetAddress(cleanAddress)) {
    return false;
  }
  const cleanCity = cleanLocationValue(city).toLowerCase();
  return !!cleanCity && cleanAddress.includes(cleanCity);
}

function inferCityFromAddress(address: string): string {
  const clean = cleanLocationValue(address);
  if (!clean) {
    return '';
  }
  const parts = clean.split(',').map((part) => part.trim()).filter(Boolean);
  if (parts.length >= 2) {
    return parts[parts.length - 2].replace(/^\d{5}\s+/, '').trim();
  }
  const postalMatch = clean.match(/\b\d{5}\s+([^,]+)/);
  return postalMatch?.[1]?.trim() || '';
}

function redemptionStatusLabel(status: string): string {
  switch (status.toLowerCase()) {
    case 'redeemed':
      return 'Eingelöst';
    case 'expired':
      return 'Abgelaufen';
    default:
      return 'Aktiv';
  }
}

function redemptionFilterLabel(
  status: 'active' | 'redeemed' | 'expired',
): string {
  switch (status) {
    case 'redeemed':
      return 'Eingelöst';
    case 'expired':
      return 'Abgelaufen';
    default:
      return 'Aktiv';
  }
}

function dealStatusLabel(isPaused: boolean, archived: boolean): string {
  if (archived) {
    return 'Archiviert';
  }
  if (isPaused) {
    return 'Pausiert';
  }
  return 'Live';
}

function dealRawStatus(
  isPaused: boolean,
  archived: boolean,
): 'live' | 'paused' | 'archived' {
  if (archived) {
    return 'archived';
  }
  if (isPaused) {
    return 'paused';
  }
  return 'live';
}

function resolveDealTitle(dealId: string, deals: StudioDealSummary[]): string {
  return deals.find((deal) => deal.id === dealId)?.title || 'Gutschein';
}

function compareSnapshotDateDesc(
  left: { data(): Record<string, unknown> },
  right: { data(): Record<string, unknown> },
): number {
  return firestoreMillis(right.data()['updatedAt'] ?? right.data()['createdAt']) -
    firestoreMillis(left.data()['updatedAt'] ?? left.data()['createdAt']);
}

function firestoreMillis(value: unknown): number {
  if (value && typeof value === 'object' && 'toMillis' in value && typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  return 0;
}

function formatDateLabel(value: unknown): string {
  const rawDate =
    value && typeof value === 'object' && 'toDate' in (value as Record<string, unknown>)
      ? (value as { toDate: () => Date }).toDate()
      : value instanceof Date
        ? value
        : null;

  if (!rawDate) {
    return 'Gerade';
  }

  return new Intl.DateTimeFormat('de-DE', {
    day: '2-digit',
    month: '2-digit',
  }).format(rawDate);
}

function humanizeStudioError(error: unknown, fallback: string): string {
  const message = error instanceof Error ? error.message.trim() : '';
  if (/missing or insufficient permissions/i.test(message) || /permission-denied/i.test(message)) {
    return 'Aktion blockiert: Dein Business-Konto ist nicht als Mitglied dieses verifizierten Business freigeschaltet. Die Sicherheitsregeln wurden für eigene Gutscheine und Stories korrigiert. Lade neu und versuche es noch einmal.';
  }
  return message || fallback;
}
