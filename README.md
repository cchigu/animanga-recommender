# Animanga Recommender

One big button, one pick. Tap, watch the 5-4-3-2-1 countdown, and get a single anime or manga recommendation drawn from your MyAnimeList data. The background shifts to match the title's colors.

## First-time setup (Windows, VS Code)

```powershell
git clone https://github.com/cchigu/animanga-recommender.git
cd animanga-recommender
flutter create --project-name animanga_recommender --org com.cchigu --platforms android .
copy lib\secrets.example.dart lib\secrets.dart
flutter pub get
flutter run
```

Then open `lib/secrets.dart` and paste your MAL Client ID (from https://myanimelist.net/apiconfig). That file is git-ignored, so it never reaches GitHub.

`flutter create .` only generates the missing `android/` folder and leaves the files in `lib/` alone. You only run it once.

After that, updating is just:

```powershell
git pull
flutter pub get
flutter run
```

## App name and icon (once)

```powershell
dart run flutter_launcher_icons
(Get-Content android\app\src\main\AndroidManifest.xml) -replace 'android:label="[^"]*"', 'android:label="Animanga Recommender"' | Set-Content android\app\src\main\AndroidManifest.xml
```

## Milestones

1. **Project + home screen** — Tap here circle, countdown, demo reveal, settings shell ✅
2. **MAL connection** — username, profile picture top right, fetch and cache your lists ✅
3. **Catalog** — candidate titles from MAL + AniList (country of origin, cover color) ✅
4. **Settings** — all recommendation settings, saved on the phone ✅
5. **Picker engine** — exclusions, Plan to Watch/Read, best score / weighted (score − 5)⁴ / random, format filters ✅
6. **Franchise logic** — strict "completed" chain check and first major entry ✅
7. **Reveal polish** — cover art, background from cover color, details, Open on MAL ✅
8. **Final polish** — app icon, loading and error states
