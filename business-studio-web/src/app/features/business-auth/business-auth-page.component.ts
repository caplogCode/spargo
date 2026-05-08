import { CommonModule } from '@angular/common';
import { CUSTOM_ELEMENTS_SCHEMA, ChangeDetectionStrategy, Component, DestroyRef, computed, effect, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { chevronDownOutline } from 'ionicons/icons';

import {
  AddressSuggestion,
  DocumentVerificationFailureDetails,
  DocumentVerificationReview,
  NearbyPlace,
  VerificationProgressStep,
} from '../../core/models/business.models';
import { BusinessApiService } from '../../core/services/business-api.service';
import { BusinessFlowService } from '../../core/services/business-flow.service';
import { FirebaseAuthService } from '../../core/services/firebase-auth.service';

type GuidedAction = {
  tone: 'info' | 'warning' | 'success';
  title: string;
  detail: string;
  targetSelector?: string;
  ctaLabel?: string;
};

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: string | HTMLElement,
        options: Record<string, unknown>,
      ) => string;
      reset: (widgetId?: string) => void;
      remove?: (widgetId?: string) => void;
    };
  }
}

@Component({
  selector: 'app-business-auth-page',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  templateUrl: './business-auth-page.component.html',
  styleUrl: './business-auth-page.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class BusinessAuthPageComponent {
  private readonly fb = inject(FormBuilder);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly auth = inject(FirebaseAuthService);
  private readonly api = inject(BusinessApiService);
  private readonly flow = inject(BusinessFlowService);
  private readonly destroyRef = inject(DestroyRef);

  readonly chevronDownIcon = chevronDownOutline;
  readonly mode = signal<'login' | 'register'>('login');
  readonly query = signal('');
  readonly searchSuggestions = signal<AddressSuggestion[]>([]);
  readonly searchResults = signal<NearbyPlace[]>([]);
  readonly selectedPlace = computed(() => this.flow.selectedPlace());
  readonly verificationLink = computed(() => this.flow.verificationLink());
  readonly persistedDocumentReview = computed(() => this.flow.documentReview());
  readonly activeError = signal('');
  readonly guidedAction = signal<GuidedAction | null>(null);
  readonly searchBusy = signal(false);
  readonly suggestionsBusy = signal(false);
  readonly googleBusy = signal(false);
  readonly googleFallbackSuggested = signal(false);
  readonly documentBusy = signal(false);
  readonly registerBusy = signal(false);
  readonly resetBusy = signal(false);
  readonly progressSteps = signal<VerificationProgressStep[]>([]);
  readonly documentReview = signal<DocumentVerificationReview | null>(this.flow.documentReview());
  readonly documentFailureDetails = signal<DocumentVerificationFailureDetails | null>(null);
  readonly chosenDocumentName = signal('');
  readonly captchaToken = signal('');
  readonly captchaStatus = signal<'idle' | 'loading' | 'ready' | 'expired' | 'error'>('loading');
  readonly captchaMessage = computed(() => {
    switch (this.captchaStatus()) {
      case 'ready':
        return this.captchaToken() === 'server-side-safety-check'
          ? 'Sicherheits-Check läuft serverseitig über Rate-Limit und Audit. Du kannst die Unterlage jetzt prüfen.'
          : 'Sicherheits-Check abgeschlossen. Du kannst die Unterlage jetzt direkt prüfen.';
      case 'expired':
        return 'Der Sicherheits-Check ist abgelaufen. Bitte kurz neu bestätigen.';
      case 'error':
        return 'Der sichtbare Sicherheits-Check konnte gerade nicht sauber geladen werden.';
      default:
        return 'Wir laden gerade den sichtbaren Sicherheits-Check für deinen Upload.';
    }
  });
  readonly currentRegisterStep = signal<1 | 2 | 3>(1);
  readonly activeVerificationMethod = signal<'google' | 'documents'>('documents');
  readonly registerStepIndex = computed(() => this.currentRegisterStep() - 1);
  readonly registerTrackOffset = computed(() => this.registerStepIndex() * (100 / 3));

  private documentPayload: { fileName: string; mimeType: string; fileBase64: string } | null = null;
  private searchSuggestTimer: ReturnType<typeof setTimeout> | null = null;
  private searchResultsTimer: ReturnType<typeof setTimeout> | null = null;
  private captchaWidgetId: string | null = null;
  private captchaRenderTimer: ReturnType<typeof setTimeout> | null = null;

  readonly loginForm = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(8)]],
  });

  readonly registerForm = this.fb.nonNullable.group({
    claimantName: ['', [Validators.required, Validators.minLength(3)]],
    contactEmail: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(12)]],
    passwordConfirm: ['', [Validators.required, Validators.minLength(12)]],
  });
  readonly registerFormState = signal(this.registerForm.getRawValue());

  readonly canSubmitRegistration = computed(() => {
    const form = this.registerFormState();
    return (
      !!this.selectedPlace() &&
      !!this.verificationLink() &&
      isStrongBusinessPassword(form.password) &&
      form.password.trim() === form.passwordConfirm.trim()
    );
  });

  readonly registerPasswordMismatch = computed(() => {
    const form = this.registerFormState();
    return !!form.passwordConfirm && form.password.trim() !== form.passwordConfirm.trim();
  });

  readonly registerPasswordTooShort = computed(() => {
    const form = this.registerFormState();
    return !!form.password && form.password.trim().length > 0 && form.password.trim().length < 12;
  });

  readonly registerPasswordNeedsStrength = computed(() => {
    const form = this.registerFormState();
    return !!form.password && form.password.trim().length >= 12 && !isStrongBusinessPassword(form.password);
  });

  readonly verificationLabel = computed(() => {
    const mode = this.flow.verificationMode();
    if (mode === 'google') {
      return 'Google Business bestätigt';
    }
    if (mode === 'document') {
      return 'Unterlagen serverseitig bestätigt';
    }
    return 'Noch nicht verifiziert';
  });

  constructor() {
    const query = this.route.snapshot.queryParamMap;
    if (query.get('continueBusinessRegistration') === '1' || query.get('mode') === 'business-registration') {
      this.mode.set('register');
      this.currentRegisterStep.set(1);
    }

    const draft = this.flow.draft();
    this.registerForm.patchValue({
      claimantName: draft.claimantName,
      contactEmail: draft.businessEmail,
    });
    this.registerFormState.set(this.registerForm.getRawValue());

    const registerSub = this.registerForm.valueChanges.subscribe(() => {
      this.registerFormState.set(this.registerForm.getRawValue());
    });
    this.destroyRef.onDestroy(() => {
      registerSub.unsubscribe();
      if (this.searchSuggestTimer) {
        clearTimeout(this.searchSuggestTimer);
      }
      if (this.searchResultsTimer) {
        clearTimeout(this.searchResultsTimer);
      }
      if (this.captchaRenderTimer) {
        clearTimeout(this.captchaRenderTimer);
      }
    });

    effect(() => {
      const step = this.currentRegisterStep();
      const place = this.selectedPlace();
      const link = this.verificationLink();

      if (step >= 2 && !place) {
        queueMicrotask(() => this.currentRegisterStep.set(1));
        return;
      }

      if (step === 3 && !link) {
        queueMicrotask(() => this.currentRegisterStep.set(place ? 2 : 1));
      }
    });

    effect(() => {
      const currentMode = this.mode();
      const step = this.currentRegisterStep();
      queueMicrotask(() => {
        if (currentMode === 'login') {
          this.scrollRegisterIntoView('.auth-card');
          return;
        }

        if (step === 1) {
          this.scrollRegisterIntoView('.workspace-panel--search');
        } else if (step === 2) {
          this.scrollRegisterIntoView('.workspace-panel--verification');
        } else if (step === 3) {
          this.scrollRegisterIntoView('.workspace-panel--credentials');
        }
      });
    });

    effect(() => {
      if (this.mode() !== 'register' || this.currentRegisterStep() !== 2) {
        return;
      }

      this.scheduleCaptchaRender();
    });

    effect(() => {
      const error = this.activeError();
      const guidance = this.guidedAction();
      if (!error || guidance?.targetSelector) {
        return;
      }

      queueMicrotask(() => this.scrollRegisterIntoView('.error-banner'));
    });
  }

  setMode(mode: 'login' | 'register'): void {
    this.activeError.set('');
    this.guidedAction.set(null);
    this.mode.set(mode);
    if (mode === 'register' && this.selectedPlace()) {
      this.currentRegisterStep.set(this.verificationLink() ? 3 : 2);
    }
  }

  goToRegisterStep(step: 1 | 2 | 3): void {
    this.guidedAction.set(null);
    if (step === 1) {
      this.currentRegisterStep.set(1);
      queueMicrotask(() => this.scrollRegisterIntoView('.workspace-panel--search'));
      return;
    }
    if (step === 2 && this.selectedPlace()) {
      this.currentRegisterStep.set(2);
      queueMicrotask(() => this.scrollRegisterIntoView('.workspace-panel--verification'));
      return;
    }
    if (step === 3 && this.verificationLink()) {
      this.currentRegisterStep.set(3);
      queueMicrotask(() => this.scrollRegisterIntoView('.workspace-panel--credentials'));
    }
  }

  setVerificationMethod(method: 'google' | 'documents'): void {
    this.activeVerificationMethod.set(method);
    this.guidedAction.set(null);
    queueMicrotask(() => this.scrollRegisterIntoView('.verification-stage'));
  }

  onSearchInput(value: string): void {
    this.query.set(value);
    this.activeError.set('');
    this.guidedAction.set(null);

    if (this.searchSuggestTimer) {
      clearTimeout(this.searchSuggestTimer);
    }
    if (this.searchResultsTimer) {
      clearTimeout(this.searchResultsTimer);
    }

    const normalized = value.trim();
    if (normalized.length < 2) {
      this.searchSuggestions.set([]);
      this.searchResults.set([]);
      this.suggestionsBusy.set(false);
      this.searchBusy.set(false);
      return;
    }

    this.suggestionsBusy.set(true);
    this.searchSuggestTimer = setTimeout(async () => {
      try {
        const suggestions = await this.api.searchBusinessSuggestions(normalized);
        if (this.query().trim() === normalized) {
          this.searchSuggestions.set(suggestions);
        }
      } catch {
        if (this.query().trim() === normalized) {
          this.searchSuggestions.set([]);
        }
      } finally {
        if (this.query().trim() === normalized) {
          this.suggestionsBusy.set(false);
        }
      }
    }, 120);

    this.searchBusy.set(true);
    this.searchResultsTimer = setTimeout(async () => {
      try {
        const results = await this.api.searchBusinesses(normalized);
        if (this.query().trim() === normalized) {
          this.searchResults.set(results);
          if (!results.length) {
            this.setGuidedAction({
              tone: 'info',
              title: 'Suche direkt verfeinern',
              detail:
                'Wir haben noch keinen klaren Standort gefunden. Ergänze am besten Stadt, Straße oder den exakten Laden-Namen.',
              targetSelector: '.input-shell--search',
              ctaLabel: 'Suchfeld öffnen',
            });
          }
        }
      } catch (error) {
        if (this.query().trim() === normalized) {
          this.activeError.set(normalizeError(error));
          this.setGuidedAction({
            tone: 'warning',
            title: 'Suche hier sofort weiterführen',
            detail:
              'Wir haben dich direkt zurück ins Suchfeld geführt. Passe den Namen oder Ort an und wir versuchen es sofort erneut.',
            targetSelector: '.input-shell--search',
            ctaLabel: 'Zur Suche',
          });
        }
      } finally {
        if (this.query().trim() === normalized) {
          this.searchBusy.set(false);
        }
      }
    }, 260);
  }

  async searchPlaces(): Promise<void> {
    const query = this.query().trim();
    if (query.length < 2) {
      this.searchResults.set([]);
      return;
    }

    this.activeError.set('');
    this.guidedAction.set(null);
    this.searchBusy.set(true);
    this.searchSuggestions.set([]);
    try {
      const results = await this.api.searchBusinesses(query);
      this.searchResults.set(results);
      if (!results.length) {
        this.setGuidedAction({
          tone: 'info',
          title: 'Suche verfeinern',
          detail:
            'Wir haben gerade keinen klaren Standort gefunden. Ergänze am besten Stadt, Straße oder den offiziellen Laden-Namen.',
          targetSelector: '.input-shell--search',
          ctaLabel: 'Suche anpassen',
        });
      }
    } catch (error) {
      this.activeError.set(normalizeError(error));
      this.setGuidedAction({
        tone: 'warning',
        title: 'Suche direkt hier fortsetzen',
        detail:
          'Wir haben dich wieder zur Suche geführt. Passe den Namen oder die Stadt an und probiere es direkt erneut.',
        targetSelector: '.input-shell--search',
        ctaLabel: 'Suchfeld öffnen',
      });
    } finally {
      this.searchBusy.set(false);
    }
  }

  choosePlace(place: NearbyPlace): void {
    this.flow.setSelectedPlace(place);
    this.flow.setClaimantName(this.registerForm.controls.claimantName.value);
    this.flow.setBusinessEmail('');
    this.searchResults.set([]);
    this.searchSuggestions.set([]);
    this.query.set(place.name);
    this.activeError.set('');
    this.guidedAction.set({
      tone: 'success',
      title: 'Standort übernommen',
      detail:
        'Perfekt. Wir haben deinen Standort übernommen und führen dich jetzt direkt zur Bestätigung.',
    });
    this.progressSteps.set([]);
    this.documentReview.set(null);
    this.documentFailureDetails.set(null);
    this.googleFallbackSuggested.set(false);
    this.activeVerificationMethod.set('documents');
    this.currentRegisterStep.set(2);
    queueMicrotask(() => this.scrollRegisterIntoView('.workspace-panel--verification'));
  }

  clearPlace(): void {
    this.flow.setSelectedPlace(null);
    this.progressSteps.set([]);
    this.documentReview.set(null);
    this.googleFallbackSuggested.set(false);
    this.activeVerificationMethod.set('documents');
    this.currentRegisterStep.set(1);
    this.guidedAction.set(null);
    queueMicrotask(() => this.scrollRegisterIntoView('.workspace-panel--search'));
  }

  async chooseSuggestion(suggestion: AddressSuggestion): Promise<void> {
    const nextQuery = `${suggestion.title} ${suggestion.addressLine}`.trim();
    this.query.set(nextQuery);
    this.searchSuggestions.set([]);
    await this.searchPlaces();
  }

  async login(): Promise<void> {
    if (this.loginForm.invalid) {
      this.loginForm.markAllAsTouched();
      return;
    }

    this.activeError.set('');
    this.registerBusy.set(true);
    try {
      await this.auth.login(this.loginForm.controls.email.value, this.loginForm.controls.password.value);
      const profile = this.auth.profile();
      await this.router.navigateByUrl(profile?.ownedBusinessId ?'/business-studio' : '/business-onboarding');
    } catch (error) {
      this.activeError.set(normalizeError(error));
      queueMicrotask(() => this.scrollRegisterIntoView('.error-banner'));
    } finally {
      this.registerBusy.set(false);
    }
  }

  async sendReset(): Promise<void> {
    const email = this.loginForm.controls.email.value.trim();
    if (!email) {
      this.activeError.set('Trage zuerst deine Business-E-Mail ein, dann können wir den Reset losschicken.');
      this.setGuidedAction({
        tone: 'info',
        title: 'E-Mail zuerst eintragen',
        detail: 'Wir haben dich direkt zum Login-Feld zurückgeführt. Trage dort zuerst deine Business-E-Mail ein.',
        targetSelector: '.auth-form .auth-field:first-child .input-shell',
        ctaLabel: 'Zum E-Mail-Feld',
      });
      return;
    }

    this.activeError.set('');
    this.resetBusy.set(true);
    try {
      await this.auth.sendPasswordReset(email);
      this.activeError.set('Reset-Link wurde verschickt. Schau bitte in dein Postfach.');
    } catch (error) {
      this.activeError.set(normalizeError(error));
      queueMicrotask(() => this.scrollRegisterIntoView('.error-banner'));
    } finally {
      this.resetBusy.set(false);
    }
  }

  async verifyWithGoogle(): Promise<void> {
    const place = this.selectedPlace();
    if (!place) {
      this.activeError.set('Wähle zuerst den richtigen Standort aus.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Zuerst Standort wählen',
        detail: 'Wir bringen dich direkt zurück zu Schritt 1, damit du zuerst den richtigen Ort auswählen kannst.',
        targetSelector: '.workspace-panel--search',
        ctaLabel: 'Zu Schritt 1',
      });
      return;
    }

    this.flow.setClaimantName(this.registerForm.controls.claimantName.value);
    this.activeError.set('');
    this.googleFallbackSuggested.set(false);
    this.documentReview.set(null);
    this.documentFailureDetails.set(null);
    this.googleBusy.set(true);
    this.progressSteps.set([
      step(
        'Google-Konto wird geöffnet',
        'Wir holen nur den verifizierten Business-Zugriff für diesen Standort.',
        'active',
      ),
      step(
        'Standort wird geprüft',
        'Der Server gleicht genau diesen Place mit deinen Google-Business-Rechten ab.',
        'idle',
      ),
      step(
        'Identität wird übernommen',
        'Die bestätigte Business-Mail wandert danach direkt in deinen Studio-Zugang.',
        'idle',
      ),
    ]);

    try {
      const identity = await this.auth.authorizeGoogleBusinessIdentity();
      this.progressSteps.update(markDone(0));
      this.progressSteps.update(markActive(1));
      let link;
      try {
        link = await this.api.verifyGoogleBusinessPlace(place, identity);
      } catch (directError) {
        const directMessage = normalizeError(directError);
        const canTryIdentityFallback = !!String(place.websiteUrl || '').trim();

        if (!canTryIdentityFallback) {
          throw directError;
        }

        this.progressSteps.set([
          step(
            'Google-Zugriff ist bestätigt',
            'Dein Google-Konto ist offen und wir prüfen jetzt die Unternehmens-Identität.',
            'done',
          ),
          step(
            'Direkter Google-Business-Zugriff war nicht stabil',
            'Wir wechseln automatisch auf den bestätigten Unternehmens-Abgleich.',
            'active',
          ),
          step(
            'Identität wird übernommen',
            'Wenn E-Mail, Website und Standort passen, geht es direkt weiter.',
            'idle',
          ),
        ]);

        link = await this.api.verifyGoogleBusinessCompanyIdentity(place, identity);
      }
      this.progressSteps.update(markDone(1));
      this.progressSteps.update(markDone(2));
      this.flow.setVerification(link, 'google');
      this.documentReview.set(null);
      this.registerForm.patchValue({
        contactEmail: link.googleUserEmail,
      });
      this.activeError.set('');
      this.googleFallbackSuggested.set(false);
      this.guidedAction.set({
        tone: 'success',
        title: 'Google Business bestätigt',
        detail:
          'Die Identität passt. Wir öffnen jetzt direkt Schritt 3, damit du nur noch dein Passwort festlegst.',
      });
      this.currentRegisterStep.set(3);
      queueMicrotask(() => this.scrollRegisterIntoView('.workspace-panel--credentials'));
    } catch (error) {
      const message = normalizeError(error);
      if (isGoogleQuotaMessage(message)) {
        this.progressSteps.set([
          step(
            'Google Business ist ausgelastet',
            'Der direkte Google-Claim ist gerade nicht verfügbar.',
            'error',
          ),
          step(
            'Unterlagenpfad ist bereit',
            'Nutze direkt die offizielle Unterlagen-Prüfung darunter. Standort und Eingaben bleiben erhalten.',
            'active',
          ),
        ]);
        this.googleFallbackSuggested.set(true);
        this.activeVerificationMethod.set('documents');
        this.activeError.set(
          'Google Business ist gerade ausgelastet. Nutze jetzt direkt die sichere Unterlagen-Prüfung darunter.',
        );
        this.guideToDocumentProof(
          'Unterlagen-Prüfung jetzt direkt verwenden',
          'Google ist gerade ausgelastet. Wir haben für dich automatisch auf den sicheren Unterlagen-Weg umgeschaltet.',
        );
      } else if (needsCompanyDomainFallback(message)) {
        this.activeVerificationMethod.set('documents');
        this.activeError.set('');
        this.guideToDocumentProof(
          'Unterlagen statt Firmen-Domain nutzen',
          'Für diesen Schnellweg fehlt keine “Lösung”, sondern nur ein anderer Prüfpfad. Wir haben dich direkt zur Unterlagen-Prüfung geführt.',
        );
      } else {
        this.progressSteps.update(markError(1));
        this.activeError.set(message);
        this.setGuidedAction({
          tone: 'warning',
          title: 'Wir führen dich zur richtigen Stelle',
          detail:
            'Der aktuelle Google-Weg konnte nicht fertig geprüft werden. Wir haben den betroffenen Bereich für dich fokussiert.',
          targetSelector: '.verification-stage',
          ctaLabel: 'Zum Prüfbereich',
        });
      }
    } finally {
      this.googleBusy.set(false);
    }
  }

  async onDocumentSelected(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement | null;
    const file = input?.files?.[0];
    if (!file) {
      return;
    }

    const fileBase64 = await toBase64(file);
    this.documentPayload = {
      fileName: file.name,
      mimeType: file.type || 'application/octet-stream',
      fileBase64,
    };
    this.chosenDocumentName.set(file.name);
  }

  async verifyDocument(): Promise<void> {
    const place = this.selectedPlace();
    const claimantName = this.registerForm.controls.claimantName.value.trim();
    const businessEmail = this.registerForm.controls.contactEmail.value.trim().toLowerCase();

    if (!place) {
      this.activeError.set('Wähle zuerst den richtigen Standort aus.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Standort zuerst festlegen',
        detail: 'Wir bringen dich zurück zur Suche, damit die Prüfung auf den richtigen Standort gebunden wird.',
        targetSelector: '.workspace-panel--search',
        ctaLabel: 'Zur Suche',
      });
      return;
    }
    if (!claimantName) {
      this.activeError.set('Wir brauchen den Namen der verantwortlichen Person für die Unterlagenprüfung.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Name laut Nachweis eintragen',
        detail:
          'Trage hier die verantwortliche Person so ein, wie sie auf dem Nachweis steht. Wir führen dich direkt zum Feld.',
        targetSelector: '.verification-method--documents .auth-field:first-child .input-shell',
        ctaLabel: 'Zum Namensfeld',
      });
      return;
    }
    if (!businessEmail) {
      this.activeError.set('Trage die Business-E-Mail ein, die später den Studio-Zugang bekommen soll.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Business-E-Mail ergänzen',
        detail:
          'Jetzt fehlt nur noch die E-Mail, die später den Studio-Zugang bekommen soll. Wir haben das passende Feld fokussiert.',
        targetSelector: '.verification-method--documents .auth-field:nth-child(2) .input-shell',
        ctaLabel: 'Zum E-Mail-Feld',
      });
      return;
    }
    if (!this.documentPayload) {
      this.activeError.set('Bitte lade zuerst eine offizielle Unterlage hoch.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Unterlage jetzt hochladen',
        detail:
          'Wir haben dich direkt zum Upload geführt. Nutze am besten einen gut lesbaren amtlichen Nachweis mit Name und Adresse.',
        targetSelector: '.upload-shell',
        ctaLabel: 'Zum Upload',
      });
      return;
    }
    if (!this.captchaToken()) {
      this.activeError.set(
        'Klicke im Sicherheits-Check direkt unter dem Datei-Upload auf die Cloudflare-Box. Danach kannst du die Unterlage prüfen.',
      );
      this.setGuidedAction({
        tone: 'info',
        title: 'Sicherheits-Check kurz bestätigen',
        detail:
          'Wir haben dich direkt zum Sicherheitsfeld geführt. Klicke dort auf die Cloudflare-Box. Wenn sie nicht sichtbar ist, nutze “Neu laden”.',
        targetSelector: '.captcha-card',
        ctaLabel: 'Zum Sicherheits-Check',
      });
      queueMicrotask(() => this.scrollRegisterIntoView('.captcha-card'));
      return;
    }

    this.flow.setClaimantName(claimantName);
    this.flow.setBusinessEmail(businessEmail);
    this.activeError.set('');
    this.googleFallbackSuggested.set(false);
    this.documentReview.set(null);
    this.documentFailureDetails.set(null);
    this.documentBusy.set(true);
    this.progressSteps.set([
      step(
        'Unterlage wird vorbereitet',
        'Die Datei wird lokal verarbeitet und direkt serverseitig übermittelt.',
        'active',
      ),
      step(
        'OCR und KI prüfen das Dokument',
        'Wir lesen Name, Rolle, Standort und amtliche Merkmale aus.',
        'idle',
      ),
      step(
        'Register- und Ortsabgleich läuft',
        'Zusätzliche Signale werden mit dem gewählten Standort zusammengeführt.',
        'idle',
      ),
      step(
        'Business-Identität wird gesichert',
        'Nur bei eindeutigem Treffer wird die Studio-Freigabe ausgestellt.',
        'idle',
      ),
    ]);

    try {
      this.progressSteps.update(markDone(0));
      this.progressSteps.update(markActive(1));
      const result = await this.api.verifyBusinessDocuments({
        claimantName,
        businessEmail,
        place,
        ...this.documentPayload,
        captchaToken: this.captchaToken(),
      });
      if (result.pendingManualReview) {
        this.documentReview.set(result.review);
        this.documentFailureDetails.set(result.details ?? null);
        this.progressSteps.set([
          step(
            'Automatische Prüfung sauber gestartet',
            'Dokument, Ort und Identität wurden aufgenommen und bewertet.',
            'done',
          ),
          step(
            'Manuelle Business-Prüfung vorbereitet',
            'Ein Grenzfall wurde erkannt. Wir halten alle Signale sichtbar fest und geben die Freigabe erst nach zusätzlicher Prüfung frei.',
            'active',
          ),
        ]);
        this.activeError.set(
          result.details?.summary ||
            'Die automatische Prüfung war nicht eindeutig genug. Wir haben den Fall sauber in die manuelle Review-Stufe überführt.',
        );
        this.setGuidedAction({
          tone: 'warning',
          title: 'Manuelle Review ist vorbereitet',
          detail:
            'Der Fall ist nicht verloren. Wir zeigen dir jetzt genau, was erkannt wurde, und halten den Upload-Bereich für mögliche Nachschärfung direkt offen.',
          targetSelector: '.document-guidance-card, .verification-method--documents',
          ctaLabel: 'Zur Review',
        });
        return;
      }
      const link = result.link;
      if (!link) {
        throw new Error(
          'Die Dokumentenprüfung konnte noch keine sichere Freigabe oder Review-Stufe erzeugen.',
        );
      }
      this.documentReview.set(result.review);
      this.documentFailureDetails.set(null);
      this.progressSteps.update(markDone(1));
      this.progressSteps.update(markDone(2));
      this.progressSteps.update(markDone(3));
      this.flow.setVerification(link, 'document', result.review);
      this.registerForm.patchValue({
        contactEmail: link.googleUserEmail,
      });
      this.guidedAction.set({
        tone: 'success',
        title: 'Unterlagen erfolgreich bestätigt',
        detail:
          'Die KI- und Dokumentenprüfung war erfolgreich. Wir öffnen jetzt direkt Schritt 3 für deinen Studio-Zugang.',
      });
      this.currentRegisterStep.set(3);
      queueMicrotask(() => this.scrollRegisterIntoView('.workspace-panel--credentials'));
    } catch (error) {
      const details = extractDocumentFailureDetails(error);
      this.documentFailureDetails.set(details);
      this.progressSteps.update(markError(1));
      this.activeError.set(normalizeError(error));
      if (details) {
        this.progressSteps.set(buildFailureProgress(details));
      }
      this.setGuidedAction({
        tone: 'warning',
        title: 'Unterlagen hier nachschärfen',
        detail:
          'Die Prüfung sagt dir jetzt konkret, welche Signale schon passen und was noch fehlt. Wir haben den relevanten Bereich direkt für dich fokussiert.',
        targetSelector: '.document-guidance-card, .verification-method--documents',
        ctaLabel: 'Zur Unterlagen-Prüfung',
      });
    } finally {
      this.documentBusy.set(false);
    }
  }

  async register(): Promise<void> {
    if (!this.canSubmitRegistration()) {
      this.registerForm.markAllAsTouched();
      this.activeError.set('Erst Standort sauber verifizieren, dann Passwort setzen.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Verifikation zuerst abschließen',
        detail:
          'Bevor du den Zugang anlegst, muss die Business-Verifikation abgeschlossen sein. Wir führen dich direkt dorthin.',
        targetSelector: '.workspace-panel--verification',
        ctaLabel: 'Zur Verifikation',
      });
      return;
    }

    const place = this.selectedPlace();
    const link = this.verificationLink();
    if (!place || !link) {
      this.activeError.set('Die Business-Verifikation fehlt noch.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Business erst bestätigen',
        detail:
          'Wir bringen dich direkt zurück in Schritt 2. Dort schließen wir die Verifikation zuerst sauber ab.',
        targetSelector: '.workspace-panel--verification',
        ctaLabel: 'Zu Schritt 2',
      });
      return;
    }

    const { password, passwordConfirm } = this.registerForm.getRawValue();
    if (password !== passwordConfirm) {
      this.activeError.set('Die Passwörter müssen exakt gleich sein.');
      this.setGuidedAction({
        tone: 'info',
        title: 'Passwörter angleichen',
        detail:
          'Wir haben dich direkt zum Passwort-Bereich geführt. Trage beide Felder identisch ein, dann geht es sofort weiter.',
        targetSelector: '.register-credentials',
        ctaLabel: 'Zum Passwort-Bereich',
      });
      return;
    }

    this.activeError.set('');
    this.registerBusy.set(true);
    try {
      await this.auth.registerBusinessAccount({
        email: this.flow.businessEmail(),
        password,
        businessName: place.name,
      });
      await this.router.navigateByUrl('/business-onboarding');
    } catch (error) {
      this.activeError.set(normalizeError(error));
      queueMicrotask(() => this.scrollRegisterIntoView('.error-banner'));
    } finally {
      this.registerBusy.set(false);
    }
  }

  retryCaptcha(): void {
    this.captchaStatus.set('loading');
    this.captchaToken.set('');
    if (this.captchaWidgetId && window.turnstile) {
      try {
        window.turnstile.reset(this.captchaWidgetId);
      } catch {
        this.captchaWidgetId = null;
      }
    }
    this.scheduleCaptchaRender();
  }

  triggerGuidedAction(): void {
    const guidance = this.guidedAction();
    if (!guidance?.targetSelector) {
      return;
    }

    this.prepareGuidedRoute(guidance.targetSelector);
    window.setTimeout(() => {
      this.scrollRegisterIntoView(guidance.targetSelector!);
      this.focusTarget(guidance.targetSelector!);
    }, 90);
  }

  private guideToDocumentProof(title: string, detail: string): void {
    this.activeVerificationMethod.set('documents');
    this.currentRegisterStep.set(2);
    this.setGuidedAction({
      tone: 'info',
      title,
      detail,
      targetSelector: '.verification-method--documents',
      ctaLabel: 'Zur Unterlagen-Prüfung',
    });
  }

  private setGuidedAction(action: GuidedAction): void {
    this.guidedAction.set(action);
    if (action.targetSelector) {
      this.prepareGuidedRoute(action.targetSelector);
      window.setTimeout(() => {
        this.scrollRegisterIntoView(action.targetSelector!);
        this.focusTarget(action.targetSelector!);
      }, 90);
    }
  }

  private prepareGuidedRoute(selector: string): void {
    if (selector.startsWith('.auth-form') || selector === '.error-banner') {
      this.mode.set('login');
      return;
    }

    this.mode.set('register');

    if (selector.includes('workspace-panel--search')) {
      this.currentRegisterStep.set(1);
      return;
    }

    if (selector.includes('verification-method--documents') || selector.includes('.upload-shell')) {
      this.currentRegisterStep.set(2);
      this.activeVerificationMethod.set('documents');
      return;
    }

    if (selector.includes('workspace-panel--verification') || selector.includes('.verification-stage')) {
      this.currentRegisterStep.set(2);
      return;
    }

    if (selector.includes('workspace-panel--credentials') || selector.includes('.register-credentials')) {
      if (this.verificationLink()) {
        this.currentRegisterStep.set(3);
      }
    }
  }

  private focusTarget(selector: string): void {
    const target = document.querySelector(selector);
    if (!(target instanceof HTMLElement)) {
      return;
    }

    const focusable =
      target.matches('input,button,textarea,[tabindex]')
        ? target
        : target.querySelector<HTMLElement>('input, button, textarea, [tabindex]');
    focusable?.focus({ preventScroll: true });
  }

  private scrollRegisterIntoView(selector: string): void {
    const target = document.querySelector(selector);
    if (!(target instanceof HTMLElement)) {
      return;
    }

    const shell = target.closest('.register-shell, .login-shell');
    if (shell instanceof HTMLElement) {
      const shellTop = window.scrollY + shell.getBoundingClientRect().top - 12;
      window.scrollTo({
        top: Math.max(0, shellTop),
        behavior: 'smooth',
      });
    }

    const scrollHost = target.closest('.register-workspace, .auth-card');
    if (scrollHost instanceof HTMLElement) {
      const hostRect = scrollHost.getBoundingClientRect();
      const targetRect = target.getBoundingClientRect();
      const nextTop = scrollHost.scrollTop + (targetRect.top - hostRect.top) - 20;
      scrollHost.scrollTo({
        top: Math.max(0, nextTop),
        behavior: 'smooth',
      });
    }

    const pageTop = window.scrollY + target.getBoundingClientRect().top - 20;
    window.scrollTo({
      top: Math.max(0, pageTop),
      behavior: 'smooth',
    });

    target.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
      inline: 'nearest',
    });
  }

  private scheduleCaptchaRender(): void {
    if (this.captchaRenderTimer) {
      clearTimeout(this.captchaRenderTimer);
    }
    this.captchaRenderTimer = window.setTimeout(() => this.renderCaptchaWidget(), 60);
  }

  private renderCaptchaWidget(): void {
    const host = document.getElementById('spargo-turnstile');
    if (!(host instanceof HTMLElement)) {
      return;
    }

    const siteKey =
      document
        .querySelector<HTMLMetaElement>('meta[name="spargo-turnstile-site-key"]')
        ?.content?.trim() || '1x00000000000000000000AA';

    if (isTurnstilePlaceholderKey(siteKey)) {
      host.innerHTML =
        '<div class="captcha-card__server-check">Serverseitiger Sicherheits-Check aktiv</div>';
      this.captchaToken.set('server-side-safety-check');
      this.captchaStatus.set('ready');
      return;
    }

    if (this.captchaWidgetId && window.turnstile) {
      return;
    }

    if (!window.turnstile?.render) {
      this.captchaStatus.set('loading');
      this.captchaRenderTimer = window.setTimeout(() => this.renderCaptchaWidget(), 240);
      return;
    }

    host.innerHTML = '';
    this.captchaStatus.set('loading');
    this.captchaWidgetId = window.turnstile.render(host, {
      sitekey: siteKey,
      theme: 'light',
      size: 'normal',
      action: 'verify-business-evidence-document',
      callback: (token: string) => {
        this.captchaToken.set(String(token || '').trim());
        this.captchaStatus.set('ready');
      },
      'expired-callback': () => {
        this.captchaToken.set('');
        this.captchaStatus.set('expired');
      },
      'error-callback': () => {
        this.captchaToken.set('');
        this.captchaStatus.set('error');
      },
    });
  }
}

