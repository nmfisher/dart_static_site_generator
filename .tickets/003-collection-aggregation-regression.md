# Ticket: site.<collection>.all no longer aggregates nested sub-collections

Repo: dart_static_site_generator
Filed by: holotype_shop i18n integration
Status: proposed
Priority: high — silent output regression for existing sites
Related: 002

## Problem

Before the i18n commit (liquify/bucket rework), `site.shop.all` on a site
with content/shop/{holotype.md, blender/*.md, unreal/*.md} listed ALL
products (holotype + blender children + unreal children). After the i18n
commit, `site.shop.all` lists only direct children (holotype.md); nested
products are reachable only via site.shop.blender.all / site.shop.unreal.all.

holotype_shop had just broadened its templates from site.shop.blender.all to
site.shop.all (to include a new unreal product + desktop app); after pulling
the new generator the EN shop browser and "More products" lists dropped from
4 products to 1 — silently, no build error.

If the old aggregate behavior was intentional-but-fragile, fine — but the
change is undocumented and breaks existing consumers. Either:

## Options

A. Restore aggregation: parent collection drops merge descendant pages
   (document the rule: parent .all = direct children + all descendants,
   child drops stay exclusive).
B. Keep strict scoping and document it as a breaking change in the README
   migration notes; consumers iterate child drops explicitly.

holotype_shop's preference is A (matches pre-i18n behavior our templates
were built against, and matches what the shop browser layout assumes).

## Acceptance criteria

- Regression test: fixture with nested collection dirs asserts
  site.<parent>.all contents before/after.
- README documents whichever semantics are chosen, in the i18n/migration
  section.
