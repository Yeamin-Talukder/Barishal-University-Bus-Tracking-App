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
- **Features:** twelve cards, each marked *Available* or *In testing*.
- **How live tracking works**, in three steps, followed by **"See it working
  in half a minute"**: how to run the app's own test buses (Profile → Test
  the system).
- **Screens:** seven real screenshots of the current app, not mock-ups. The
  first one shows a bus being tracked; its buses are the app's test buses,
  and both the page and the screenshot say so.
- **Roadmap:** ready, in progress, next, later.
- **Hero download group:** the download button for the latest version, a
  dropdown of its builds (64-bit recommended, 32-bit for older phones), and
  a QR button that opens a "Scan to install" card for the chosen build.
- **Download:** version and build dropdowns covering every release on
  GitHub, the chosen build's date, size, download count and SHA-256, a card
  for every build of that version (each with Download and QR buttons), a
  QR panel that follows the choice, and how to install an APK, including
  the note that early-access builds are signed with a development key. The
  iPhone card says it is planned. Builds are recognised by their file name
  (`arm64`, `armv7`/`armeabi`, `universal`, `x86_64`), so name release APKs
  that way. QR codes carry the app icon in the middle (error correction Q)
  and were checked to decode to the APK link.
- **Download bar on phones:** once the visitor has scrolled past the first
  screen, a small bar with the version, size and a Download button stays at
  the bottom. It hides over the download section and the footer.
- **Open source:** GitHub stars, downloads, forks and latest version.
- **FAQ** in English and Bangla.

Nothing on the page is invented: download numbers, stars and versions come
from GitHub, and until the repository and a release exist the page says
"coming soon" instead of showing made-up numbers.

### Where the download details come from

1. The visitor's browser asks GitHub directly and keeps the answer for ten
   minutes. The line under the numbers then says "Live from GitHub."
2. GitHub answers only 60 such questions an hour from one network, and a
   campus network shared by many students can use those up. So `build.py`
   also asks GitHub when the site is built and saves the answer as
   `public/release.json`. The page shows that copy at once and replaces it
   with GitHub's live answer when that arrives. If GitHub does not answer,
   the copy stays and the line says "Figures saved on <date>."
3. With neither, the card says GitHub could not be reached and its button
   leads to the releases page.

The deploy workflow rebuilds the site every six hours so the saved copy
picks up new releases and download counts. When building on your own
computer, the copy is skipped if GitHub cannot be reached (the build says
so) and everything else still works.

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
counts the downloads itself. For visitors who are shown the saved copy, the
new version appears after the next rebuild: within six hours, or straight
away if you run the **Website** workflow by hand from the **Actions** tab.

If a release has more than one APK, the page offers the `arm64` one and
links the others underneath. Releases should be signed with a proper release
key first; see DEVELOPMENT.md.

## Updating the pictures

After the app changes, from the project root:

1. Build and serve the app's web version (`flutter build web`, then the
   `app-web-shots` preview on port 5601).
2. `node website/tools/capture_screens.mjs http://localhost:5601 website/src/assets/screens`
   takes the seven phone screenshots. The tap positions are in the script;
   if a screen's layout changes, its taps need checking. Add a name at the
   end to retake one, e.g. `... website/src/assets/screens tracking`. The
   `tracking` and `test-mode` shots start the app's test buses themselves.
3. `python website/tools/make_images.py` remakes the favicons and the link
   preview image from the app icon.

## Checking the layout

```bash
node website/tools/shoot_site.mjs http://localhost:5700/ build/site-shots phone-dark
```

saves the page in screen-height slices and prints the page height, any
sideways overflow and any script errors. The views are `phone-dark`,
`phone-light`, `desktop-dark` and `desktop-light`; leave the name out for
all four. Both tools start their own headless Edge, close it when they
finish, and give up rather than wait for ever if it stops answering.

## Search engines (SEO)

Google Search Console ownership is proved by
`src/google37d6bfa5bc028c76.html`, copied unchanged from the file Google
gave. Keep it: removing it un-verifies the site.

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
