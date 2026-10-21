import { expect, test } from '@playwright/test';

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

function featureDemo(page) {
  return page.locator('.feature-card .notchy').first();
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

test('full feature demo supports tabs, clipboard filters, timer, notes, shelf and Face Check', async ({
  page
}) => {
  const errors = await open(page);
  const demo = featureDemo(page);
  await demo.getByRole('tab', { name: 'Home' }).focus();
  await page.keyboard.press('ArrowRight');
  await expect(demo.getByRole('tab', { name: 'Shelf' })).toHaveAttribute('aria-selected', 'true');
  await expect(demo.getByRole('tab', { name: 'Shelf' })).toBeFocused();
  await page.keyboard.press('ArrowLeft');
  await expect(demo.getByRole('tab', { name: 'Home' })).toBeFocused();
  for (const name of ['Stats', 'AI tools', 'Clipboard']) {
    await demo.getByRole('tab', { name, exact: true }).click();
    await expect(demo.getByRole('tabpanel', { name, exact: true })).toBeVisible();
  }
  await expect(demo.getByRole('button', { name: 'All', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await expect(demo.locator('.clip-card')).toHaveCount(6);
  await demo.getByRole('button', { name: 'Code', exact: true }).click();
  await expect(demo.getByText('1 clip', { exact: true })).toBeVisible();
  await expect(demo.locator('.clip-card')).toHaveCount(1);
  await expect(demo.locator('.clip-card')).toContainText('island');
  await expect(demo.getByRole('button', { name: 'Code', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await expect(demo.getByRole('button', { name: 'All', exact: true })).toHaveAttribute(
    'aria-pressed',
    'false'
  );

  await demo.getByRole('tab', { name: 'Timer' }).click();
  await demo.getByRole('button', { name: 'Start timer' }).click();
  await expect(demo.getByRole('button', { name: 'Pause', exact: true })).toBeVisible();
  await expect(demo.getByRole('timer')).not.toHaveText('25:00');
  await demo.getByRole('button', { name: 'Pause', exact: true }).click();
  await expect(demo.getByRole('button', { name: 'Resume', exact: true })).toBeVisible();
  await demo.getByRole('button', { name: 'Reset timer' }).click();
  await expect(demo.getByRole('timer')).toHaveText('25:00');

  await demo.getByRole('tab', { name: 'Notes' }).click();
  const note = demo.getByRole('textbox');
  await note.fill('Keep this note');
  await demo.getByRole('tab', { name: 'Home' }).click();
  await demo.getByRole('tab', { name: 'Notes' }).click();
  await expect(note).toHaveValue('Keep this note');

  await demo.getByRole('tab', { name: 'Shelf' }).click();
  await demo.getByRole('button', { name: 'Add demo file' }).click();
  await expect(demo.getByRole('button', { name: 'Remove Idea 1.txt' })).toBeVisible();
  await demo.getByRole('button', { name: 'Remove Idea 1.txt' }).click();
  await expect(demo.getByRole('button', { name: 'Remove Idea 1.txt' })).toHaveCount(0);
  await demo.getByRole('button', { name: 'Quick Look Brief.pdf' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toBeHidden();

  await demo.getByRole('tab', { name: 'Face Check' }).click();
  await demo.getByRole('button', { name: 'Simulate Face Check' }).click();
  await expect(demo.getByRole('button', { name: 'Simulating scan…' })).toBeDisabled();
  await expect(demo.getByRole('tabpanel').getByRole('status')).toHaveText(
    'Demo success. No face data was captured.'
  );
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

test('live activities switch sample status and playback controls', async ({ page }) => {
  const errors = await open(page);
  const live = page.getByRole('region', { name: 'Interactive live activity preview' });
  await live.getByRole('button', { name: 'Pause music', exact: true }).click();
  await expect(live.getByRole('button', { name: 'Play music', exact: true })).toHaveAttribute(
    'aria-pressed',
    'false'
  );
  for (const [name, value] of [
    ['Downloads', '72%'],
    ['Headphones', '82%'],
    ['Charging', '84%'],
    ['Focus', 'Deep Work'],
    ['Camera', 'In use'],
    ['AI context', '19%'],
    ['Timer', '24:18']
  ]) {
    await live.getByRole('button', { name, exact: true }).click();
    await expect(live.getByRole('button', { name, exact: true })).toHaveAttribute(
      'aria-pressed',
      'true'
    );
    await expect(live.locator('.notch-copy strong')).toHaveText(value);
  }
  await live.getByRole('button', { name: 'Start timer', exact: true }).click();
  await expect(live.getByText('Pomodoro timer is running')).toBeVisible();
  await live.getByRole('button', { name: 'Pause timer', exact: true }).click();
  await expect(live.getByRole('button', { name: 'Start timer', exact: true })).toHaveAttribute(
    'aria-pressed',
    'false'
  );
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
    const demo = featureDemo(page);
    await demo.getByRole('tab', { name: 'Home', exact: true }).click();
    await demo.getByRole('button', { name: 'Play sample playback' }).click();
    await expect(demo.locator('.equalizer i').first()).toHaveCSS('animation-name', 'none');
    await expect(demo.getByRole('tab', { name: 'Home', exact: true })).toHaveCSS(
      'transition-duration',
      '0s'
    );
    expect(
      await page
        .locator('#top')
        .evaluate((el) => getComputedStyle(el).getPropertyValue('--hero-progress').trim())
    ).toBe('0');
    await expect(page.locator('.live-activities .equalizer').first()).toHaveCSS('display', 'none');
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
  const live = page.getByRole('region', { name: 'Interactive live activity preview' });
  await live.getByRole('button', { name: 'Pause music', exact: true }).click();
  await expect(live.locator('.equalizer i').first()).toHaveCSS('animation-play-state', 'paused');
  await page.getByRole('button', { name: 'Pause decorative motion' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-motion', 'paused');
  await expect(page.locator('.feature-card').first()).toHaveCSS('opacity', '1');
  await expect(page.locator('.feature-card').first()).toHaveCSS('transition-duration', '0s');
  await page.getByRole('button', { name: 'Resume decorative motion' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-motion', 'running');
});

test('hero keeps its measured scene scale and supports native-icon clip interactions', async ({
  page
}) => {
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
  const hero = page.getByRole('region', { name: 'Interactive clipboard shelf preview' });
  await hero.getByRole('button', { name: /^Code \d/ }).click();
  await expect(hero.locator('button.card')).toHaveCount(1);
  await hero.getByRole('searchbox', { name: 'Search sample clips' }).fill('no-sample-can-match');
  await expect(hero.locator('.empty')).toBeVisible();
  await hero.getByRole('button', { name: 'Show all', exact: true }).click();
  await expect(hero.locator('button.card')).toHaveCount(8);
  await hero.getByRole('button', { name: 'Compact view', exact: true }).click();
  await expect(hero.getByRole('button', { name: 'Compact view', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await hero.locator('button.card').first().click();
  await expect(hero.getByRole('status')).toContainText('Sample selected');
  expect(await hero.locator('img[src^="/assets/macos/"]').count()).toBeGreaterThan(4);
  const icon = await page.request.get('/assets/macos/finder.png');
  expect(icon.ok()).toBeTruthy();
  expect(icon.headers()['content-type']).toContain('image/png');
});

test('audience cards use six crisp vector icons in reference-sized badges', async ({ page }) => {
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

test('download card matches the reference surface, notch, tabs and checks', async ({ page }) => {
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
