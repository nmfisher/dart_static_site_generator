import 'package:blog_builder/src/page_models.dart';
import 'package:blog_builder/src/site_data_model.dart';
import 'package:test/test.dart';

/// Ticket 002: on a page of locale L, `site.<collection>` must resolve the
/// locale-prefixed subtree (`/L/<collection>`) first and fall back to the
/// default-locale subtree when the locale tree is missing or empty.
void main() {
  PageModel page(String title, String route, {String? locale}) => PageModel(
        title: title,
        route: route,
        source: 'memory:$route',
        rawMarkdown: '',
        blurb: '',
        metadata: const {},
        date: DateTime(2024, 1, 1),
        locale: locale,
      );

  SiteData leaf(PageModel p) => SiteData(name: p.route, route: p.route)
    ..page = p;

  /// root -> shop(a) / de -> shop(b, c[, empty])
  SiteData tree({
    List<PageModel> enShop = const [],
    List<PageModel> deShop = const [],
    bool deShopNode = true,
  }) {
    final shop = SiteData(name: 'shop', route: '/shop');
    for (final p in enShop) {
      shop.children[p.route] = leaf(p);
      shop.pages.add(p);
    }
    final de = SiteData(name: 'de', route: '/de');
    if (deShopNode) {
      final deShopNodeData = SiteData(name: 'shop', route: '/de/shop');
      for (final p in deShop) {
        deShopNodeData.children[p.route] = leaf(p);
        deShopNodeData.pages.add(p);
      }
      de.children['shop'] = deShopNodeData;
    }
    final root = SiteData(name: 'root', route: '/')
      ..children['shop'] = shop
      ..children['de'] = de;
    return root;
  }

  List<String> routes(Map<String, dynamic> node) =>
      (node['all'] as List).map((p) => p['route'] as String).toList();

  test('default view (no locale) is unchanged', () {
    final root = tree(enShop: [page('A', '/shop/a')], deShop: [
      page('B', '/de/shop/b'),
      page('C', '/de/shop/c')
    ]);
    final map = root.toLiquidMap();
    expect(routes(map['shop']), ['/shop/a']);
  });

  test('site.shop resolves the de subtree on de pages', () {
    final root = tree(enShop: [page('A', '/shop/a')], deShop: [
      page('B', '/de/shop/b'),
      page('C', '/de/shop/c')
    ]);
    final map = root.toLiquidMap(locale: 'de');
    expect(routes(map['shop']), ['/de/shop/b', '/de/shop/c']);
    // The locale node itself stays reachable.
    expect((map['de'] as Map)['route'], '/de');
  });

  test('site.shop falls back to the default subtree when the locale one '
      'is empty', () {
    final root =
        tree(enShop: [page('A', '/shop/a')], deShop: [page('B', '/de/shop/b')]);
    final deShop = root.children['de']!.children['shop']!;
    deShop.pages.clear();
    deShop.children.clear();
    expect(deShop.hasContent, isFalse);
    final map = root.toLiquidMap(locale: 'de');
    expect(routes(map['shop']), ['/shop/a']);
  });

  test('site.shop falls back to the default subtree when the locale one '
      'is missing', () {
    final root = tree(
      enShop: [page('A', '/shop/a')],
      deShop: [page('B', '/de/shop/b')],
      deShopNode: false,
    );
    final map = root.toLiquidMap(locale: 'de');
    expect(routes(map['shop']), ['/shop/a']);
  });

  test('nested lookups stay inside the resolved locale subtree', () {
    // /de/shop/blender (sub-collection) with a de product page.
    final root = tree(enShop: [page('A', '/shop/a')], deShop: []);
    final de = root.children['de']!;
    final deShop = SiteData(name: 'shop', route: '/de/shop');
    final blender = SiteData(name: 'blender', route: '/de/shop/blender');
    blender.pages.add(page('Blend', '/de/shop/blender/x', locale: 'de'));
    blender.children['/de/shop/blender/x'] =
        leaf(page('Blend', '/de/shop/blender/x', locale: 'de'));
    deShop.children['blender'] = blender;
    de.children['shop'] = deShop;

    final map = root.toLiquidMap(locale: 'de');
    final shop = map['shop'] as Map<String, dynamic>;
    expect(shop.containsKey('all'), isFalse); // no direct de product pages
    expect(routes(shop['blender']), ['/de/shop/blender/x']);
  });
}
