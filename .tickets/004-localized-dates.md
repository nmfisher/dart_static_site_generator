# Ticket: Localized date rendering (page.long_date / formatted_date)

Repo: dart_static_site_generator
Filed by: holotype_shop i18n integration
Status: done
Priority: medium
Related: 001

## Problem

Ticket 001 specified localized date formatting for non-default locales, but
the implementation emits English formats regardless of locale: a zh news
article renders "July 15, 2026" in page.long_date on /zh/... pages.

## Desired behavior

- page.formatted_date / page.long_date render per the page's locale:
  en "July 15, 2026", zh-CN "2026年7月15日" (at minimum a hardcoded map for
  the configured locales; no intl dependency required).
- <time datetime=...> values stay ISO (already the case via formatted_date).

## Acceptance criteria

- i18n_test: a zh-dated page renders 2026年7月15日 in long_date.
- Default-locale output unchanged.
