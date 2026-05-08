# Codemagic + Firebase Test Lab

Dieses Projekt ist fuer Codemagic so vorbereitet, dass jeder Push auf `main`
Android und iOS in Firebase Test Lab ausfuehrt.

## GitHub

Codemagic kann erst laufen, wenn das Projekt als GitHub-Repository verbunden ist.
Der Root dieses Projekts enthaelt dafuer `codemagic.yaml`.

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

Der Workflow nutzt `app-store-connect fetch-signing-files` fuer ein
iOS-Development-Profil, weil Firebase Test Lab echte iPhones ausfuehrt.

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

Der lokale CI-Gate fuehrt bewusst `test/widget_test.dart` aus. Die vorhandenen
alten Responsive-Tests starten Firebase-abhaengige Screens ohne Bootstrap und
sind deshalb nicht Teil des Release-Triggers. Der echte App-Start wird ueber
`integration_test/app_smoke_test.dart` in Firebase Test Lab geprueft.