function isTurnstilePlaceholderKey(siteKey: string): boolean {
  const normalized = siteKey.trim();
  return !normalized || normalized === '1x00000000000000000000AA';
}

function normalizeError(error: unknown): string {
  const details = extractDocumentFailureDetails(error);
  if (details?.summary) {
    return details.summary;
  }

  if (error instanceof Error && error.message.trim()) {
    const raw = error.message
      .trim()
      .replaceAll('F?r', 'Für')
      .replaceAll('für', 'für')
      .replaceAll('g?ltige', 'gültige')
      .replaceAll('bestätigte', 'bestätigte')
      .replaceAll('best?tigen', 'bestätigen')
      .replaceAll('Identit?t', 'Identität')
      .replaceAll('verkn?pfte', 'verknüpfte')
      .replaceAll('m?glich', 'möglich')
      .replaceAll('f?hren', 'führen')
      .replaceAll('prüfen', 'prüfen')
      .replaceAll('Prüfung', 'Prüfung')
      .replaceAll('bestätigte', 'bestätigte')
      .replaceAll('Identit?t', 'Identität')
      .replaceAll('m?glich', 'möglich');

    const normalized = raw.toLowerCase();
    if (normalized.includes('firmen-e-mail') || normalized.includes('unternehmens-domain')) {
      return 'Google konnte dein Business über diesen Schnellweg nicht eindeutig zuordnen. Wir führen dich jetzt direkt mit der Unterlagen-Prüfung weiter.';
    }
    if (
      normalized.includes('offiziellen unterlagen passen nicht eindeutig') ||
      normalized.includes('starken dokumenten-treffer') ||
      normalized.includes('passen noch nicht stark genug')
    ) {
      return 'Die Unterlage wurde noch nicht stark genug mit deinem ausgewählten Standort verknüpft. Wir führen dich direkt zur Nachweis-Prüfung zurück und fokussieren den Bereich, der noch nachgeschärft werden muss.';
    }
    return raw;
  }
  return 'Das Business Studio konnte diese Aktion gerade nicht sauber abschließen.';
}

