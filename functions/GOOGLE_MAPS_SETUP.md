# Google Maps Server Setup

Die Flutter-App nutzt fuer Places, Geocoding und Place-Fotos jetzt Firebase Functions als Proxy.
Der Google-Server-Key liegt deshalb nicht mehr im App-Code, sondern als Firebase Secret.

## Benoetigte Google APIs

- `Geocoding API`
- `Places API`

## Secret setzen

```powershell
firebase functions:secrets:set GOOGLE_MAPS_SERVER_API_KEY
```

Oder ohne Prompt aus einer Datei:

```powershell
firebase functions:secrets:set GOOGLE_MAPS_SERVER_API_KEY --data-file path\to\google-maps-server-key.txt
```

## Functions deployen

```powershell
firebase deploy --only functions
```

## Was jetzt serverseitig laeuft

- `googleMapsAddressSuggestions`
- `googleMapsResolveLocation`
- `googleMapsNearbyPlaces`
- `googleMapsPlacePhoto`
