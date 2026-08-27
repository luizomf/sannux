#!/usr/bin/env node

const DEFAULT_TIMEOUT_MS = 20000;
const DEFAULT_RENDER_WAIT_MS = 2000;
const DEFAULT_MAX_TEXT_CHARS = 50000;
const DEFAULT_MAX_LINKS = 100;
const DEFAULT_NAVIGATION_ATTEMPTS = 2;
const MIN_READABLE_CHARS = 120;
const DEFAULT_CHROMIUM_PATH = "/usr/bin/chromium";

function numericEnv(name, fallback, min, max) {
  const rawValue = process.env[name];
  if (!rawValue) {
    return fallback;
  }

  const value = Number.parseInt(rawValue, 10);
  if (!Number.isFinite(value)) {
    return fallback;
  }

  return Math.min(Math.max(value, min), max);
}

function normalizeText(value) {
  return String(value ?? "")
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{4,}/g, "\n\n\n")
    .trim();
}

function capText(value, maxLength) {
  const text = normalizeText(value);
  if (text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, maxLength)}\n[truncated]`;
}

function printJson(result) {
  const output = {
    ok: Boolean(result.ok),
    url: result.url ?? "",
    final_url: result.final_url ?? "",
    title: result.title ?? "",
    text: result.text ?? "",
    links: Array.isArray(result.links) ? result.links : [],
    blocked_reason: result.blocked_reason ?? null,
  };

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

function failure(url, blockedReason, overrides = {}) {
  printJson({
    ok: false,
    url,
    final_url: overrides.final_url ?? url,
    title: overrides.title ?? "",
    text: overrides.text ?? "",
    links: overrides.links ?? [],
    blocked_reason: blockedReason,
  });
}

function parseRequestedUrl(rawUrl) {
  if (!rawUrl) {
    return { ok: false, blockedReason: "missing_url", url: "" };
  }

  let parsedUrl;
  try {
    parsedUrl = new URL(rawUrl);
  } catch {
    return { ok: false, blockedReason: "unsupported_url", url: rawUrl };
  }

  if (!["http:", "https:"].includes(parsedUrl.protocol)) {
    return { ok: false, blockedReason: "unsupported_url", url: rawUrl };
  }

  return { ok: true, url: parsedUrl.href };
}

function detectBlockedReason(status, title, text, finalUrl) {
  if ([401, 403, 429].includes(status)) {
    return "captcha_or_login";
  }

  try {
    const parsedFinalUrl = new URL(finalUrl);
    if (parsedFinalUrl.searchParams.has("js_challenge")) {
      return "captcha_or_login";
    }
  } catch {
    // Ignore URL parsing here; unsupported input is rejected before navigation.
  }

  const sample = `${title}\n${text.slice(0, 6000)}`.toLowerCase();
  const blockedPatterns = [
    /captcha/,
    /verify (that )?you are human/,
    /are you a human/,
    /robot check/,
    /unusual traffic/,
    /checking your browser/,
    /access denied/,
    /temporarily blocked/,
    /sign in to continue/,
    /log in to continue/,
    /login required/,
    /you must be logged in/,
    /enable cookies to continue/,
    /blocked by network security/,
    /file a ticket below/,
  ];

  return blockedPatterns.some((pattern) => pattern.test(sample))
    ? "captcha_or_login"
    : null;
}

function normalizeLinks(links, maxLinks) {
  const seen = new Set();
  const normalizedLinks = [];

  for (const link of links) {
    const url = normalizeText(link?.url);
    if (!url || seen.has(url)) {
      continue;
    }

    let parsedUrl;
    try {
      parsedUrl = new URL(url);
    } catch {
      continue;
    }

    if (!["http:", "https:"].includes(parsedUrl.protocol)) {
      continue;
    }

    seen.add(parsedUrl.href);
    normalizedLinks.push({
      text: capText(link?.text, 200),
      url: parsedUrl.href,
    });

    if (normalizedLinks.length >= maxLinks) {
      break;
    }
  }

  return normalizedLinks;
}

function errorLooksLikeTimeout(error) {
  const message = String(error?.message ?? "").toLowerCase();
  return error?.name === "TimeoutError" || message.includes("timeout");
}

async function gotoWithRetries(page, url, timeoutMs, maxAttempts) {
  let lastError;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await page.goto(url, {
        waitUntil: "domcontentloaded",
        timeout: timeoutMs,
      });
    } catch (error) {
      lastError = error;

      if (attempt < maxAttempts) {
        await page.waitForTimeout(500).catch(() => undefined);
      }
    }
  }

  throw lastError;
}

async function extractPage(page, maxLinks) {
  return page.evaluate((linkLimit) => {
    const clean = (value) =>
      String(value || "")
        .replace(/\s+/g, " ")
        .trim();

    const links = Array.from(document.querySelectorAll("a[href]"))
      .map((anchor) => ({
        text: clean(
          anchor.innerText ||
            anchor.getAttribute("aria-label") ||
            anchor.getAttribute("title") ||
            anchor.href,
        ),
        url: anchor.href,
      }))
      .filter((link) => link.url)
      .slice(0, linkLimit * 3);

    return {
      final_url: window.location.href,
      title: document.title || "",
      text: document.body?.innerText || "",
      links,
    };
  }, maxLinks);
}

async function main() {
  const parsedUrl = parseRequestedUrl(process.argv[2]);
  if (!parsedUrl.ok) {
    failure(parsedUrl.url, parsedUrl.blockedReason);
    return;
  }

  const timeoutMs = numericEnv(
    "BROWSER_FETCH_TIMEOUT_MS",
    DEFAULT_TIMEOUT_MS,
    1000,
    120000,
  );
  const renderWaitMs = numericEnv(
    "BROWSER_FETCH_RENDER_WAIT_MS",
    DEFAULT_RENDER_WAIT_MS,
    0,
    10000,
  );
  const maxTextChars = numericEnv(
    "BROWSER_FETCH_MAX_TEXT_CHARS",
    DEFAULT_MAX_TEXT_CHARS,
    1000,
    200000,
  );
  const maxLinks = numericEnv(
    "BROWSER_FETCH_MAX_LINKS",
    DEFAULT_MAX_LINKS,
    0,
    500,
  );
  const chromiumPath =
    process.env.BROWSER_FETCH_CHROMIUM_PATH || DEFAULT_CHROMIUM_PATH;
  const navigationAttempts = numericEnv(
    "BROWSER_FETCH_NAVIGATION_ATTEMPTS",
    DEFAULT_NAVIGATION_ATTEMPTS,
    1,
    5,
  );

  let browser;
  try {
    const { chromium } = await import("playwright-core");

    browser = await chromium.launch({
      executablePath: chromiumPath,
      headless: true,
      args: [
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--disable-extensions",
      ],
    });

    const context = await browser.newContext();
    const page = await context.newPage();
    page.setDefaultTimeout(timeoutMs);

    let response = null;
    let navigationError = null;
    try {
      response = await gotoWithRetries(
        page,
        parsedUrl.url,
        timeoutMs,
        navigationAttempts,
      );
    } catch (error) {
      navigationError = error;
    }

    if (renderWaitMs > 0) {
      await page
        .waitForLoadState("networkidle", { timeout: renderWaitMs })
        .catch(() => undefined);
    }

    const extracted = await extractPage(page, maxLinks);
    const status = response?.status() ?? null;
    const title = capText(extracted.title, 500);
    const text = capText(extracted.text, maxTextChars);
    const links = normalizeLinks(extracted.links, maxLinks);
    const finalUrl = extracted.final_url || page.url() || parsedUrl.url;
    const blockedReason = detectBlockedReason(status, title, text, finalUrl);

    if (navigationError && finalUrl.startsWith("chrome-error://")) {
      throw navigationError;
    }

    if (blockedReason) {
      failure(parsedUrl.url, blockedReason, {
        final_url: finalUrl,
        title,
        links,
      });
      return;
    }

    if (status !== null && status >= 400) {
      failure(parsedUrl.url, "browser_error", {
        final_url: finalUrl,
        title: title || `HTTP ${status}`,
        links,
      });
      return;
    }

    if (navigationError && text.length < MIN_READABLE_CHARS) {
      throw navigationError;
    }

    if (text.length < MIN_READABLE_CHARS) {
      failure(parsedUrl.url, "no_readable_content", {
        final_url: finalUrl,
        title,
        links,
      });
      return;
    }

    printJson({
      ok: true,
      url: parsedUrl.url,
      final_url: finalUrl,
      title,
      text,
      links,
      blocked_reason: null,
    });
  } catch (error) {
    failure(
      parsedUrl.url,
      errorLooksLikeTimeout(error) ? "timeout" : "browser_error",
    );
  } finally {
    if (browser) {
      await browser.close().catch(() => undefined);
    }
  }
}

await main();
