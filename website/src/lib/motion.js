export function reveal(node, options = {}) {
  const query = window.matchMedia('(prefers-reduced-motion: reduce)');
  let observer;
  const show = () => node.classList.add('is-visible');
  node.classList.add('reveal');
  node.style.setProperty('--reveal-delay', `${options.delay || 0}ms`);
  if (query.matches || !('IntersectionObserver' in window)) show();
  else {
    observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            show();
            if (!options.repeat) observer.unobserve(node);
          } else if (options.repeat) node.classList.remove('is-visible');
        }
      },
      { threshold: Math.min(options.threshold ?? 0.18, 0.5) }
    );
    observer.observe(node);
  }
  const change = () => {
    if (query.matches) {
      show();
      observer?.disconnect();
    }
  };
  query.addEventListener('change', change);
  return {
    destroy() {
      observer?.disconnect();
      query.removeEventListener('change', change);
    }
  };
}
