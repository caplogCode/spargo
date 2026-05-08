import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import {
  GoogleAuthProvider,
  User,
  createUserWithEmailAndPassword,
  getAuth,
  onAuthStateChanged,
  sendEmailVerification,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
} from 'firebase/auth';
import { FirebaseApp, FirebaseOptions, initializeApp } from 'firebase/app';
import { doc, getDoc, getFirestore, serverTimestamp, setDoc } from 'firebase/firestore';

import { BusinessUserProfile, GoogleBusinessIdentity } from '../models/business.models';
import { firebaseConfig } from '../firebase.config';

const primaryApp = initializeApp(firebaseConfig);
const primaryAuth = getAuth(primaryApp);
const firestore = getFirestore(primaryApp);
const googleIdentityApp = ensureSecondaryApp(firebaseConfig);
const googleIdentityAuth = getAuth(googleIdentityApp);

@Injectable({ providedIn: 'root' })
export class FirebaseAuthService {
  private readonly router = inject(Router);

  private readonly firebaseUserSignal = signal<User | null>(primaryAuth.currentUser);
  private readonly profileSignal = signal<BusinessUserProfile | null>(null);
  private readonly profileLoadedSignal = signal(false);
  private bootstrapPromise: Promise<void> | null = null;

  readonly firebaseUser = computed(() => this.firebaseUserSignal());
  readonly profile = computed(() => this.profileSignal());
  readonly profileLoaded = computed(() => this.profileLoadedSignal());
  readonly isAuthenticated = computed(() => !!this.firebaseUserSignal());
  readonly isBusinessAccount = computed(() => this.profileSignal()?.accountType === 'business');

  constructor() {
    this.bootstrapPromise = new Promise((resolve) => {
      onAuthStateChanged(primaryAuth, async (user) => {
        this.firebaseUserSignal.set(user);
        this.profileLoadedSignal.set(false);

        if (!user) {
          this.profileSignal.set(null);
          this.profileLoadedSignal.set(true);
          resolve();
          return;
        }

        const snapshot = await getDoc(doc(firestore, 'users', user.uid));
        const data = snapshot.data() ?? {};
        const accountType = String(data['accountType'] ?? '').trim();
        const ownedBusinessId = String(data['ownedBusinessId'] ?? '').trim();

        this.profileSignal.set({
          uid: user.uid,
          email: user.email ?? '',
          emailVerified: user.emailVerified,
          displayName: user.displayName ?? '',
          accountType:
            accountType === 'business' ? 'business' : accountType === 'user' ? 'user' : '',
          ownedBusinessId,
          businessOnboardingComplete: Boolean(data['businessOnboardingComplete']) || !!ownedBusinessId,
        });
        this.profileLoadedSignal.set(true);
        resolve();
      });
    });
  }

  async waitForBootstrap(): Promise<void> {
    await this.bootstrapPromise;
    if (!this.profileLoadedSignal()) {
      while (!this.profileLoadedSignal()) {
        await new Promise((resolve) => setTimeout(resolve, 40));
      }
    }
  }

  async login(email: string, password: string): Promise<void> {
    await signInWithEmailAndPassword(primaryAuth, email.trim(), password.trim());
    await this.waitForBootstrap();
    await this.ensureBusinessSessionOrThrow();
  }

  async authorizeGoogleBusinessIdentity(): Promise<GoogleBusinessIdentity> {
    const provider = new GoogleAuthProvider();
    provider.addScope('email');
    provider.addScope('https://www.googleapis.com/auth/business.manage');
    provider.setCustomParameters({ prompt: 'select_account' });

    const result = await signInWithPopup(googleIdentityAuth, provider);
    const credential = GoogleAuthProvider.credentialFromResult(result);
    const accessToken = credential?.accessToken ?? '';
    const email = result.user.email?.trim().toLowerCase() ?? '';

    if (!accessToken || !email) {
      throw new Error('Die Google-Business-Identität konnte nicht sauber geladen werden.');
    }

    await signOut(googleIdentityAuth).catch(() => undefined);
    return {
      email,
      accessToken,
      displayName: result.user.displayName?.trim() ?? '',
    };
  }