function extractDocumentFailureDetails(
  error: unknown,
): DocumentVerificationFailureDetails | null {
  if (!error || typeof error !== 'object' || !('details' in error)) {
    return null;
  }

  const details = (error as { details?: DocumentVerificationFailureDetails }).details;
  return details ?? null;
}

function buildFailureProgress(
  details: DocumentVerificationFailureDetails,
): VerificationProgressStep[] {
  const hasMatches = details.matchedSignals.length > 0;
  const focusLabel =
    details.suggestedFocus === 'upload'
      ? 'Amtlichen Nachweis schärfen'
      : details.suggestedFocus === 'name'
        ? 'Verantwortliche Person prüfen'
        : details.suggestedFocus === 'email'
          ? 'Business-E-Mail prüfen'
          : 'Standortdaten prüfen';

  return [
    step(
      hasMatches ? 'Bereits sauber erkannt' : 'Dokument angekommen',
      hasMatches
        ? `Schon passend: ${details.matchedSignals.join(', ')}.`
        : 'Die Unterlage ist da, aber wir brauchen noch klarere strukturierte Signale.',
      hasMatches ? 'done' : 'active',
    ),
    step(
      focusLabel,
      details.missingSignals.length
        ? `Noch offen: ${details.missingSignals.join(', ')}.`
        : 'Wir führen dich direkt auf den Bereich, der jetzt am meisten hilft.',
      'error',
    ),
  ];
}

