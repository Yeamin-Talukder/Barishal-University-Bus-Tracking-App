/* BU Bus Tracker website: theme, navigation, animations, and live release
   information from GitHub. No framework; runs after the page is parsed. */
(function () {
  'use strict';

  var root = document.documentElement;
  var CFG = window.BUBT_CONFIG || {};
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function $(sel, ctx) { return (ctx || document).querySelector(sel); }
  function $$(sel, ctx) { return Array.prototype.slice.call((ctx || document).querySelectorAll(sel)); }
  function store(key, value) {
    try {
      if (value === undefined) return localStorage.getItem(key);
      localStorage.setItem(key, value);
    } catch (e) { return null; }
  }

  root.classList.remove('no-js');
  $$('[data-year]').forEach(function (el) { el.textContent = String(new Date().getFullYear()); });

  /* ---------- Theme ---------- */

  var toggle = $('.theme-toggle');
  function applyTheme(theme) {
    root.setAttribute('data-theme', theme);
    if (toggle) toggle.setAttribute('aria-label', theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
    $$('img[data-src-dark]').forEach(function (img) {
      var src = img.getAttribute(theme === 'dark' ? 'data-src-dark' : 'data-src-light');
      if (src && img.getAttribute('src') !== src) img.setAttribute('src', src);
    });
  }
  applyTheme(root.getAttribute('data-theme') || 'dark');
  if (toggle) {
    toggle.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      store('bubt-theme', next);
      applyTheme(next);
    });
  }
  // Follow the system setting until the visitor picks a theme here.
  var systemLight = window.matchMedia('(prefers-color-scheme: light)');
  var onSystemChange = function (e) { if (!store('bubt-theme')) applyTheme(e.matches ? 'light' : 'dark'); };
  if (systemLight.addEventListener) systemLight.addEventListener('change', onSystemChange);

  /* ---------- Header and menu ---------- */

  var header = $('.site-header');
  function onScroll() { header.classList.toggle('scrolled', window.scrollY > 8); }
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  var menuBtn = $('.menu-toggle');
  function setMenu(open) {
    document.body.classList.toggle('menu-open', open);
    menuBtn.setAttribute('aria-expanded', String(open));
    menuBtn.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
  }
  menuBtn.addEventListener('click', function () { setMenu(!document.body.classList.contains('menu-open')); });
  $$('#site-nav a').forEach(function (a) { a.addEventListener('click', function () { setMenu(false); }); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') setMenu(false); });

  // Highlight the menu link of the section in view.
  var links = {};
  $$('#site-nav a[href^="#"]').forEach(function (a) { links[a.getAttribute('href').slice(1)] = a; });
  if ('IntersectionObserver' in window) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var link = links[entry.target.id];
        if (!link) return;
        if (entry.isIntersecting) {
          Object.keys(links).forEach(function (k) { links[k].classList.remove('active'); });
          link.classList.add('active');
        }
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    Object.keys(links).forEach(function (id) { var s = document.getElementById(id); if (s) spy.observe(s); });
  }

  /* ---------- Reveal on scroll and counters ---------- */

  function countUp(el) {
    var target = parseInt(el.getAttribute('data-count'), 10);
    if (isNaN(target) || reduceMotion) { el.textContent = String(target); return; }
    var start = null, duration = 1200, done = false;
    function frame(t) {
      if (done) return;
      if (start === null) start = t;
      var p = Math.min((t - start) / duration, 1);
      el.textContent = String(Math.round(target * (1 - Math.pow(1 - p, 3))));
      if (p < 1) requestAnimationFrame(frame);
      else done = true;
    }
    requestAnimationFrame(frame);
    // Browsers pause animation frames in background tabs; never leave a
    // half-counted number behind.
    setTimeout(function () { done = true; el.textContent = String(target); }, duration + 200);
  }

  var revealEls = $$('.reveal');
  if ('IntersectionObserver' in window && !reduceMotion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('in');
        $$('[data-count]', entry.target).forEach(countUp);
        io.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('in'); });
  }

  if (reduceMotion) {
    var heroMap = $('.hero-map');
    if (heroMap && heroMap.pauseAnimations) heroMap.pauseAnimations();
  }

  /* ---------- Feature cards follow the pointer ---------- */

  $$('.feature').forEach(function (card) {
    card.addEventListener('pointermove', function (e) {
      var r = card.getBoundingClientRect();
      card.style.setProperty('--mx', (e.clientX - r.left) + 'px');
      card.style.setProperty('--my', (e.clientY - r.top) + 'px');
    });
  });

  /* ---------- Screenshot gallery ---------- */

  var gallery = $('.gallery');
  function step(dir) {
    var shot = $('.shot', gallery);
    var by = shot ? shot.getBoundingClientRect().width + 28 : 280;
    gallery.scrollBy({ left: dir * by, behavior: reduceMotion ? 'auto' : 'smooth' });
  }
  $('.gallery-nav.prev').addEventListener('click', function () { step(-1); });
  $('.gallery-nav.next').addEventListener('click', function () { step(1); });

  /* ---------- FAQ: smooth open and close, one answer at a time ---------- */

  var EASE = 'cubic-bezier(.2, .8, .2, 1)';
  // Each animation also has a timer that settles the final state, because
  // browsers pause animations in background tabs.
  function openFaq(item) {
    var body = $('.faq-a', item);
    item.open = true;
    if (reduceMotion || !body.animate) return;
    var anim = body.animate([{ height: '0px' }, { height: body.scrollHeight + 'px' }], { duration: 420, easing: EASE });
    setTimeout(function () { anim.cancel(); }, 480);
  }
  function closeFaq(item) {
    var body = $('.faq-a', item);
    if (reduceMotion || !body.animate) { item.open = false; return; }
    item.classList.add('closing');
    var anim = body.animate(
      [{ height: body.scrollHeight + 'px', opacity: 1 }, { height: '0px', opacity: 0 }],
      { duration: 320, easing: EASE, fill: 'forwards' }
    );
    var settled = false;
    function settle() {
      if (settled) return;
      settled = true;
      item.open = false;
      item.classList.remove('closing');
      anim.cancel();
    }
    anim.onfinish = settle;
    setTimeout(settle, 380);
  }
  $$('.faq-item').forEach(function (item) {
    $('summary', item).addEventListener('click', function (e) {
      e.preventDefault();
      if (item.classList.contains('closing')) return;
      if (item.open) { closeFaq(item); return; }
      $$('.faq-item[open]').forEach(function (other) { if (other !== item) closeFaq(other); });
      openFaq(item);
    });
  });

  /* ---------- GitHub: links, release and statistics ---------- */

  var owner = (CFG.githubOwner || '').trim();
  var repo = (CFG.githubRepo || '').trim();
  var configured = Boolean(owner && repo);
  var repoUrl = configured ? 'https://github.com/' + owner + '/' + repo : '';
  var ghUrls = {
    repo: repoUrl,
    releases: repoUrl && repoUrl + '/releases',
    'new-issue': repoUrl && repoUrl + '/issues/new'
  };

  function enableLink(el, href, external) {
    el.setAttribute('href', href);
    el.removeAttribute('aria-disabled');
    el.removeAttribute('title');
    if (external) { el.setAttribute('target', '_blank'); el.setAttribute('rel', 'noopener'); }
  }
  function disableLink(el, why) {
    el.setAttribute('aria-disabled', 'true');
    if (why) el.setAttribute('title', why);
  }

  $$('[data-gh-link]').forEach(function (el) {
    var href = ghUrls[el.getAttribute('data-gh-link')];
    if (href) enableLink(el, href, true);
    else el.setAttribute('title', 'Coming soon: the project is not on GitHub yet');
  });
  if (configured) {
    var ghText = $('[data-gh-text]');
    if (ghText) ghText.textContent = 'The source code is on GitHub. Follow the work, report problems and suggest ideas.';
  }

  var card = $('.dl-card.android');
  function setRelease(field, value) {
    $$('[data-release="' + field + '"]', card).forEach(function (el) { el.textContent = value; });
  }
  function setGh(field, value) {
    $$('[data-gh="' + field + '"]').forEach(function (el) { el.textContent = value; });
  }
  function setTag(text, cls) {
    var tag = $('[data-release-tag]', card);
    tag.textContent = text;
    tag.className = 'tag' + (cls ? ' ' + cls : '');
  }
  var apkBtn = $('[data-release-link="apk"]', card);
  var notesBtn = $('[data-release-link="notes"]', card);

  function formatDate(iso) {
    try {
      return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    } catch (e) { return iso.slice(0, 10); }
  }
  function formatSize(bytes) {
    return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(bytes / 1024)) + ' KB';
  }
  function formatCount(n) { return Number(n).toLocaleString('en-US'); }

  function pickApk(assets) {
    var apks = assets.filter(function (a) { return /\.apk$/i.test(a.name); });
    if (CFG.apkNamePattern) {
      try {
        var re = new RegExp(CFG.apkNamePattern, 'i');
        var m = apks.filter(function (a) { return re.test(a.name); })[0];
        if (m) return m;
      } catch (e) { /* bad pattern: fall through */ }
    }
    return apks.filter(function (a) { return /universal/i.test(a.name); })[0] ||
      apks.filter(function (a) { return /arm64/i.test(a.name); })[0] ||
      apks[0] || null;
  }

  function drawQr(text) {
    var box = $('[data-qr]', card);
    if (!box || !text || !window.matchMedia('(min-width: 601px)').matches) return;
    function draw() {
      if (!window.qrcode) return;
      var qr = window.qrcode(0, 'M');
      qr.addData(text);
      qr.make();
      var n = qr.getModuleCount();
      var canvas = $('canvas', box);
      var scale = Math.floor(canvas.width / n) || 1;
      var offset = Math.floor((canvas.width - n * scale) / 2);
      var ctx = canvas.getContext('2d');
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = '#0B1115';
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          if (qr.isDark(r, c)) ctx.fillRect(offset + c * scale, offset + r * scale, scale, scale);
        }
      }
      box.hidden = false;
    }
    if (window.qrcode) draw();
    else window.addEventListener('load', draw);
  }

  function showNoRelease(message) {
    card.setAttribute('data-release-state', 'none');
    setTag('Coming soon', 'soon');
    setRelease('status', message);
    disableLink(apkBtn, 'No release yet');
    disableLink(notesBtn, 'No release yet');
    var all = $('.all-releases', card);
    if (!configured) disableLink(all, 'Coming soon');
  }

  function showRelease(release, totalDownloads) {
    var apk = pickApk(release.assets || []);
    card.setAttribute('data-release-state', 'ready');
    setTag(release.prerelease ? 'Pre-release' : 'Latest', release.prerelease ? 'soon' : 'ok');
    setRelease('version', release.tag_name || release.name || '—');
    setRelease('date', release.published_at ? formatDate(release.published_at) : '—');
    setRelease('downloads', formatCount(totalDownloads));
    enableLink(notesBtn, release.html_url, true);
    if (apk) {
      setRelease('size', formatSize(apk.size));
      setRelease('status', 'Download the APK below, or scan the code with your phone.');
      enableLink(apkBtn, apk.browser_download_url, false);
      $('span', apkBtn).textContent = 'Download APK (' + formatSize(apk.size) + ')';
      if (apk.digest && /^sha256:/.test(apk.digest)) {
        setRelease('sha', apk.digest.slice(7));
        $('[data-release="sha-wrap"]', card).hidden = false;
      }
      drawQr(apk.browser_download_url);
    } else {
      setRelease('size', '—');
      setRelease('status', 'This version has no APK attached. See the release page for its files.');
      enableLink(apkBtn, release.html_url, true);
    }
  }

  function getJson(url) {
    return fetch(url, { headers: { Accept: 'application/vnd.github+json' } }).then(function (res) {
      if (res.status === 404) return null;
      if (!res.ok) throw new Error('GitHub answered ' + res.status);
      return res.json();
    });
  }

  function render(data) {
    var releases = (data.releases || []).filter(function (r) { return !r.draft; });
    var total = 0;
    releases.forEach(function (r) {
      (r.assets || []).forEach(function (a) { if (/\.apk$/i.test(a.name)) total += a.download_count || 0; });
    });
    if (data.repo) {
      setGh('stars', formatCount(data.repo.stargazers_count));
      setGh('forks', formatCount(data.repo.forks_count));
    }
    var latest = releases.filter(function (r) { return !r.prerelease; })[0] || releases[0];
    if (latest) {
      setGh('downloads', formatCount(total));
      setGh('version', latest.tag_name || '—');
      setGh('note', 'Live from GitHub.');
      showRelease(latest, total);
    } else {
      setGh('note', data.repo ? 'Downloads appear here after the first release.' : 'The repository could not be found.');
      showNoRelease(data.repo
        ? 'The first release is not published yet. It will appear here as soon as it is ready.'
        : 'The download is not available yet.');
    }
  }

  if (!configured) {
    showNoRelease('The first release is not published yet. It will appear here as soon as it is ready.');
  } else {
    var cacheKey = 'bubt-gh-' + owner + '/' + repo;
    var cached = null;
    try { cached = JSON.parse(store(cacheKey) || 'null'); } catch (e) { cached = null; }
    if (cached && Date.now() - cached.t < 10 * 60 * 1000) {
      render(cached);
    } else {
      var api = 'https://api.github.com/repos/' + owner + '/' + repo;
      Promise.all([getJson(api), getJson(api + '/releases?per_page=100')])
        .then(function (res) {
          var data = { t: Date.now(), repo: res[0], releases: res[1] || [] };
          store(cacheKey, JSON.stringify(data));
          render(data);
        })
        .catch(function () {
          card.setAttribute('data-release-state', 'error');
          setTag('GitHub', '');
          setRelease('status', 'Could not reach GitHub just now. The latest version is always on the releases page.');
          enableLink(apkBtn, ghUrls.releases, true);
          $('span', apkBtn).textContent = 'Download from GitHub';
          disableLink(notesBtn, '');
          setGh('note', 'Could not reach GitHub just now.');
        });
    }
  }

  var copyBtn = $('[data-copy-sha]');
  if (copyBtn) {
    copyBtn.addEventListener('click', function () {
      var text = $('[data-release="sha"]').textContent;
      if (!navigator.clipboard || !text) return;
      navigator.clipboard.writeText(text).then(function () {
        copyBtn.classList.add('copied');
        setTimeout(function () { copyBtn.classList.remove('copied'); }, 1500);
      });
    });
  }
})();
