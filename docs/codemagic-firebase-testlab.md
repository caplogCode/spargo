# Codemagic + Firebase Test Lab

Dieses Projekt ist fuer Codemagic so vorbereitet, dass jeder Push auf `main`
Android und iOS in Firebase Test Lab ausfuehrt und danach Tester-Artefakte per
Codemagic-Mail an die hinterlegten Tester verschickt.

## GitHub

Codemagic kann erst laufen, wenn das Projekt als GitHub-Repository verbunden ist.
Der Root dieses Projekts enthaelt dafuer `codemagic.yaml`.

Lokales Git ist bereits auf `main` vorbereitet. Sobald ein GitHub-Repository
existiert:

```powershell
git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin main
```

Zusaetzlich existiert eine GitHub-Actions-Absicherung unter
`.github/workflows/mobile-distribution.yml`. Diese baut bei jedem Push auf
`main` und per manuellem Button eine Android-APK. Mit
`FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` verteilt GitHub Actions die Android-APK
direkt an die Tester ueber Firebase App Distribution.

Eine installierbare iOS-IPA wird dort gebaut und verteilt, sobald folgende
GitHub-Secrets gesetzt sind:

- `IOS_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `KEYCHAIN_PASSWORD`
- `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64`
- `FIREBASE_IOS_APP_ID`

Ohne Apple-Signing-Secrets kann iOS nur als unsigned Diagnose-Build gebaut
werden; installierbare IPA-Auslieferung braucht immer Apple-Signing.

## Codemagic Environment Groups

Lege in Codemagic zwei Environment Groups an.

### `firebase-test-lab`

- `FIREBASE_PROJECT_ID`: Firebase-Projekt-ID, aktuell `spargo-app`
- `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64`: Base64-codierte Service-Account-JSON
- optional `FIREBASE_TESTLAB_RESULTS_BUCKET`: eigener Test-Lab-Result-Bucket

Der Service Account braucht mindestens Firebase Test Lab Admin und Zugriff auf
Cloud Storage Test-Ergebnis-Buckets.

### `ios-signing`

- Codemagic Apple Developer Portal Integration aktivieren
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_IDENTIFIER`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- optional `IOS_EXPORT_METHOD`: Standard ist `ad-hoc`

Der Workflow nutzt `app-store-connect fetch-signing-files` fuer ein
iOS-Development-Profil, weil Firebase Test Lab echte iPhones ausfuehrt.
Fuer eine installierbare Tester-IPA wird zusaetzlich ein IPA-Artefakt gebaut.
Bei `ad-hoc` nutzt Codemagic `IOS_APP_ADHOC`; die Testgeraete muessen dafuer im
Apple Developer Account registriert sein. Fuer TestFlight/App-Store-Connect kann
`IOS_EXPORT_METHOD` auf `app-store` gesetzt werden, dann wird `IOS_APP_STORE`
genutzt.

## Workflow

Workflow-Name: `firebase-test-lab-release`

Ausloeser:

- Push auf `main`

Was passiert:

1. Flutter Packages installieren
2. Firebase Service Account fuer `gcloud` aktivieren
3. Flutter Tests + Analyzer
4. Android Debug-App + AndroidTest bauen
5. Android Firebase Test Lab ausfuehren
6. iOS Signing vorbereiten
7. iOS XCTest-ZIP fuer Firebase Test Lab bauen
8. iPhone Firebase Test Lab ausfuehren
9. Android Release-APK fuer Tester bauen
10. iOS IPA fuer Tester bauen
11. APK/IPA per Codemagic-Artefakt-Mail an die Tester schicken

Tester-Mailadressen:

- `markuskara25@gmail.com`
- `benny_g_@outlook.com`
- `suekrue.goektas@outlook.com`

Der lokale CI-Gate fuehrt bewusst `test/widget_test.dart` aus. Die vorhandenen
alten Responsive-Tests starten Firebase-abhaengige Screens ohne Bootstrap und
sind deshalb nicht Teil des Release-Triggers. Der echte App-Start wird ueber
`integration_test/app_smoke_test.dart` in Firebase Test Lab geprueft.
