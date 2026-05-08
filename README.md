# Spargo

Spargo ist ein Flutter-MVP fuer eine lokale Coupon- und Discovery-App mit social-first Feed, Stories, Nearby-Logik, Wallet und integriertem Business-Modus.

## Produktbild

- Feed statt Gutschein-Katalog
- lokale Deals fuer junge, lifestyle-orientierte Nutzer
- Stories, Trends, Nearby und Wallet in einem Produkt
- Business-Bereich fuer Restaurants, Cafes, Beauty und lokale Shops
- coupon-first statt Rabatt-Wuehltisch

## Experience

- Home als Social Feed mit Stories, Hero-Deals, Tagesaktionen und dauerhaften Coupons
- Discover fuer Nearby-Deals und lokale Orientierung
- Saved fuer gemerkte Angebote
- Wallet fuer aktive Gutscheine, Codes und QR-Nutzung
- Profil fuer Verlauf, Einstellungen und Business-Wechsel

## Business-Modus

- Deals posten
- Stories posten
- Gutscheine pausieren oder live schalten
- einfache Insights fuer Views, Saves, Aktivierungen und Einloesungen

## Architektur

- `flutter_riverpod` fuer leichtgewichtiges, sauberes State Management
- feature-orientierte Struktur mit separatem Theme-, Routing-, Model- und Data-Layer
- Mock-Repositories und Mock-Daten als spaeter austauschbare Backend-Schnittstelle
- wiederverwendbare UI-Komponenten fuer Feed, Wallet, Discover und Business

## Designrichtung

- premium local discovery
- coupon-first, klarer und ruhiger statt ueberladen
- Urbanist als Schriftfamilie
- dunkles Ink, weiches Off-White und rubinfarbene Highlights
- SetOff-inspirierte Richtung als visuelle Referenz, aber keine 1:1-Kopie

## Projektstruktur

```text
lib/
  app.dart
  main.dart
  core/
    constants/
    extensions/
    utils/
    widgets/
  theme/
  routing/
  domain/models/
  data/
    mock/
    repositories/
  shared/
    providers/
    widgets/
  features/
    app_shell/
    auth/
    onboarding/
    home/
    stories/
    search/
    discover/
    deals/
    business/
    saved/
    wallet/
    notifications/
    profile/
```

## Aktueller Scope

- Splash, Welcome, Standort-Freigabe, Login und Registrierung
- Registrierung mit Wahl zwischen Nutzer- und Unternehmenspfad
- Social Feed mit Stories, Sticky Filter, Hero Deal, Flash Deals und Coupon Feed
- Discover mit Nearby-Fokus und Map/List-Umschaltung
- Deal Detail mit Hero, Sticky CTA und Business-Infos
- Saved, Wallet, Notifications, Profil und Settings
- Business Dashboard, Deal-Verwaltung, Story-Erstellung und Analytics-Mocks

## Monetarisierungsideen

- Free Tier mit limitierter Coupon-Nutzung
- Mini-Abo fuer Premium-Nutzer
- Business-Upsells fuer Reichweite und Hervorhebung

## Launch-Logik

- zuerst eine Stadt
- lokales Angebotsnetz dicht machen
- Nutzer und Haendler parallel onboarden
- danach Stadt fuer Stadt erweitern

## Setup

```bash
flutter pub get
flutter analyze
flutter test
```

## Verifiziert

- `flutter analyze`
- `flutter test test\responsive_layout_test.dart`

## Naechste Schritte

1. Backend anbinden:
   Repository-Layer an echte APIs haengen, DTOs und Caching ergaenzen.
2. Auth:
   Firebase Auth, Supabase Auth oder eigenes OAuth-Backend integrieren.
3. Karten:
   echte Map-Integration mit Marker-Clustering, Geoqueries und Deeplinks.
4. Push:
   Benachrichtigungen fuer gespeicherte Deals, ablaufende Gutscheine und neue Merchant-Posts.
5. Wallet und QR:
   Offline-Speicherung, Coupon-ID, Redemption-Validierung und Missbrauchsschutz.
6. Reviews und Social:
   Bewertungen, Freundes-Empfehlungen, Sharing und Merchant-Follows vertiefen.