function isGoogleQuotaMessage(message: string): boolean {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('google business api limit') ||
    normalized.includes('limit gerade erreicht') ||
    normalized.includes('quota') ||
    normalized.includes('429') ||
    normalized.includes('gerade ausgelastet') ||
    normalized.includes('warte kurz und versuche es erneut')
  );
}

function needsCompanyDomainFallback(message: string): boolean {
  const normalized = message.toLowerCase();
  return (
    normalized.includes('firmen-e-mail') ||
    normalized.includes('unternehmens-domain') ||
    normalized.includes('offiziellen unternehmens-domain') ||
    normalized.includes('google-e-mail passt nicht zur offiziellen unternehmens-domain')
  );
}

function step(title: string, detail: string, state: VerificationProgressStep['state']): VerificationProgressStep {
  return { title, detail, state };
}

function markDone(index: number) {
  return (steps: VerificationProgressStep[]) =>
    steps.map((item, current) => (current === index ?{ ...item, state: 'done' as const } : item));
}

function markActive(index: number) {
  return (steps: VerificationProgressStep[]) =>
    steps.map((item, current) => (current === index ? { ...item, state: 'active' as const } : item));
}

function markError(index: number) {
  return (steps: VerificationProgressStep[]) =>
    steps.map((item, current) => (current === index ? { ...item, state: 'error' as const } : item));
}

function toBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = typeof reader.result === 'string' ? reader.result : '';
      const base64 = result.includes(',') ? result.split(',')[1] : result;
      resolve(base64);
    };
    reader.onerror = () => reject(reader.error ?? new Error('Datei konnte nicht gelesen werden.'));
    reader.readAsDataURL(file);
  });
}

function isStrongBusinessPassword(value: string): boolean {
  const input = value.trim();
  return (
    input.length >= 12 &&
    /[A-ZÄÖÜ]/.test(input) &&
    /[a-zäöüß]/.test(input) &&
    /\d/.test(input) &&
    /[^A-Za-z0-9ÄÖÜäöüß]/.test(input)
  );
}


