import 'package:blog_builder/src/page_models.dart';
import 'package:path/path.dart' as p;

class SiteData {
  final Map<String, dynamic> data = {};

  /// Template-facing collection payload (catalog). Called with the active
  /// page's locale code (null for the default locale / i18n off) so a page
  /// resolves locale-scoped collections first, falling back to the
  /// default-locale buckets (ticket 002).
  Map<String, dynamic> Function(String? locale)? extraData;
  final String name; // Name of the directory/collection/page
  final String route; // Full route of this node
  PageModel?
      page; // If this node represents a page (made non-final for assignment)
  final Map<String, SiteData> children; // Subdirectories/sub-collections
  final List<PageModel>
      pages; // Pages directly within this directory/collection

  SiteData({
    required this.name,
    required this.route,
    this.page,
    Map<String, SiteData>? children,
    List<PageModel>? pages,
  })  : children = children ?? {},
        pages = pages ?? [];

  // Method to convert to a Liquid-friendly map. Pass a locale to resolve
  // collections locale-scoped (ticket 002); omit it for the default view.
  Map<String, dynamic> toLiquidMap({String? locale}) {
    final Map<String, dynamic> map = {
      'name': name,
      'route': route,
    };

    if (page != null) {
      map.addAll(page!.toMap()); // Add page properties if this is a page node
    }

    // Add children (subdirectories/collections). On a page of locale L
    // (ticket 002), every top-level content subtree is resolved from the
    // locale-prefixed tree first (`site.shop` -> `/de/shop` subtree), so a
    // localized page sees its locale's collection entries. A subtree that is
    // missing or empty in the locale tree falls back to the default-locale
    // subtree; the locale node itself (site.de) stays untouched.
    final localeNode = locale == null ? null : _localeChild(locale);
    children.forEach((key, value) {
      if (localeNode != null && key == localeNode.key) {
        map[key] = value.toLiquidMap();
        return;
      }
      final localized = localeNode?.value.children[key];
      if (localized != null && localized.hasContent) {
        map[key] = localized.toLiquidMap();
        return;
      }
      map[key] = value.toLiquidMap();
    });

    // Add direct pages (e.g., site.posts.first_post)
    // Use the last segment of the route as the key, ensuring it's unique
    final Set<String> usedKeys = children.keys.toSet();
    for (final pModel in pages) {
      String pageKey = p.posix.basename(pModel.route);
      if (children[pageKey]?.page?.route == pModel.route) continue;
      if (pageKey.isEmpty) {
        // Handle root index page
        pageKey = 'index';
      }

      // Ensure uniqueness, append a number if necessary
      int counter = 1;
      String originalPageKey = pageKey;
      while (usedKeys.contains(pageKey)) {
        pageKey = '${originalPageKey}_$counter';
        counter++;
      }
      usedKeys.add(pageKey);
      final pageMap = pModel.toMap();
      map[pageKey] = pageMap;
    }

    // Add a special 'all' list for pages directly under this node, sorted by priority then date
    if (pages.isNotEmpty) {
      final sortedPages = _sortedPages();
      map['all'] = [for (final p in sortedPages) p.toMap()];
    }

    map.addAll(data);
    map.addAll(extraData?.call(locale) ?? {});
    return map;
  }

  /// The child node holding the locale-prefixed tree for [locale] (e.g. the
  /// `/de` node), matched case-insensitively against route segments, or null.
  MapEntry<String, SiteData>? _localeChild(String locale) {
    for (final entry in children.entries) {
      if (entry.key.toLowerCase() == locale.toLowerCase()) return entry;
    }
    return null;
  }

  /// Whether this subtree exposes anything to templates: direct pages, an
  /// own page (collection index) or any nested content.
  bool get hasContent =>
      pages.isNotEmpty ||
      page != null ||
      children.values.any((child) => child.hasContent);

  List<PageModel> _sortedPages() {
    int _parsePriority(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    final sortedPages = List<PageModel>.from(pages)
      ..sort((a, b) {
        // Sort by priority (lower = first) if present
        final aHasPri = a.extras.containsKey('priority');
        final bHasPri = b.extras.containsKey('priority');
        if (aHasPri && bHasPri) {
          final cmp = _parsePriority(a.extras['priority'])
              .compareTo(_parsePriority(b.extras['priority']));
          if (cmp != 0) return cmp;
        } else if (aHasPri) {
          return -1;
        } else if (bHasPri) {
          return 1;
        }
        // Fall back to date sorting (newest first)
        if (a.date == null && b.date == null)
          return a.route.compareTo(b.route);
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return b.date!.compareTo(a.date!);
      });
    return sortedPages;
  }
}
