/* ─────────────────────────────────────────────────────────────────────────────
   KIVO – Shared Script
   ───────────────────────────────────────────────────────────────────────────── */

/* ── Navbar: add glass on scroll ── */
(function () {
  const nav = document.querySelector('.nav');
  if (!nav) return;
  const toggle = () => nav.classList.toggle('scrolled', window.scrollY > 20);
  window.addEventListener('scroll', toggle, { passive: true });
  toggle();
})();

/* ── Mobile menu toggle ── */
(function () {
  const btn   = document.querySelector('.nav-menu-btn');
  const links = document.querySelector('.nav-links');
  if (!btn || !links) return;

  btn.addEventListener('click', () => {
    const open = links.classList.toggle('open');
    btn.setAttribute('aria-expanded', open);
  });

  links.querySelectorAll('a').forEach(a =>
    a.addEventListener('click', () => links.classList.remove('open'))
  );
})();

/* ── Intersection Observer: fade-up animation ── */
(function () {
  const els = document.querySelectorAll('.fade-up');
  if (!els.length) return;

  const observer = new IntersectionObserver(
    entries => entries.forEach(e => {
      if (e.isIntersecting) {
        e.target.classList.add('visible');
        observer.unobserve(e.target);
      }
    }),
    { threshold: 0.12 }
  );

  els.forEach((el, i) => {
    el.style.transitionDelay = `${(i % 4) * 80}ms`;
    observer.observe(el);
  });
})();

/* ── Smooth anchor scroll ── */
(function () {
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
      const target = document.querySelector(a.getAttribute('href'));
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });
})();
