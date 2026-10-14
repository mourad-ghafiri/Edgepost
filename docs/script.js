// Edgepost website. Everything works without it: the tour's screens also sit
// inline under each step, the device strips are plain lists, and the
// viewer is an enhancement over images that already show.
(() => {
  'use strict';

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');

  // The header's hairline once the page scrolls.
  const header = document.querySelector('.site-header');
  if (header) {
    const onScroll = () => header.classList.toggle('is-scrolled', window.scrollY > 4);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  // The menu on narrow screens.
  const menuButton = document.querySelector('.menu-button');
  const nav = document.getElementById('site-nav');
  if (menuButton && nav) {
    header.classList.add('has-menu');
    const narrow = window.matchMedia('(max-width: 760px)');
    const sync = () => {
      if (narrow.matches) {
        nav.hidden = menuButton.getAttribute('aria-expanded') !== 'true';
      } else {
        nav.hidden = false;
        menuButton.setAttribute('aria-expanded', 'false');
      }
    };
    menuButton.addEventListener('click', () => {
      const open = menuButton.getAttribute('aria-expanded') !== 'true';
      menuButton.setAttribute('aria-expanded', String(open));
      sync();
    });
    nav.addEventListener('click', (e) => {
      if (e.target.closest('a') && narrow.matches) {
        menuButton.setAttribute('aria-expanded', 'false');
        sync();
      }
    });
    narrow.addEventListener('change', sync);
    sync();
  }

  // The tour: as a step's words reach the reading line (60% down the
  // window), the pinned phone shows its screen (sliding in like a pushed
  // page, or back out like a popped one when scrolling up), and the phone's
  // tab bar lights its chapter. Above the first step, Today.
  const screen = document.querySelector('.phone__screen');
  const dock = document.querySelector('.dock');
  const steps = [...document.querySelectorAll('.step[data-screen]')];
  if (screen && dock && steps.length) {
    const images = new Map([...screen.querySelectorAll('img[data-screen]')].map((img) => [img.dataset.screen, img]));
    const tabs = [...dock.querySelectorAll('button[data-chapter]')];
    const heads = steps.map((step) => step.firstElementChild);
    const mailBadge = dock.querySelector('[data-badge="mail"]');
    let index = 0;

    const show = (next) => {
      const from = images.get(steps[index].dataset.screen);
      const to = images.get(steps[next].dataset.screen);
      if (from === to && to.classList.contains('is-current')) return;
      screen.classList.toggle('is-back', next < index);
      images.forEach((img) => img.classList.remove('is-behind'));
      from.classList.remove('is-current');
      from.classList.add('is-behind');
      from.setAttribute('aria-hidden', 'true');
      to.classList.add('is-current');
      to.removeAttribute('aria-hidden');
      // The app shows a thread, a reply or a domain's signature without its
      // tab bar; the Mail badge is the unread count on that screen.
      dock.classList.toggle('is-away', to.dataset.tabbar === 'false');
      if (mailBadge && to.dataset.mail) mailBadge.textContent = to.dataset.mail;
      index = next;
      const chapter = steps[next].closest('.chapter');
      tabs.forEach((tab) => {
        if (chapter && tab.dataset.chapter === chapter.id) tab.setAttribute('aria-current', 'step');
        else tab.removeAttribute('aria-current');
      });
    };

    let queued = false;
    const pick = () => {
      queued = false;
      const line = window.innerHeight * 0.6;
      let next = 0;
      heads.forEach((head, i) => {
        if (head.getBoundingClientRect().top < line) next = i;
      });
      show(next);
    };
    const onScroll = () => {
      if (!queued) {
        queued = true;
        requestAnimationFrame(pick);
      }
    };

    images.get(steps[0].dataset.screen).classList.add('is-current');
    tabs[0].setAttribute('aria-current', 'step');
    dock.hidden = false;
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
    pick();

    tabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        const target = document.getElementById(tab.dataset.chapter);
        if (!target) return;
        target.scrollIntoView({ behavior: reduced.matches ? 'auto' : 'smooth', block: 'start' });
        const heading = target.querySelector('h1, h2');
        if (heading) heading.focus({ preventScroll: true });
      });
    });
  }

  // A link to an answer opens it (#cost from the hero's sending line).
  const openAnswer = () => {
    const target = location.hash && document.getElementById(location.hash.slice(1));
    if (target && target.tagName === 'DETAILS') target.open = true;
  };
  window.addEventListener('hashchange', openAnswer);
  document.querySelectorAll('a[href^="#"]').forEach((link) => {
    link.addEventListener('click', () => {
      const target = document.getElementById(link.getAttribute('href').slice(1));
      if (target && target.tagName === 'DETAILS') target.open = true;
    });
  });
  openAnswer();

  // Screens: one tab per device, one strip each.
  const tablist = document.querySelector('[role="tablist"]');
  if (tablist) {
    const tabs = [...tablist.querySelectorAll('[role="tab"]')];
    const select = (tab, focus) => {
      tabs.forEach((t) => {
        const on = t === tab;
        t.setAttribute('aria-selected', String(on));
        t.tabIndex = on ? 0 : -1;
        document.getElementById(t.getAttribute('aria-controls')).hidden = !on;
      });
      if (focus) tab.focus();
    };
    tabs.forEach((tab, i) => {
      tab.addEventListener('click', () => select(tab, false));
      tab.addEventListener('keydown', (e) => {
        const move = { ArrowRight: 1, ArrowLeft: -1, Home: -i, End: tabs.length - 1 - i }[e.key];
        if (move === undefined) return;
        e.preventDefault();
        select(tabs[(i + move + tabs.length) % tabs.length], true);
      });
    });
  }

  // Previous and next for the strip on screen, for a mouse with no
  // sideways scroll.
  const stripNav = document.querySelector('.strip-nav');
  if (stripNav) {
    const strips = [...document.querySelectorAll('.strip')];
    const [prev, next] = stripNav.querySelectorAll('button');
    const visible = () => strips.find((strip) => !strip.hidden);
    const update = () => {
      const strip = visible();
      if (!strip) return;
      const end = strip.scrollWidth - strip.clientWidth - 2;
      prev.disabled = strip.scrollLeft <= 2;
      next.disabled = strip.scrollLeft >= end;
      stripNav.hidden = strip.scrollWidth <= strip.clientWidth + 2;
    };
    stripNav.querySelectorAll('button').forEach((button) => {
      button.addEventListener('click', () => {
        const strip = visible();
        strip.scrollBy({ left: Number(button.dataset.strip) * strip.clientWidth * 0.85, behavior: reduced.matches ? 'auto' : 'smooth' });
      });
    });
    strips.forEach((strip) => strip.addEventListener('scroll', update, { passive: true }));
    document.querySelectorAll('[role="tab"]').forEach((tab) => {
      tab.addEventListener('click', () => requestAnimationFrame(update));
      tab.addEventListener('keyup', () => requestAnimationFrame(update));
    });
    window.addEventListener('resize', update);
    update();
  }

  // The viewer: a screen at full size, with the others of its strip a
  // swipe, an arrow key or a button away.
  const viewer = document.getElementById('viewer');
  if (viewer && typeof viewer.showModal === 'function') {
    const image = viewer.querySelector('img');
    const caption = viewer.querySelector('figcaption');
    let shots = [];
    let at = 0;
    let opener = null;

    const render = () => {
      const shot = shots[at];
      const img = shot.querySelector('img');
      image.src = shot.dataset.full;
      image.alt = img.alt;
      image.width = img.width;
      image.height = img.height;
      caption.textContent = `${shot.dataset.caption} · ${at + 1} of ${shots.length}`;
    };
    const step = (d) => {
      at = (at + d + shots.length) % shots.length;
      render();
    };

    document.querySelectorAll('.shot').forEach((shot) => {
      shot.addEventListener('click', () => {
        shots = [...shot.parentElement.querySelectorAll('.shot')];
        at = shots.indexOf(shot);
        opener = shot;
        render();
        viewer.showModal();
      });
    });
    viewer.querySelector('[data-prev]').addEventListener('click', () => step(-1));
    viewer.querySelector('[data-next]').addEventListener('click', () => step(1));
    viewer.querySelector('[data-close]').addEventListener('click', () => viewer.close());
    viewer.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight') step(1);
      if (e.key === 'ArrowLeft') step(-1);
    });
    viewer.addEventListener('click', (e) => {
      if (e.target === viewer) viewer.close();
    });
    let startX = null;
    viewer.addEventListener('touchstart', (e) => (startX = e.touches[0].clientX), { passive: true });
    viewer.addEventListener('touchend', (e) => {
      if (startX === null) return;
      const dx = e.changedTouches[0].clientX - startX;
      if (Math.abs(dx) > 48) step(dx < 0 ? 1 : -1);
      startX = null;
    });
    viewer.addEventListener('close', () => opener && opener.focus());
  }

})();
