# Ticket: site.<collection>.all must aggregate nested sub-collections

Repo: dart_static_site_generator
Filed by: holotype_shop i18n integration
Status: done
Priority: high — silent output regression for existing sites
Related: 002

## Problem

On a site with content/shop/{holotype.md, blender/*.md, unreal/*.md},
`site.shop.all` lists only direct children (holotype.md); nested products
are reachable only via site.shop.blender.all / site.shop.unreal.all.

holotype_shop had just broadened its templates from site.shop.blender.all to
site.shop.all (to include a new unreal product + desktop app); after pulling
the new generator the EN shop browser and "More products" lists dropped from
4 products to 1 — silently, no build error.

## Required fix (spec-conformant aggregation, option A)

Restore aggregation in the site drop: `site.<parent>.all` = the parent's
direct pages **plus every page in nested sub-directories**, recursively.
Child drops stay exclusive (each child's `all` remains its own pages only);
a page that appears in a child drop must not be dropped from the parent.

This is the option A behaviour the consumer asked for, and it matches the
Liquid/SSG conventions this generator's drop API follows:

- **Vendored liquify (vendor/liquify-patched, 1.6.1) imposes nothing here.**
  Its `Drop` class is a generic attribute container (`attrs` +
  `liquidMethodMissing`, vendor/liquify-patched/lib/src/drop.dart); there is
  no collection type and no aggregation rule in the engine. The semantics of
  `site.<collection>` are entirely this repo's data contract, so the engine
  cannot contradict this change.
- **Shopify Liquid (upstream Shopify/liquid) is deliberately
  data-agnostic**: the engine is "stateless ... render ... passing in a hash
  with local variables and objects" (Shopify/liquid README), and collection
  objects are host-supplied data. Where Shopify's own platform does define
  collection semantics, the `all_*` convention means "the complete set":
  `collection.all_products_count` — "The total number of products in a
  collection. This includes products that have been filtered out of the
  current view." (shopify.dev/docs/api/liquid/objects/collection). A parent
  collection drop exposing an `all` subset is therefore contrary to the
  `all_*` convention the name invokes.
- **Jekyll**, whose `site.<thing>` drop conventions this generator's
  directory drops follow, treats a collection as one flat recursive group:
  sub-directories never become sub-collections, and `Collection#entries`
  globs `["**", "*"]` — every descendant document is a member of the
  collection (jekyll/jekyll lib/jekyll/collection.rb). Aggregation is the
  norm, not the exception.
- **Repo history**: the pre-i18n tree (`bd1f0eb`, "Add safe builds...") had
  the same direct-children-only route-tree `all` while the catalog
  (`site.collections.<name>.all`) aggregated descendants by path prefix, so
  consumer templates written against the catalog/aggregate view broke when
  pointed at the bare drop. Restoring aggregation in the route-tree drop
  removes the undocumented inconsistency between the two surfaces.

## Acceptance criteria

- Regression test: fixture with nested collection dirs asserts
  site.<parent>.all contents (parent + descendants) and that child drops
  stay exclusive.
- README documents the aggregation rule in the i18n/migration section.
