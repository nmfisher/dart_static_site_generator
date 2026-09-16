import 'package:blog_builder/src/page_models.dart';
import 'package:path/path.dart' as p;

class SiteData {
  final Map<String, dynamic> data = {};
  Map<String, dynamic> Function()? extraData;
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

  // Method to convert to a Liquid-friendly map
  Map<String, dynamic> toLiquidMap() {
    final Map<String, dynamic> map = {
      'name': name,
      'route': route,
    };

    if (page != null) {
      map.addAll(page!.toMap()); // Add page properties if this is a page node
    }

    // Add children (subdirectories/collections)
    children.forEach((key, value) {
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
      map['all'] = sortedPages.map((p) {
        final m = p.toMap();
        return m;
      }).toList();
    }

    map.addAll(data);
    map.addAll(extraData?.call() ?? {});
    return map;
  }
}
