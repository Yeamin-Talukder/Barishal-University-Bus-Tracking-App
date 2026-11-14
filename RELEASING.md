# Releasing the Android app

GitHub Actions does it: `.github/workflows/android.yml`.

| You push | What happens |
|---|---|
| Any branch, or a pull request to `main` | `flutter analyze` and every test. |
| `main`, version unchanged | The same checks. No release. |
| `main`, **new version** in `pubspec.yaml` | Checks, then both APKs are built and signed, GitHub release `v<version>` is published with checksums and notes, and the website's download section is refreshed. |

The app's own updater (Profile → App updates) and the website both read
GitHub releases, so a published release reaches phones by itself.

## Releasing a new version

1. Raise the version in `pubspec.yaml`. Both parts go up:

   ```yaml
   version: 1.1.0+2   # was 1.0.0+1
   ```

   The part before `+` is what people see (`v1.1.0`). The build number
   after it must be higher than the last release's, or phones refuse the
   update. The workflow stops with a message if either is not higher.

2. Optional: write what's new for passengers in
   `release-notes/v1.1.0.md`. Without it, the notes list the commit
   messages since the last release (website commits left out). The app
   shows these notes under "What's new" when it offers the update.

3. Commit and push to `main`. Follow it under the repository's **Actions**
   tab; the release appears under **Releases** about 15 minutes later.

To release again without new commits (after adding a missing secret, for
example), use **Actions → Android app → Run workflow** on `main`.

## One-time setup: secrets

Settings → Secrets and variables → Actions → New repository secret.

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The signing key, base64. |
| `GOOGLE_SERVICES_JSON` | `android/app/google-services.json`, base64. It is not in git. |
| `FIREBASE_OPTIONS_DART` | The real `lib/firebase_options.dart`, base64. Git holds only a placeholder; an app built with it has no tracking backend. |

Without them the workflow still checks and tests (against the placeholder
Firebase options, as anyone cloning the repository would), but refuses to
release.

**The signing key must stay the same for every release.** Android only
installs an update signed with the same key as the installed app, and
Google sign-in is tied to the key's SHA fingerprint in Firebase. Releases
so far are signed with the project owner's Android debug key
(`%USERPROFILE%\.android\debug.keystore`), so that is the key to upload.
Its passwords are Android's defaults, which the workflow uses when the
optional secrets below are not set.

The values can be set from a terminal with the GitHub CLI, on the computer
that has the key (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.android\debug.keystore")) | gh secret set ANDROID_KEYSTORE_BASE64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\google-services.json")) | gh secret set GOOGLE_SERVICES_JSON
[Convert]::ToBase64String([IO.File]::ReadAllBytes("lib\firebase_options.dart")) | gh secret set FIREBASE_OPTIONS_DART
```

Keep a backup of the key file somewhere safe: if it is lost, no update can
ever be installed over the current app again.

### Moving to a real release key later

Create a new key, upload it as `ANDROID_KEYSTORE_BASE64`, and set
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.
Add the new key's SHA-1 and SHA-256 to the Android app in Firebase
(`firebase apps:android:sha:create`) or Google sign-in stops working.
Everyone must then uninstall the old app once, since its key differs; say
so in that release's notes.

## Building by hand

`flutter build apk --release --split-per-abi` still works on a developer's
machine and signs with that machine's debug key. To sign the way the
workflow does, set `ANDROID_KEYSTORE_PATH` (and the passwords, if not
Android's defaults) first.
