import 'package:blog_builder/src/page_models.dart';
import 'package:path/path.dart' as p;

class SiteData {
  final String name; // Name of the directory/collection/page
  final String route; // Full route of this node
  PageModel? page; // If this node represents a page (made non-final for assignment)
  final Map<String, SiteData> children; // Subdirectories/sub-collections
  final List<PageModel> pages; // Pages directly within this directory/collection

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
      String pageKey = p.basenameWithoutExtension(pModel.route);
      if (pageKey.isEmpty) { // Handle root index page
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
      map[pageKey] = pModel.toMap();
    }

    // Add a special 'all' list for pages directly under this node, sorted by date
    if (pages.isNotEmpty) {
      final sortedPages = List<PageModel>.from(pages)
        ..sort((a, b) {
          if (a.date == null && b.date == null) return 0;
          if (a.date == null) return 1;
          if (b.date == null) return -1;
          return b.date!.compareTo(a.date!); // Newest first
        });
      map['all'] = sortedPages.map((p) => p.toMap()).toList();
    }

    return map;
  }
}
