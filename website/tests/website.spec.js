import { expect, test } from '@playwright/test';
import { closedShots, tabShots } from '../src/lib/shots.js';

const dmg = 'https://github.com/Mehdidjah/notchy-releases/releases/latest/download/Notchy.dmg';
const releaseApi = '**/repos/Mehdidjah/notchy-releases/releases/latest';
const release = { tag_name: 'v2.4.0', assets: [{ name: 'Notchy-test.dmg', size: 12_500_000 }] };

async function mockRelease(page, body = release, status = 200) {
  await page.route(releaseApi, (route) =>
    route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) })
  );
}

async function open(page) {
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Your notch, finally useful.' })).toBeVisible();
  return errors;
}

// The feature cards in page order and the screenshot of the real app each one shows.
const featureShots = [
  'tab-clipboard',
  'tab-shelf',
  'tab-home',
  'tab-timer',
  'tab-stats',
  'tab-notes',
  'tab-face',
  'tab-ai'
];

/** Waits until an image has loaded and returns its natural and displayed widths. */
async function loadedWidths(image) {
  await image.scrollIntoViewIfNeeded();
  await expect
    .poll(() => image.evaluate((img) => (img.complete ? img.naturalWidth : 0)))
    .toBeGreaterThan(0);
  return image.evaluate((img) => [img.naturalWidth, img.getBoundingClientRect().width]);
}

test.beforeEach(async ({ page }) => {
  await mockRelease(page);
});
test('renders release metadata, fixed download and section anchors without horizontal overflow', async ({
  page
}) => {
  const errors = await open(page);
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
    'href',
    'https://notchy-gamma.vercel.app/'
  );
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute(
    'content',
    'https://notchy-gamma.vercel.app/assets/img/social-card.jpg'
  );
  await expect(page.locator('.release-version')).toHaveText('Version 2.4.0');
  await expect(page.locator('.download-meta')).toContainText('Notchy-test.dmg · 13 MB · Universal');
  await expect(page.locator(`a[href="${dmg}"]`)).toHaveCount(6);
  for (const id of ['top', 'features', 'live', 'privacy', 'download', 'install', 'faq'])
    await expect(page.locator(`#${id}`)).toHaveCount(1);
  for (const width of [1440, 810, 390, 320]) {
    await page.setViewportSize({ width, height: 844 });
    await expect
      .poll(() => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))
      .toBeTruthy();
  }
  expect(errors).toEqual([]);
});

test('uses fallback release copy when release metadata fails', async ({ page }) => {
  await page.unroute(releaseApi);
  await mockRelease(page, { message: 'unavailable' }, 503);
  const errors = await open(page);
  await expect(
    page.getByText('Release details are unavailable. Check GitHub for download availability.')
  ).toBeVisible();
  await expect(page.locator('.release-version')).toHaveText('Latest release');
  await expect(page.locator('.download-meta')).toHaveText('Notchy.dmg · Universal Mac app');
  await expect(page.locator(`a[href="${dmg}"]`).first()).toBeVisible();
  expect(errors).toEqual([]);
});

test('mobile navigation opens and closes via link and Escape', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const errors = await open(page);
  await page.getByRole('button', { name: 'Open navigation' }).click();
  await expect(page.getByRole('navigation', { name: 'Main navigation' })).toHaveClass(/menu-open/);
  await page.getByRole('navigation').getByRole('link', { name: 'Features' }).click();
  await expect(page).toHaveURL(/#features$/);
  await expect(page.getByRole('button', { name: 'Open navigation' })).toHaveAttribute(
    'aria-expanded',
    'false'
  );
  await expect(page.getByRole('navigation').getByRole('link', { name: 'Features' })).toBeHidden();
  await page.getByRole('button', { name: 'Open navigation' }).click();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button', { name: 'Open navigation' })).toBeVisible();
  expect(errors).toEqual([]);
});