  async registerBusinessAccount(input: {
    email: string;
    password: string;
    businessName: string;
  }): Promise<void> {
    const email = input.email.trim().toLowerCase();
    const businessName = input.businessName.trim();
    if (!isStrongBusinessPassword(input.password)) {
      throw new Error(
        'Dein Passwort braucht mindestens 12 Zeichen sowie Groß- und Kleinbuchstaben, eine Zahl und ein Sonderzeichen.',
      );
    }

    const currentUser = primaryAuth.currentUser;
    if (currentUser?.email?.trim().toLowerCase() && currentUser.email.trim().toLowerCase() !== email) {
      await signOut(primaryAuth).catch(() => undefined);
    }

    const user =
      primaryAuth.currentUser?.email?.trim().toLowerCase() === email
        ? primaryAuth.currentUser
        : await this.createOrResumeBusinessUser(email, input.password);

    if (!user.emailVerified) {
      await sendEmailVerification(user).catch(() => undefined);
    }

    await setDoc(
      doc(firestore, 'users', user.uid),
      {
        accountType: 'business',
        name: businessName,
        handle: `@${email.split('@')[0]}`,
        city: '',
        district: '',
        avatarInitials: initialsFor(businessName),
        favoriteCategories: [],
        savedDealIds: [],
        activeDealIds: [],
        followingBusinessIds: [],
        seenStoryIds: [],
        rewards: [],
        points: 0,
        freeCouponCredits: 0,
        inviteCode: inviteCodeFor(user.uid),
        streakDays: 0,
        preferences: {
          interests: [],
          city: '',
          radiusKm: 35,
          notificationsEnabled: true,
          socialProofEnabled: true,
          openNowOnly: false,
        },
        ownedBusinessId: '',
        businessOnboardingComplete: false,
        hasLocationPermission: false,
        updatedAt: serverTimestamp(),
        createdAt: serverTimestamp(),
      },
      { merge: true },
    );

    this.firebaseUserSignal.set(user);
    this.profileSignal.set({
      uid: user.uid,
      email: user.email ?? email,
      emailVerified: user.emailVerified,
      displayName: user.displayName ?? '',
      accountType: 'business',
      ownedBusinessId: '',
      businessOnboardingComplete: false,
    });
    this.profileLoadedSignal.set(true);
  }

  async refreshEmailVerification(): Promise<void> {
    if (!primaryAuth.currentUser) {
      return;
    }
    await primaryAuth.currentUser.reload();
    this.firebaseUserSignal.set(primaryAuth.currentUser);
    const currentProfile = this.profileSignal();
    if (currentProfile) {
      this.profileSignal.set({
        ...currentProfile,
        emailVerified: primaryAuth.currentUser?.emailVerified ?? false,
      });
    }
  }

  async markBusinessOnboardingComplete(businessId: string): Promise<void> {
    const normalizedBusinessId = String(businessId || '').trim();
    if (!normalizedBusinessId) {
      throw new Error('Das Studio konnte keine gültige Business-ID übernehmen. Bitte öffne die Freischaltung erneut.');
    }

    const user = primaryAuth.currentUser;
    if (!user) {
      throw new Error('Keine aktive Business-Session vorhanden.');
    }

    await setDoc(
      doc(firestore, 'users', user.uid),
      {
        accountType: 'business',
        ownedBusinessId: normalizedBusinessId,
        businessOnboardingComplete: true,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );

    const profile = this.profileSignal();
    if (profile) {
      this.profileSignal.set({
        ...profile,
        ownedBusinessId: normalizedBusinessId,
        businessOnboardingComplete: true,
      });
    }
  }

  async sendPasswordReset(email: string): Promise<void> {
    await sendPasswordResetEmail(primaryAuth, email.trim());
  }

  async logout(): Promise<void> {
    await signOut(primaryAuth);
    await this.router.navigateByUrl('/business-register');
  }

  async forceBusinessIsolation(): Promise<void> {
    if (!primaryAuth.currentUser) {
      return;
    }
    await signOut(primaryAuth).catch(() => undefined);
  }

  async getIdToken(forceRefresh = false): Promise<string> {
    const currentUser = primaryAuth.currentUser;
    if (!currentUser) {
      return '';
    }
    return currentUser.getIdToken(forceRefresh);
  }

  get currentUser(): User | null {
    return primaryAuth.currentUser;
  }

  get firestoreInstance() {
    return firestore;
  }

  private async ensureBusinessSessionOrThrow(): Promise<void> {
    const profile = this.profileSignal();
    if (profile?.accountType === 'business') {
      return;
    }

    await this.forceBusinessIsolation();
    throw new Error('Dieses Konto gehört nicht zum Business Studio. Nutze bitte einen Business-Zugang.');
  }

  private async createOrResumeBusinessUser(email: string, password: string): Promise<User> {
    try {
      const credential = await createUserWithEmailAndPassword(primaryAuth, email, password);
      return credential.user;
    } catch (error) {
      if (!isFirebaseAuthCode(error, 'auth/email-already-in-use')) {
        throw error;
      }

      const credential = await signInWithEmailAndPassword(primaryAuth, email, password);
      return credential.user;
    }
  }
}

function isFirebaseAuthCode(error: unknown, code: string): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    String((error as { code?: unknown }).code) === code
  );
}

function ensureSecondaryApp(config: FirebaseOptions): FirebaseApp {
  return initializeApp(config, 'business-google-identity');
}

function initialsFor(value: string): string {
  return value
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join('');
}

function inviteCodeFor(uid: string): string {
  const suffix = uid.replace(/[^A-Za-z0-9]/g, '').slice(0, 6).toUpperCase();
  return `SPAR-${suffix.padEnd(6, 'X')}`;
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
