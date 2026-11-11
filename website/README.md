# BU Bus Tracker website

The marketing and download site for the app: one fast, static page with no
framework, in dark and light themes, built for phones first.

```
website/
  site.config.json     your site address and GitHub repository
  build.py             builds src/ into public/ with those values filled in
  src/                 the site: index.html, 404.html, css/, js/, assets/
  public/              the built site (generated, not committed)
  tools/
    capture_screens.mjs  real app screenshots from the web build
    make_images.py       favicons, app icons and the link preview image
    og-image.html        layout of the link preview image
    shoot_site.mjs       screenshots of the website itself, for checking
```

## What is on the page

- **Hero** that fills the first screen, with an animated route map, the real
  app on a phone, and download and GitHub buttons.
- **Facts** from the app's data: 11 timetables, 101 departures, 3 passenger
  groups, a 2 MB offline map.
- **Features**, each marked *Available* or *Coming soon*.
- **How live tracking works**, in three steps.
- **Screens:** real screenshots of the current app, not mock-ups.
- **Roadmap:** ready, in progress, next, later.
- **Download:** Android version, release date, size, download count, SHA-256
  checksum, a QR code for desktop visitors, and how to install an APK. The
  iPhone card says it is planned.
- **Open source:** GitHub stars, downloads, forks and latest version.
- **FAQ** in English and Bangla.

Nothing on the page is invented: download numbers, stars and versions come
live from GitHub, and until the repository and a release exist the page says
"coming soon" instead of showing made-up numbers.

## Preview locally

```bash
python website/build.py
```

```bash
python -m http.server 5700 --directory website/public
```

Then open <http://localhost:5700>. In Claude Code the preview is also
available as the `website` entry in `.claude/launch.json`.

## Before publishing

Edit `website/site.config.json`:

| Key | What to put |
|---|---|
| `siteUrl` | The address the site will have, ending in `/`. For GitHub Pages: `https://<user>.github.io/<repo>/`, or your own domain. Used for the canonical link, link previews, `sitemap.xml` and `robots.txt`. |
| `githubOwner` | Your GitHub user or organisation name. |
| `githubRepo` | The repository name. |
| `apkNamePattern` | Optional. Which APK to offer if a release has several, as a regular expression such as `arm64`. Default: a `universal` APK, then `arm64`, then the first `.apk`. |

Run `python website/build.py` again after any change.

## Publishing with GitHub Pages

1. Push the project to GitHub (the workflow is in
   `.github/workflows/website.yml`).
2. On GitHub: **Settings → Pages → Build and deployment → Source: GitHub
   Actions**.
3. Push a change under `website/`, or run the **Website** workflow by hand
   from the **Actions** tab. The site is built and published; the address is
   shown on the workflow run.

## Releasing a new app version

The download area reads GitHub Releases, so a new version needs no website
change:

1. Build the APK, e.g.
   `flutter build apk --release --split-per-abi --target-platform android-arm64`
   (needs JDK 21+, see DEVELOPMENT.md), or a universal APK without
   `--split-per-abi`.
2. Rename it clearly, e.g. `bu-bus-tracker-v1.0.0-arm64.apk`.
3. On GitHub: **Releases → Draft a new release**, tag it (e.g. `v1.0.0`),
   write what changed, attach the APK and publish.

Within about ten minutes (the page caches GitHub's answer per visitor) the
site shows the new version, date, size, checksum and download count. GitHub
counts the downloads itself. Releases should be signed with a proper release
key first; see DEVELOPMENT.md.

## Updating the pictures

After the app changes, from the project root:

1. Build and serve the app's web version (`flutter build web`, then the
   `app-web-shots` preview on port 5601).
2. `node website/tools/capture_screens.mjs http://localhost:5601 website/src/assets/screens`
   takes the five phone screenshots. The tap positions for the tabs are in the
   script.
3. `python website/tools/make_images.py` remakes the favicons and the link
   preview image from the app icon.

## Search engines (SEO)

Already in the page:

- A title and description written for searches like "University of Barishal
  bus schedule", plus Bangla text on the page for Bangla searches.
- Structured data (JSON-LD) describing the website, the app (free, Android
  7.0+) and the FAQ, which lets Google show the questions in results.
- Open Graph and Twitter tags with a 1200 × 630 preview image, so links look
  good on Facebook, Messenger and WhatsApp.
- `sitemap.xml`, `robots.txt`, a canonical link, a web app manifest, icons,
  one `h1`, descriptive alt text on every image, and a fast page: no
  framework, about 300 KB of screenshots, all below the first screen loaded
  lazily.

After the site is live:

1. Add it to [Google Search Console](https://search.google.com/search-console)
   and [Bing Webmaster Tools](https://www.bing.com/webmasters), and submit
   `sitemap.xml` in both. This is the single most useful step.
2. Check the structured data with Google's
   [Rich Results Test](https://search.google.com/test/rich-results).
3. Share the link where students already are (department and batch groups,
   the university's pages). Links from other sites are what search engines
   trust most.
