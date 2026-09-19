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

## Conformance with Shopify Liquid

Square-bracket access with a non-literal key is documented and tested
behavior in the reference implementation:

- Official docs ([Liquid basics → Referencing handles](https://shopify.dev/docs/api/liquid/basics)):
  square-bracket notation "accepts a handle wrapped in quotes `'`, a Liquid
  variable, or an object reference".
- `Shopify/liquid` integration tests (`test/integration/variable_test.rb`):
  `{{ list[foo] }}` (variable key, Hash and Array targets), `{{ self[key] }}`
  (dynamic find var), and `{{ a[ self[ 'b' ] ] }}` (key that is itself a
  bracket expression) — the last is mirrored by the regression test
  "hash key can be a nested bracket expression".

The patch accepts any expression in the key slot, a slight superset of
Shopify's grammar (their parser restricts bracket keys to variables and
lookups); all documented forms behave identically.

## Upstream PR status

The same diff is intended for a PR to kingwill101/liquify. It currently
lives on the `fix/variable-key-bracket-access` branch of
https://github.com/nmfisher/liquify
([PR #1](https://github.com/nmfisher/liquify/pull/1) opens it against that
repo's master; the same branch can be pointed at kingwill101/liquify in a
follow-up PR). The branch adds four regression tests to
`pkgs/liquify/test/issues_test.dart` on top of the fix, including one
mirroring Shopify's nested-bracket test; the `.patch` file here includes
those tests.

## Verification at vendor time

- liquify's own suite (vendored + patched): **744 passed / 0 failed**
  (740 upstream + 4 new regression tests in `test/issues_test.dart`).
- blog_builder suite: 145 passed / 0 failed (6 of them in
  `test/liquify_repro_test.dart` covering bracket access).
- `dart analyze`: clean on both packages.
