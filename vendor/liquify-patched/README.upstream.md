# Vendored liquify (patched)

`pubspec.yaml` overrides `liquify` with this directory while we carry two
local patches. Remove the `dependency_overrides` entry once upstream ships a
release containing the fix.

## Base

Files are from https://github.com/kingwill101/liquify at `4e4d2e9`
("make playground more useful"); the published 1.6.1 grammar
(`lib/src/grammar/shared.dart`) is byte-identical to that base. Upstream's
pub workspace nests the package at `pkgs/liquify/`; here it is flattened to
the directory root. A working clone of the upstream repo with the same
patches applied lives locally at `vendor/liquify/` (git-ignored) and is the
workspace for preparing the upstream PR.

## Patch: variable / expression keys in bracket access

`variable-key-bracket-access.patch` (paths prefixed `pkgs/liquify/` as in the
upstream workspace) — two complementary changes:

1. `lib/src/grammar/shared.dart` — `arrayAccess()`:
   `ref0(literal)` → `ref0(expression)`, so the bracket key slot accepts any
   expression (`{{ alternates[site.i18n.default.code] }}`). Shopify Liquid
   allows hash keys that are "an expression that resolves to a string";
   1.6.1 only parses literals and throws `ParsingException`.
2. `lib/src/evaluator/evaluator.dart` — in *both* sync and async
   `visitMemberAccess`, the array-access branch now evaluates the key node
   (`member.key.accept(this)` / `acceptAsync`) instead of casting it to
   `Literal`, and handles `List` (int index or `int.tryParse`) and `Map`
   (`containsKey`) explicitly, returning null otherwise. Previously a
   non-literal key could never resolve (hard cast), and the chain form
   `x.y[key]` only worked by accident.

## Upstream PR status

The same diff is intended for a PR to kingwill101/liquify. Status:
**not yet filed**.

## Verification at vendor time

- liquify's own suite (vendored + patched): **740 passed / 0 failed**.
- blog_builder suite: 145 passed / 0 failed (6 of them in
  `test/liquify_repro_test.dart` covering bracket access).
- `dart analyze`: clean on both packages.