test('feature cards show sharp screenshots of the real app on each tab', async ({ page }) => {
  const errors = await open(page);
  const shots = page.locator('.feature-card .island-shot');
  await expect(shots).toHaveCount(featureShots.length);
  for (const [index, name] of featureShots.entries()) {
    const shot = shots.nth(index);
    await expect(shot).toHaveAttribute('src', `/assets/app/${name}.png`);
    await expect(shot).toHaveAttribute('alt', /^Notchy/);
    const [natural, shown] = await loadedWidths(shot);
    expect(natural).toBeGreaterThanOrEqual(shown * 2 - 2);
  }
  const ai = page.getByRole('group', { name: 'AI tools view' });
  await ai.getByRole('button', { name: 'Sessions', exact: true }).click();
  await expect(ai.getByRole('button', { name: 'Sessions', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await expect(shots.last()).toHaveAttribute('src', '/assets/app/tab-ai-sessions.png');
  await loadedWidths(shots.last());
  await ai.getByRole('button', { name: 'Chat', exact: true }).click();
  await expect(shots.last()).toHaveAttribute('src', '/assets/app/tab-ai.png');
  expect(errors).toEqual([]);
});

test('download tabs and FAQ are keyboard-accessible', async ({ page }) => {
  const errors = await open(page);
  const downloadTabs = page.getByRole('tablist', { name: 'Get Notchy' });
  await downloadTabs.getByRole('tab', { name: 'The app' }).focus();
  await page.keyboard.press('ArrowRight');
  await expect(downloadTabs.getByRole('tab', { name: 'Getting started' })).toHaveAttribute(
    'aria-selected',
    'true'
  );
  await expect(page.getByRole('tabpanel', { name: 'Getting started' })).toContainText(
    'Just drag it in.'
  );
  await page.keyboard.press('ArrowLeft');
  await expect(downloadTabs.getByRole('tab', { name: 'The app' })).toHaveAttribute(
    'aria-selected',
    'true'
  );
  await expect(downloadTabs.getByRole('tab', { name: 'The app' })).toBeFocused();
  await downloadTabs.getByRole('tab', { name: 'Getting started' }).click();
  await expect(page.getByRole('link', { name: 'View installation steps' })).toHaveAttribute(
    'href',
    '#install'
  );
  await downloadTabs.getByRole('tab', { name: 'The app' }).click();
  await expect(page.getByRole('tabpanel', { name: 'The app' })).toContainText('Hello, Notchy.');
  const faq = page.getByRole('button', { name: 'What is Notchy?' });
  await faq.click();
  await expect(faq).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByRole('region', { name: 'What is Notchy?' })).toBeVisible();
  await faq.click();
  await expect(faq).toHaveAttribute('aria-expanded', 'false');
  await expect(page.getByRole('region', { name: 'What is Notchy?' })).toHaveCount(0);
  expect(errors).toEqual([]);
});

test('screenshot sizes in shots.js match the images at the scale they are drawn at', async ({
  page
}) => {
  await page.goto('/');
  const sizeOf = (src) =>
    page.evaluate(async (url) => {
      const image = new Image();
      image.src = url;
      await image.decode();
      return [image.naturalWidth, image.naturalHeight];
    }, src);
  // The open island is drawn at 2x, the closed notch at 4x (Tests/NotchyTests/WebsiteShot*).
  for (const shot of Object.values(tabShots)) {
    const [width, height] = await sizeOf(shot.src);
    expect([width / 2, height / 2], shot.src).toEqual([shot.width, shot.height]);
  }
  for (const shot of closedShots) {
    const [width, height] = await sizeOf(shot.src);
    expect([width / 4, height / 4], shot.src).toEqual([shot.width, shot.height]);
  }
});

test('live activities show the real closed notch for each activity', async ({ page }) => {
  const errors = await open(page);
  const live = page.getByRole('region', { name: 'Live activities on the closed notch' });
  const stage = live.locator('.stage-shot');
  for (const [name, file] of [
    ['Timer', 'closed-timer'],
    ['Next meeting', 'closed-reminder'],
    ['Claude Code', 'closed-claude'],
    ['Volume', 'closed-volume'],
    ['Brightness', 'closed-brightness'],
    ['Shelf', 'closed-shelf'],
    ['Caps Lock', 'closed-capslock'],
    ['Copied', 'peek-copied'],
    ['Face Check', 'closed-facecheck'],
    ['Now playing', 'closed-music']
  ]) {
    const button = live.getByRole('button', { name, exact: true });
    await button.click();
    await expect(button).toHaveAttribute('aria-pressed', 'true');
    await expect(stage).toHaveAttribute('src', `/assets/app/${file}.png`);
    await loadedWidths(stage);
  }
  await expect(live.getByRole('button', { pressed: true })).toHaveCount(1);
  expect(errors).toEqual([]);
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('disables animation and hero parallax', async ({ page }) => {
    const errors = await open(page);
    await page.evaluate(() => window.scrollTo(0, 500));
    await expect
      .poll(() => page.locator('.hero-foreground').evaluate((el) => getComputedStyle(el).transform))
      .toBe('none');
    await expect(page.locator('.hero-foreground')).toHaveCSS('will-change', 'auto');
    expect(
      await page
        .locator('.headline-char')
        .first()
        .evaluate((el) => parseFloat(getComputedStyle(el).animationDuration))
    ).toBeLessThanOrEqual(0.00001);
    await expect(page.locator('.site-nav')).toHaveCSS('animation-name', 'none');
    expect(
      await page
        .locator('.activity-card')
        .first()
        .evaluate((el) => parseFloat(getComputedStyle(el).transitionDuration))
    ).toBeLessThanOrEqual(0.00001);
    expect(
      await page
        .locator('#top')
        .evaluate((el) => getComputedStyle(el).getPropertyValue('--hero-progress').trim())
    ).toBe('0');
    expect(errors).toEqual([]);
  });
});

test('decorative motion is reversible and can be paused without hiding content', async ({
  page
}) => {
  await open(page);
  await page.evaluate(() => window.scrollTo({ top: 500, behavior: 'instant' }));
  await expect
    .poll(() =>
      page
        .locator('#top')
        .evaluate((el) => Number(getComputedStyle(el).getPropertyValue('--hero-progress')))
    )
    .toBeGreaterThan(0);
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
  await expect
    .poll(() =>
      page
        .locator('#top')
        .evaluate((el) => Number(getComputedStyle(el).getPropertyValue('--hero-progress')))
    )
    .toBe(0);
  await page.getByRole('button', { name: 'Pause decorative motion' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-motion', 'paused');
  await expect(page.locator('.feature-card').first()).toHaveCSS('opacity', '1');
  await expect(page.locator('.feature-card').first()).toHaveCSS('transition-duration', '0s');
  await page.getByRole('button', { name: 'Resume decorative motion' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-motion', 'running');
});

test('hero keeps its responsive scene scale and shows the real island', async ({ page }) => {
  await open(page);
  for (const [width, expectedFrame, headingSize] of [
    [1440, 1000, '80px'],
    [968, 700, '80px'],
    [390, 350, '50px']
  ]) {
    await page.setViewportSize({ width, height: 1042 });
    await expect
      .poll(async () => Math.round((await page.locator('.glass-desktop').boundingBox()).width))
      .toBe(expectedFrame);
    await expect(page.locator('.hero-copy h1')).toHaveCSS('font-size', headingSize);
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)
    ).toBeTruthy();
  }
  await page.setViewportSize({ width: 1440, height: 1042 });
  const island = page.locator('.hero-island');
  await expect(island).toHaveAttribute('src', '/assets/app/tab-home.png');
  const [natural, shown] = await loadedWidths(island);
  expect(natural).toBeGreaterThanOrEqual(shown * 2 - 2);
  // The app icons once extracted from macOS are gone; only the menu glyph remains.
  expect(await page.locator('img[src^="/assets/macos/"]').count()).toBe(0);
});

test('audience cards use six vector icons in 64px badges', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await open(page);
  const cards = page.locator('.benefit-card');
  const badges = cards.locator('.benefit-icon');
  const icons = badges.locator('img');
  await expect(cards).toHaveCount(6);
  await expect(icons).toHaveCount(6);
  const names = [
    'paint-brush',
    'code-block',
    'pencil-line',
    'calendar-check',
    'browsers',
    'laptop'
  ];
  for (let i = 0; i < names.length; i++) {
    await expect(icons.nth(i)).toHaveAttribute('src', `/assets/icons/benefits/${names[i]}.svg`);
    await expect(icons.nth(i)).toHaveAttribute('alt', '');
    await expect(badges.nth(i)).toHaveAttribute('aria-hidden', 'true');
    const response = await page.request.get(`/assets/icons/benefits/${names[i]}.svg`);
    expect(response.ok()).toBeTruthy();
    expect(response.headers()['content-type']).toContain('image/svg+xml');
  }
  for (const width of [1440, 968, 390, 320]) {
    await page.setViewportSize({ width, height: 1000 });
    await expect(badges.first()).toHaveCSS('width', '64px');
    await expect(badges.first()).toHaveCSS('height', '64px');
    await expect(badges.first()).toHaveCSS('border-radius', '30px');
    await expect(icons.first()).toHaveCSS('width', '24px');
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)
    ).toBeTruthy();
  }
  await expect
    .poll(() =>
      icons.evaluateAll((imgs) => imgs.every((img) => img.complete && img.naturalWidth > 0))
    )
    .toBeTruthy();
});

test('download card uses the expected surface, notch, tabs and checks', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await open(page);
  const card = page.locator('.download-card');
  await card.scrollIntoViewIfNeeded();
  const design = await card.evaluate((el) => {
    const style = getComputedStyle(el);
    const notch = el.querySelector('.download-notch');
    const tabs = el.querySelector('.download-tabs');
    const active = tabs.querySelector('[aria-selected="true"]');
    const cta = el.querySelector('.download-panel > .button');
    return {
      width: el.getBoundingClientRect().width,
      surface: style.backgroundColor,
      radius: style.borderRadius,
      padding: style.padding,
      shadow: style.boxShadow,
      notchWidth: notch.getBoundingClientRect().width,
      notchHeight: notch.getBoundingClientRect().height,
      notchFontSize: getComputedStyle(notch).fontSize,
      notchShoulder: getComputedStyle(notch, '::before').backgroundImage,
      tabsHeight: tabs.getBoundingClientRect().height,
      tabsBackground: getComputedStyle(tabs).backgroundColor,
      indicatorBackground: getComputedStyle(tabs, '::before').backgroundColor,
      activeColor: getComputedStyle(active).color,
      ctaRadius: getComputedStyle(cta).borderRadius,
      ctaHeight: cta.getBoundingClientRect().height,
      checkColor: getComputedStyle(el.querySelector('.download-checks svg')).color
    };
  });
  expect(design).toMatchObject({
    width: 400,
    surface: 'rgb(247, 247, 247)',
    radius: '40px',
    padding: '80px 40px 40px',
    shadow: 'none',
    notchWidth: 240,
    notchHeight: 50,
    notchFontSize: '16px',
    tabsHeight: 40,
    tabsBackground: 'rgb(255, 255, 255)',
    indicatorBackground: 'rgb(0, 0, 0)',
    activeColor: 'rgb(255, 255, 255)',
    ctaRadius: '20px',
    checkColor: 'rgb(204, 204, 204)'
  });
  expect(design.ctaHeight).toBeCloseTo(52.4, 1);
  expect(design.notchShoulder).toContain('radial-gradient');
  const checks = card.locator('.download-checks svg');
  await expect(checks).toHaveCount(5);
  for (const check of await checks.all()) {
    await expect(check).toHaveAttribute('width', '24');
    await expect(check).toHaveAttribute('stroke-width', '1.5');
  }
  await card.getByRole('tab', { name: 'Getting started' }).click();
  await expect(card.getByRole('tablist')).toHaveAttribute('data-active', 'install');
  const tabs = card.locator('.download-tabs');
  const indicatorX = await tabs.evaluate((el) => (el.getBoundingClientRect().width - 2) / 2);
  await expect
    .poll(() =>
      tabs.evaluate((el) => new DOMMatrix(getComputedStyle(el, '::before').transform).m41)
    )
    .toBeCloseTo(indicatorX, 1);
  await expect(card.getByRole('tabpanel')).toContainText('not notarized');
});

