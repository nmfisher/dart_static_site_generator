# Ticket: Site string tables (site.strings) for UI copy i18n

Repo: dart_static_site_generator
Filed by: holotype_shop i18n integration
Status: done (top-level `strings:` config schema; see note at bottom)
Priority: medium (workaround exists; mechanism would remove ~20 inline
locale conditionals from consumer templates)
Related: 001

## Problem

Ticket 001 specified optional per-locale string tables (strings: {en:
strings/en.yaml, zh: strings/zh.yaml}) exposed to templates as
site.strings.<key>. Not implemented. Consumers with UI copy in shared
layouts (nav labels, buttons, modal text) currently duplicate copy inline:

    {% if page.locale == 'zh' %}商店{% else %}SHOP{% endif %}

holotype_shop already maintains canonical tables at blog/strings/{en,zh}.yaml
(42 keys, parity-checked) that are currently only documentation.

## Desired behavior

- Optional config (schema per ticket 001): locales.strings: {<locale>: <path>}.
- YAML tables exposed as site.strings (nested keys, e.g.
  site.strings.nav.shop).
- Missing key = build error (fail loud), per ticket 001's policy.

## Acceptance criteria

- i18n_test: zh page renders site.strings.nav.shop == 商店; en page renders
  SHOP; missing key fails the build with the key name in the error.
- Absent strings config: site.strings is simply undefined (no error).

## Implementation notes (as built)

- Config schema is top-level `strings: {<locale>: <path>}` (validated against
  `locales.items`), not the `locales.strings:` nesting sketched in ticket 001.
- Paths are resolved relative to the input root; missing file, invalid YAML,
  or non-map YAML are build errors naming the locale and path.
- `site.strings` exposes the nested table for the page's locale, falling back
  to the default locale's table when the page's locale has none. Without a
  `strings:` config the key is simply absent from `site`.
- Fail-loud validation scans every template under `<input>/templates/` before
  rendering: any `site.strings.<key>` reference missing from **any** loaded
  table fails the build, naming key, template, and locale.
- Tests: i18n_test.dart "site.strings renders locale string tables"
  (en SHOP / de Laden via layout), missing-key throwsA(isA<FormatException>()),
  absent-config leaves `site.strings` undefined and builds clean.
- README i18n section documents the config + fallback + fail-loud policy.
