# Ticket: Expose locale-scoped collections to templates (site drop)

Repo: dart_static_site_generator
Filed by: holotype_shop i18n integration
Status: done
Priority: high — blocks correct localized storefronts
Related: 001 (i18n builds), 003 (collection aggregation)

## Problem

Translated pages are collected into per-locale buckets (`shop@zh`), but the
site drop only exposes un-bucketed collections. Consequently, on a page whose
`page.locale` is `zh`, `site.shop.all` / `site.shop.blender.all` resolve to
the DEFAULT-locale pages. A localized storefront cannot render localized
product lists: zh home/shop pages show English product names linking to
English routes.

Observed in holotype_shop (config: default_locale en + locales en/zh, zh
content under content/zh/): build/zh/index.html sidebar lists "Audio
Lip-Sync Pro (Add-on)" etc. with href="/shop/..." instead of the zh
translations under /zh/shop/....

## Desired behavior

During rendering of a page with `locale == L`, collection lookups resolve
locale-scoped first and fall back to the default bucket:

- `site.shop` on an L-locale page = bucket `shop@L`; per-child lookups
  (`site.shop.blender`) = `blender@L`.
- A missing/empty locale bucket falls back to the default-locale bucket
  (avoids empty nav when only some content is translated — consumers choose
  per template whether to iterate `page.extras.alternates` for the rest).
- `.all`, `.count`, pagination and category archives behave consistently
  with the bucket actually used.

## Acceptance criteria

- i18n_test: a translated product page renders its locale's collection
  entries (zh title + /zh/... route) via `site.<name>.all`.
- Default-locale pages keep current behavior exactly.
- Mixed-translation fixture: pages without a translation fall back to the
  default-locale bucket rather than disappearing.
