# Ticket: Locale-aware (i18n) builds — per-locale pass with /zh/ prefix

Repo: dart_static_site_generator
Requested by: holotype_shop (Chinese storefront project, zh-CN)
Status: proposed
Priority: high (blocks storefront i18n work)

## Context

holotype_shop builds its site with this generator:

    dart run bin/blog_builder.dart -i blog -o build [-w]

Input tree: `config.yaml` (site config), `content/**/*.md` (markdown +
frontmatter), `templates/**.liquid` (layouts/includes), `assets/` (static).
Output: flat static site in `build/` + generated `sitemap.xml`; the consumer
copies `build/404/index.html` to `build/404.html` for Cloudflare's
not_found_handling.

To add a Simplified Chinese version of the shop, holotype_shop needs the whole
site rendered **once per locale** so templates (which iterate `site.shop.all`,
nav product lists, "More products", etc.) work unchanged inside each locale.

Chosen URL strategy: **path prefix** — English stays at `/` (default locale),
Chinese at `/zh/...`, same domain.

## Goals

1. A `locales` config block that turns on multi-locale builds; absence of the
   block must produce byte-identical behavior to today (zero regression risk
   for existing single-locale users).
2. Per-locale content roots: `content/zh/...` mirrors `content/...` 1:1.
3. Template-visible locale APIs so holotype_shop's Liquid templates need no
   structural changes.

## Non-goals

- Content translation (done in holotype_shop repo).
- Auto language negotiation / redirects (handled client-side there).
- More than two locales, but design must not assume exactly two.

## Requirements

### 1. Config schema (`config.yaml`)

    locales:
      default: en
      items:
        en:
          prefix: ""            # no prefix, routes unchanged
          html_lang: en
        zh:
          prefix: /zh
          html_lang: zh-CN
      strings:
        en: strings/en.yaml     # optional string tables
        zh: strings/zh.yaml

- No `locales:` block ⇒ single-locale build exactly as today.
- `baseUrl` stays global; locale-prefixed URLs are `baseUrl + prefix + route`.

### 2. Per-locale build pass

- Run the existing pipeline once per locale with a **locale-scoped content
  root**: locale `zh` reads `content/zh/`, locale `en` reads `content/`.
- Output layout: `build/<prefix>/...` (en → `build/`, zh → `build/zh/`).
- Collections (`site.shop`, `site.shop.<category>`, news, etc.) must resolve
  per locale — `site.shop.all` inside the zh pass yields only zh products.
- **Missing-page policy: omit.** If `content/zh/shop/x.md` doesn't exist, the
  zh build simply has no page at that route and it disappears from zh nav and
  collections. No fallback-rendering of English pages into the zh build (avoids
  mixed-language pages and half-localized nav).
- Frontmatter is per-file; nothing is inherited across locales.
- `assets/` are copied once to `build/assets/` (shared; not duplicated under
  each locale).

### 3. Template API additions

- `page.lang` — locale code; used for `<html lang="...">`.
- `page.locale_prefix` — `""` or `/zh` (for hand-built links in JS/inline code).
- `page.translations` — map of locale → URL of the equivalent page in the other
  locale, computed by matching the content path **after stripping the locale
  dir** (`content/shop/x.md` ↔ `content/zh/shop/x.md`). Entries only exist for
  locales where the counterpart page exists. Used for the language switcher.
- `site.strings` — the locale's string table, flat keys
  (`site.strings.nav.shop`, `site.strings.product.buy_full`...). Missing key ⇒
  build error (fail loud, not silent English).
- Localized dates: keep `page.formatted_date` / `page.long_date` but localize
  per locale (`2026年7月15日` for zh-CN). Locale→format mapping internal to the
  generator; hardcode zh-CN + en formats, no intl package dependency required.

### 4. Head/SEO support

- Sitemap: single `build/sitemap.xml` listing **all locales**, each `<url>` with
  `xhtml:link rel="alternate" hreflang` entries for existing counterparts
  (`en`, `zh-CN`, plus `x-default` → default-locale URL). `lastmod` from the
  page's own source file. (holotype_shop's head.liquid will also emit per-page
  hreflang `<link>`s from `page.translations` — generator only needs to keep
  `page.translations` correct.)

### 5. 404

- Each locale still emits its own `404/index.html` (from that locale's
  `content/404.md`) so `/zh/404/` exists. Site-wide fallback
  (`build/404.html`) remains the default locale's — the hosting layer picks one
  file; nothing to do in the generator beyond not breaking the existing
  `build/404/index.html` path.

### 6. Watch mode (`-w`)

- Rebuild pass(es) for affected locale(s); adding/removing a file under
  `content/zh/` must trigger the zh pass. Simple approach acceptable: rebuild
  all locales on any change.

### 7. Acceptance criteria

- Existing holotype_shop build with no `locales` block: output diff vs. today
  is empty (modulo timestamps).
- With locales enabled: every en route exists unchanged; `/zh/` mirror routes
  exist for every translated page; no route collisions between locales;
  sitemap validates with hreflang alternates; nav/collection loops inside zh
  pages list only zh pages.
- `page.translations` round-trips: en page links to zh page and vice versa.
- Small golden-file test: 2-locale fixture site (one translated page, one
  en-only page, one shared asset) asserting output tree + sitemap.

## Open questions

- String tables: YAML in the site repo (`blog/strings/*.yaml`) vs. a
  `strings:` section inside `config.yaml`? Leaning YAML files (they'll hold
  ~40 UI strings and will grow).
- Should locale-prefixed routes normalize trailing slashes differently for CJK
  slugs? (holotype_shop keeps ASCII slugs for zh pages, so likely moot — but
  generator should not assume ASCII.)