for (const width of [1440, 834, 390, 320]) {
  test(`download gradient follows both card panels without a hard cutoff at ${width}px`, async ({
    page
  }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    const errors = await open(page);
    const section = page.locator('#download');
    const assertCoverage = async () => {
      const layout = await section.evaluate((el) => {
        const card = el.querySelector('.download-card').getBoundingClientRect();
        const backdrop = el.querySelector('.download-scenery');
        const gradient = backdrop.getBoundingClientRect();
        const style = getComputedStyle(backdrop);
        return {
          cardHeight: card.height,
          cardBottom: card.bottom,
          gradientHeight: gradient.height,
          gradientBottom: gradient.bottom,
          gradientLeft: gradient.left,
          gradientRight: gradient.right,
          fadeClearance: el.getBoundingClientRect().bottom - gradient.bottom,
          filter: style.filter,
          background: style.backgroundImage,
          pointerEvents: style.pointerEvents,
          overflow: document.documentElement.scrollWidth > innerWidth
        };
      });
      expect(layout.gradientHeight).toBeCloseTo(layout.cardHeight + 40, 1);
      expect(layout.gradientBottom).toBeCloseTo(layout.cardBottom - 20, 1);
      expect(layout.gradientLeft).toBeCloseTo(-60, 1);
      expect(layout.gradientRight).toBeCloseTo(width + 60, 1);
      expect(layout.fadeClearance).toBeGreaterThan(150);
      expect(layout.filter).toBe('blur(50px)');
      expect(layout.background).toContain('0deg');
      expect(layout.background).toContain('21.0902%');
      expect(layout.background).toContain('52.6658%');
      expect(layout.pointerEvents).toBe('none');
      expect(layout.overflow).toBe(false);
    };
    await assertCoverage();
    await section.getByRole('tab', { name: 'Getting started' }).click();
    await assertCoverage();
    await section.getByRole('tab', { name: 'The app' }).click();
    await assertCoverage();
    await expect(section.getByRole('link', { name: 'Download for macOS' })).toHaveAttribute(
      'href',
      dmg
    );
    expect(errors).toEqual([]);
  });
}
