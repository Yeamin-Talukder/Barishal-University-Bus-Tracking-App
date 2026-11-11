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

  /* ---------- Builds, choices and QR codes ---------- */

  function apksOf(release) {
    return (release && release.assets || []).filter(function (a) { return /\.apk$/i.test(a.name); });
  }
  // What a build is for, in words a student understands.
  function variantOf(a) {
    var n = a.name;
    if (/universal/i.test(n)) return { label: 'Universal', desc: 'Works on every phone, larger download', rank: 1 };
    if (/arm64|aarch64/i.test(n)) return { label: '64-bit', desc: 'Almost every phone from the last eight years', rank: 0, best: true };
    if (/armv7|armeabi|arm32/i.test(n)) return { label: '32-bit', desc: 'Older or low-cost phones', rank: 2 };
    if (/x86_64/i.test(n)) return { label: 'x86 64-bit', desc: 'Emulators and some tablets', rank: 3 };
    if (/x86/i.test(n)) return { label: 'x86', desc: 'Emulators', rank: 4 };
    return { label: n.replace(/\.apk$/i, ''), desc: '', rank: 9 };
  }
  function sortedApks(release) {
    return apksOf(release).sort(function (x, y) { return variantOf(x).rank - variantOf(y).rank; });
  }
  function versionOf(release) { return (release.tag_name || release.name || '').replace(/^v(?=\d)/, ''); }
  // d: { title, desc, meta, badge } shown by the custom dropdown.
  function option(value, text, selected, d) {
    var o = document.createElement('option');
    o.value = value;
    o.textContent = text;
    if (selected) o.selected = true;
    d = d || {};
    o.dataset.title = d.title || text;
    if (d.desc) o.dataset.desc = d.desc;
    if (d.meta) o.dataset.meta = d.meta;
    if (d.badge) o.dataset.badge = d.badge;
    return o;
  }

  /* ---------- Custom dropdown over a native <select> ----------
     The select stays the source of truth (value, change event); a button
     and a listbox draw it with titles, notes and badges. Keyboard: arrows,
     Home/End, Enter/Space, Escape. */
  var openDd = null;
  function enhanceSelect(wrap) {
    var sel = $('select', wrap);
    if (!sel || wrap.dd) return;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'dd-btn';
    btn.setAttribute('aria-haspopup', 'listbox');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', sel.getAttribute('aria-label') || '');
    var list = document.createElement('ul');
    list.className = 'dd-list';
    list.setAttribute('role', 'listbox');
    list.tabIndex = -1;
    sel.classList.add('dd-native');
    sel.tabIndex = -1;
    sel.setAttribute('aria-hidden', 'true');
    wrap.classList.add('dd');
    wrap.insertBefore(btn, sel);
    wrap.appendChild(list);
    var active = 0;

    function el(tag, cls, text) {
      var e = document.createElement(tag);
      if (cls) e.className = cls;
      if (text) e.textContent = text;
      return e;
    }
    function body(o, withDesc) {
      var box = el('span', 'dd-text');
      var t = el('span', 'dd-title', o.dataset.title || o.textContent);
      if (o.dataset.badge) t.appendChild(el('span', 'dd-badge', o.dataset.badge));
      box.appendChild(t);
      if (withDesc && o.dataset.desc) box.appendChild(el('span', 'dd-desc', o.dataset.desc));
      if (o.dataset.meta) box.appendChild(el('span', 'dd-meta', o.dataset.meta));
      return box;
    }
    function render() {
      btn.textContent = '';
      var cur = sel.options[sel.selectedIndex];
      if (cur) btn.appendChild(body(cur, false));
      btn.insertAdjacentHTML('beforeend', '<svg class="i dd-chev" aria-hidden="true"><use href="#i-chevron"/></svg>');
      btn.disabled = sel.disabled || sel.options.length < 2;
      wrap.classList.toggle('single', sel.options.length < 2);
      list.textContent = '';
      Array.prototype.forEach.call(sel.options, function (o, i) {
        var li = el('li', 'dd-opt');
        li.setAttribute('role', 'option');
        li.id = (sel.dataset.ddId || (sel.dataset.ddId = 'dd' + Math.random().toString(36).slice(2, 8))) + '-' + i;
        li.setAttribute('aria-selected', String(i === sel.selectedIndex));
        li.appendChild(body(o, true));
        li.insertAdjacentHTML('beforeend', '<svg class="i dd-check" aria-hidden="true"><use href="#i-check"/></svg>');
        li.addEventListener('click', function () { choose(i); });
        li.addEventListener('mousemove', function () { setActive(i); });
        list.appendChild(li);
      });
    }
    function setActive(i) {
      var items = list.children;
      if (!items.length) return;
      active = (i + items.length) % items.length;
      Array.prototype.forEach.call(items, function (li, k) { li.classList.toggle('active', k === active); });
      list.setAttribute('aria-activedescendant', items[active].id);
      items[active].scrollIntoView({ block: 'nearest' });
    }
    function open() {
      if (btn.disabled) return;
      if (openDd && openDd !== api) openDd.close();
      wrap.classList.add('open');
      btn.setAttribute('aria-expanded', 'true');
      // Open upwards when there is no room below.
      var r = wrap.getBoundingClientRect();
      wrap.classList.toggle('up', window.innerHeight - r.bottom < 260 && r.top > 300);
      setActive(sel.selectedIndex);
      list.focus({ preventScroll: true });
      openDd = api;
    }
    function close(focusBtn) {
      wrap.classList.remove('open');
      btn.setAttribute('aria-expanded', 'false');
      if (openDd === api) openDd = null;
      if (focusBtn) btn.focus();
    }
    function choose(i) {
      if (i !== sel.selectedIndex) {
        sel.selectedIndex = i;
        sel.dispatchEvent(new Event('change', { bubbles: true }));
      }
      render();
      close(true);
    }
    btn.addEventListener('click', function () { wrap.classList.contains('open') ? close() : open(); });
    btn.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); open(); }
    });
    list.addEventListener('keydown', function (e) {
      var k = e.key;
      if (k === 'ArrowDown') setActive(active + 1);
      else if (k === 'ArrowUp') setActive(active - 1);
      else if (k === 'Home') setActive(0);
      else if (k === 'End') setActive(list.children.length - 1);
      else if (k === 'Enter' || k === ' ') choose(active);
      else if (k === 'Escape' || k === 'Tab') { close(k === 'Escape'); if (k === 'Tab') return; }
      else return;
      e.preventDefault();
    });
    var api = { render: render, close: close, wrap: wrap };
    wrap.dd = api;
    render();
  }
  function refreshDd(sel) { var w = sel && sel.closest('.select'); if (w && w.dd) w.dd.render(); }
  document.addEventListener('click', function (e) {
    if (openDd && !openDd.wrap.contains(e.target)) openDd.close();
  });
  $$('.select').forEach(enhanceSelect);
  function byName(list, name) { return list.filter(function (x) { return x.name === name; })[0] || null; }

  // The releases with an APK; the latest; the build in the hero; the version
  // and build chosen in the download section. Choices are kept by tag and
  // build name, because the data is replaced when GitHub's answer arrives.
  var dl = { releases: [], latest: null, heroName: null, pickTag: null, pickLabel: null };

  /* A QR code with the app icon in its middle. Error correction level Q
     (25%) leaves room for the icon; the canvas is large so the code stays sharp. */
  var qrLogo = new Image();
  qrLogo.src = 'assets/icons/icon-192.png';
  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }
  function drawQr(canvas, text) {
    if (!canvas || !text) return;
    function draw() {
      if (!window.qrcode) return false;
      var qr = window.qrcode(0, 'Q');
      qr.addData(text);
      qr.make();
      var n = qr.getModuleCount();
      var size = canvas.width;
      var cell = Math.floor(size / (n + 2));
      var offset = Math.floor((size - n * cell) / 2);
      var ctx = canvas.getContext('2d');
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, size, size);
      ctx.fillStyle = '#0F1318';
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          if (qr.isDark(r, c)) ctx.fillRect(offset + c * cell, offset + r * cell, cell, cell);
        }
      }
      var logo = function () {
        var box = Math.round(size * 0.2);
        var x = Math.round((size - box) / 2);
        ctx.fillStyle = '#fff';
        roundRect(ctx, x - 10, x - 10, box + 20, box + 20, box * 0.3);
        ctx.fill();
        ctx.save();
        roundRect(ctx, x, x, box, box, box * 0.24);
        ctx.clip();
        ctx.drawImage(qrLogo, x, x, box, box);
        ctx.restore();
      };
      if (qrLogo.complete && qrLogo.naturalWidth) logo();
      else qrLogo.addEventListener('load', logo, { once: true });
      canvas.classList.add('ready');
      return true;
    }
    if (!draw()) window.addEventListener('load', draw, { once: true });
  }
  function fillQrCard(box, release, asset) {
    if (!box || !release || !asset) return;
    drawQr($('[data-qr-canvas]', box), asset.browser_download_url);
    var empty = $('[data-qr-empty]', box);
    if (empty) empty.hidden = true;
    $('[data-qr-file]', box).textContent = 'Downloads ' + versionOf(release) + ' · ' +
      variantOf(asset).label + (release === dl.latest ? ' (newest)' : '');
  }

  /* Hero: main button, build dropdown, QR button. */
  var heroApk = $('[data-hero-apk]');
  var heroSelect = $('[data-hero-variant]');
  var qrOpen = $('[data-qr-open]');
  function heroAsset() {
    var apks = apksOf(dl.latest);
    return byName(apks, dl.heroName) || pickApk(apks);
  }
  function renderHero() {
    var a = heroAsset();
    if (!a) return;
    dl.heroName = a.name;
    heroApk.setAttribute('href', a.browser_download_url);
    $('[data-hero-sub]').textContent = 'Download ' + (dl.latest.tag_name || '');
    $('[data-hero-label]').textContent = 'Android';
    var note = $('[data-hero-note]');
    note.textContent = variantOf(a).label + ' build · ' + formatSize(a.size) + ' · Android 7.0 or newer · Free';
    note.hidden = false;
    qrOpen.disabled = false;
    setDock(a.browser_download_url, (dl.latest.tag_name || '') + ' · ' + variantOf(a).label + ' · ' + formatSize(a.size));
  }
  function setupHero() {
    var apks = sortedApks(dl.latest);
    var current = heroAsset();
    heroSelect.textContent = '';
    apks.forEach(function (a) {
      var v = variantOf(a);
      heroSelect.appendChild(option(a.name, v.label, a === current, {
        title: v.label, desc: v.desc, meta: formatSize(a.size), badge: v.best ? 'Best' : ''
      }));
    });
    $('[data-hero-variant-wrap]').hidden = apks.length < 2;
    refreshDd(heroSelect);
    renderHero();
  }
  heroSelect.addEventListener('change', function () {
    dl.heroName = heroSelect.value;
    renderHero();
  });

  var qrDialog = $('[data-qr-dialog]');
  qrOpen.addEventListener('click', function () {
    var a = heroAsset();
    if (!a) return;
    fillQrCard($('[data-qr-card="dialog"]'), dl.latest, a);
    if (qrDialog.showModal) qrDialog.showModal();
    else qrDialog.setAttribute('open', '');
  });
  $('[data-qr-close]').addEventListener('click', function () { qrDialog.close(); });
  // A click on the dimmed backdrop closes it too.
  qrDialog.addEventListener('click', function (e) { if (e.target === qrDialog) qrDialog.close(); });

  /* Download section: version and build dropdowns, every build, QR panel. */
  var pickRelease = $('[data-pick-release]');
  var pickBuild = $('[data-pick-build]');
  function pickedRelease() {
    return dl.releases.filter(function (r) { return r.tag_name === dl.pickTag; })[0] || dl.latest;
  }
  function pickedAsset() {
    var apks = apksOf(pickedRelease());
    return apks.filter(function (a) { return variantOf(a).label === dl.pickLabel; })[0] || pickApk(apks);
  }
  function setupPickers() {
    var chosen = pickedRelease();
    pickRelease.textContent = '';
    dl.releases.forEach(function (r) {
      var kind = r === dl.latest ? ' · Latest' : (r.prerelease ? ' · Pre-release' : '');
      var when = r.published_at ? ' · ' + formatDate(r.published_at) : '';
      pickRelease.appendChild(option(r.tag_name, (r.tag_name || r.name) + kind + when, r === chosen, {
        title: r.tag_name || r.name, badge: r === dl.latest ? 'Latest' : (r.prerelease ? 'Pre-release' : ''),
        meta: (r.published_at ? formatDate(r.published_at) : '') + ' · ' + apksOf(r).length + ' build' + (apksOf(r).length === 1 ? '' : 's')
      }));
    });
    pickRelease.disabled = dl.releases.length < 2;
    refreshDd(pickRelease);
    $('[data-pickers]').hidden = false;
    fillBuilds();
  }
  function fillBuilds() {
    var current = pickedAsset();
    var apks = sortedApks(pickedRelease());
    pickBuild.textContent = '';
    apks.forEach(function (a) {
      var v = variantOf(a);
      pickBuild.appendChild(option(a.name, v.label + ' · ' + formatSize(a.size), a === current, {
        title: v.label, desc: v.desc, badge: v.best ? 'Recommended' : '',
        meta: formatSize(a.size) + ' · ' + formatCount(a.download_count || 0) + ' download' + (a.download_count === 1 ? '' : 's')
      }));
    });
    pickBuild.disabled = apks.length < 2;
    refreshDd(pickBuild);
    renderPick();
  }
  pickRelease.addEventListener('change', function () {
    dl.pickTag = pickRelease.value;
    fillBuilds();
  });
  pickBuild.addEventListener('change', function () {
    var a = byName(apksOf(pickedRelease()), pickBuild.value);
    if (a) dl.pickLabel = variantOf(a).label;
    renderPick();
  });
  function renderPick() {
    var r = pickedRelease();
    var a = pickedAsset();
    var latest = r === dl.latest;
    setTag(latest ? 'Latest' : (r.prerelease ? 'Pre-release' : 'Older version'), latest ? 'ok' : 'soon');
    setRelease('version', r.tag_name || r.name || '—');
    setRelease('date', r.published_at ? formatDate(r.published_at) : '—');
    enableLink(notesBtn, r.html_url, true);
    var shaWrap = $('[data-release="sha-wrap"]', card);
    if (a) {
      var v = variantOf(a);
      dl.pickLabel = v.label;
      setRelease('size', formatSize(a.size));
      setRelease('downloads', formatCount(a.download_count || 0));
      setRelease('status', (latest ? '' : 'This is an older version. ') +
        v.label + ' build' + (v.desc ? ': ' + v.desc.charAt(0).toLowerCase() + v.desc.slice(1) : '') + '.');
      enableLink(apkBtn, a.browser_download_url, false);
      $('span', apkBtn).textContent = 'Download ' + v.label + ' APK (' + formatSize(a.size) + ')';
      if (a.digest && /^sha256:/.test(a.digest)) {
        setRelease('sha', a.digest.slice(7));
        shaWrap.hidden = false;
      } else {
        shaWrap.hidden = true;
      }
      fillQrCard($('[data-qr-card="panel"]'), r, a);
    }
    renderBuildList(r, a);
  }
  function renderBuildList(release, chosen) {
    var list = $('[data-builds-list]');
    var apks = sortedApks(release);
    list.textContent = '';
    apks.forEach(function (a) {
      var v = variantOf(a);
      var li = document.createElement('li');
      li.className = 'build' + (a === chosen ? ' chosen' : '');
      li.innerHTML =
        '<div class="build-info"><b class="build-name"></b><span class="build-desc"></span><span class="build-meta"></span></div>' +
        '<div class="build-actions">' +
        '<a class="btn btn-sm btn-ghost build-dl"><svg class="i"><use href="#i-download"/></svg><span>Download</span></a>' +
        '<button type="button" class="icon-btn build-qr"><svg class="i"><use href="#i-qr"/></svg></button>' +
        '</div>';
      $('.build-name', li).textContent = v.label;
      if (v.best) {
        var tag = document.createElement('span');
        tag.className = 'tag ok';
        tag.textContent = 'Recommended';
        $('.build-name', li).appendChild(tag);
      }
      $('.build-desc', li).textContent = v.desc;
      $('.build-meta', li).textContent = formatSize(a.size) + ' · ' + formatCount(a.download_count || 0) +
        ' download' + (a.download_count === 1 ? '' : 's') + ' · ' + a.name;
      $('.build-dl', li).setAttribute('href', a.browser_download_url);
      $('.build-dl', li).setAttribute('aria-label', 'Download the ' + v.label + ' build (' + formatSize(a.size) + ')');
      var q = $('.build-qr', li);
      q.setAttribute('aria-label', 'Show the QR code for the ' + v.label + ' build');
      q.setAttribute('title', 'Show this build\'s QR code');
      q.addEventListener('click', function () {
        dl.pickLabel = v.label;
        pickBuild.value = a.name;
        refreshDd(pickBuild);
        renderPick();
        var panel = $('.qr-panel');
        panel.classList.remove('flash');
        void panel.offsetWidth;
        panel.classList.add('flash');
        if (window.matchMedia('(max-width: 1020px)').matches) {
          panel.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'center' });
        }
      });
      list.appendChild(li);
    });
    $('[data-builds]').hidden = !apks.length;
  }

  /* ---------- Download bar on phones ---------- */

  var dock = $('[data-dock]');
  function setDock(href, meta) {
    if (!dock) return;
    var link = $('[data-dock-link]', dock);
    if (href) link.setAttribute('href', href);
    if (meta) $('[data-dock-meta]', dock).textContent = meta;
  }
  (function () {
    if (!dock) return;
    dock.hidden = false;
    var hero = $('.hero');
    var download = $('#download');
    var footer = $('.site-footer');
    function update() {
      var h = window.innerHeight;
      var pastHero = hero ? hero.getBoundingClientRect().bottom < h * 0.35 : true;
      // Not over the download section itself, nor over the footer.
      var d = download ? download.getBoundingClientRect() : null;
      var onDownload = d ? d.top < h * 0.8 && d.bottom > h * 0.2 : false;
      var atFooter = footer ? footer.getBoundingClientRect().top < h - 40 : false;
      dock.classList.toggle('show', pastHero && !onDownload && !atFooter);
    }
    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update);
    update();
  })();

  function showNoRelease(message) {
    card.setAttribute('data-release-state', 'none');
    setTag('Coming soon', 'soon');
    setRelease('status', message);
    disableLink(apkBtn, 'No release yet');
    disableLink(notesBtn, 'No release yet');
    var all = $('.all-releases', card);
    if (!configured) disableLink(all, 'Coming soon');
  }

  function showReleases(releases, latestAny) {
    dl.releases = releases.filter(function (r) { return apksOf(r).length; });
    if (!dl.releases.length) {
      // A release without an APK: point to its page.
      card.setAttribute('data-release-state', 'ready');
      setTag(latestAny.prerelease ? 'Pre-release' : 'Latest', latestAny.prerelease ? 'soon' : 'ok');
      setRelease('version', latestAny.tag_name || latestAny.name || '—');
      setRelease('date', latestAny.published_at ? formatDate(latestAny.published_at) : '—');
      setRelease('size', '—');
      setRelease('status', 'This version has no APK attached. See the release page for its files.');
      enableLink(notesBtn, latestAny.html_url, true);
      enableLink(apkBtn, latestAny.html_url, true);
      return;
    }
    dl.latest = dl.releases.filter(function (r) { return !r.prerelease; })[0] || dl.releases[0];
    card.setAttribute('data-release-state', 'ready');
    setupHero();
    setupPickers();
  }

  function getJson(url) {
    return fetch(url, { headers: { Accept: 'application/vnd.github+json' } }).then(function (res) {
      if (res.status === 404) return null;
      if (!res.ok) throw new Error('GitHub answered ' + res.status);
      return res.json();
    });
  }

  // note: the line under the GitHub numbers. Left out when the numbers
  // have just come from GitHub.
  function render(data, note) {
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
      var hd = $('[data-hero-downloads]');
      if (hd) {
        $('b', hd).textContent = formatCount(total);
        $('span', hd).textContent = total === 1 ? 'download' : 'downloads';
        hd.hidden = false;
      }
      setGh('version', latest.tag_name || '—');
      setGh('note', note || 'Live from GitHub.');
      showReleases(releases, latest);
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
      // GitHub answers only 60 questions an hour from one network, and a
      // campus network can use those up. So the site also carries a copy of
      // the release details saved when it was last built (release.json).
      // That copy is shown at once, then replaced by GitHub's own answer;
      // if GitHub does not answer, the copy stays, with its date.
      var settled = false;
      var shown = null;
      var savedNote = function (d) {
        return 'Figures saved on ' + formatDate(new Date(d.t).toISOString()) + '.';
      };
      var showSaved = function (d) {
        if (settled || !d || !d.releases || !d.releases.length) return;
        if (shown && shown.t >= d.t) return;
        shown = d;
        render(d, savedNote(d));
      };
      if (cached) showSaved(cached);
      fetch('release.json', { cache: 'no-cache' })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(showSaved)
        .catch(function () {});

      var api = 'https://api.github.com/repos/' + owner + '/' + repo;
      Promise.all([getJson(api), getJson(api + '/releases?per_page=100')])
        .then(function (res) {
          settled = true;
          var data = { t: Date.now(), repo: res[0], releases: res[1] || [] };
          store(cacheKey, JSON.stringify(data));
          render(data);
        })
        .catch(function () {
          // Give the saved copy a moment to arrive before showing a fault.
          setTimeout(function () {
            if (shown) return;
            settled = true;
            card.setAttribute('data-release-state', 'error');
            setTag('GitHub', '');
            setRelease('status', 'Could not reach GitHub just now. The latest version is always on the releases page.');
            enableLink(apkBtn, ghUrls.releases, true);
            $('span', apkBtn).textContent = 'Download from GitHub';
            disableLink(notesBtn, '');
            setGh('note', 'Could not reach GitHub just now.');
          }, 1500);
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
