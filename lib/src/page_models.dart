import 'dart:io';
import 'dart:math';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';


class PageModel {
  final String html;
  final String? layoutId; // Template specified in frontmatter
  final String? templateId; // Often derived from parent dir, used if layoutId missing
  final String title;
  final String route; // URL path
  final Map<String, String> metadata;
  final String markdown; // Original markdown content (after frontmatter)
  final DateTime? date;
  final String blurb; // Auto-generated summary
  final String source; // Original file path
  final bool draft;
  final bool isIndex; // Is this an auto-generated index page?

  PageModel(
      {required this.html,
      required this.title,
      required this.route,
      required this.markdown,
      required this.source,
      required this.blurb,
      this.draft = true,
      required this.metadata, // Make required
      this.layoutId,
      this.templateId,
      this.date,
      this.isIndex = false}) {
    if (route.isEmpty && !isIndex) { // Allow empty route for potential root index
       throw ArgumentError.value(route, 'route', "Route cannot be empty (source $source)");
    }
     if (title.isEmpty) {
      print("Warning: Page title is empty for source: $source");
    }
  }

  factory PageModel.from(File file, Directory baseDir) {
    final filePath = file.path;
    final content = file.readAsStringSync();
    final parts = content.split('---');

    if (parts.length < 3 || !content.startsWith('---')) {
      throw FormatException(
          "Invalid frontmatter format in $filePath. Expected '---' delimiters.");
    }

    final frontmatterContent = parts[1];
    final markdownContent = parts.skip(2).join('---').trim();

    dynamic doc;
    try {
      doc = loadYaml(frontmatterContent);
      if (doc == null || doc is! YamlMap) {
         throw FormatException("Frontmatter is not a valid YAML map in $filePath.");
      }
    } catch (e) {
      throw FormatException("Failed to parse YAML frontmatter in $filePath: $e\nContent:\n$frontmatterContent");
    }

    final layoutId = doc["layout"]?.toString();
    final templateId = doc["template"]?.toString();
    final title = doc["title"]?.toString() ?? p.basenameWithoutExtension(filePath);

    DateTime? date;
    if (doc["date"] != null) {
      try {
        // Attempt parsing - consider using DateFormat for more formats
        date = DateTime.parse(doc["date"].toString());
        // Example using intl (add dependency first):
        // date = DateFormat('yyyy-MM-dd HH:mm:ss').parse(doc["date"].toString());
      } catch (err) {
        print("Warning: Could not parse date '${doc["date"]}' in $filePath (expected ISO 8601 format): $err");
      }
    }

    final html = md.markdownToHtml(markdownContent, inlineSyntaxes: [md.InlineHtmlSyntax()]);
    final plainText = html.replaceAll(RegExp(r'<[^>]*>|\s{2,}'), ' ').trim(); // Strip tags and excessive whitespace
    final blurb = plainText.substring(0, min(plainText.length, 200)).trim();

     final metadata = <String, String>{
      "og:description": blurb,
      "og:title": title.replaceAll('"', '"'), // Use HTML entity for quotes
      "twitter:title": title.replaceAll('"', '"'),
      "twitter:description": blurb,
    };

    if (doc["meta"] != null && doc["meta"] is YamlMap) {
      try {
        for (final key in doc["meta"].keys) {
          metadata[key.toString()] = doc["meta"][key]?.toString() ?? '';
        }
      } catch (e) {
         print("Warning: Could not parse 'meta' section in frontmatter for $filePath: $e");
      }
    }

    var route = doc["url"]?.toString() ?? doc["route"]?.toString();

    if (route == null) {
      final relativePath = p.relative(filePath, from: baseDir.path);
      final pathSegments = p.split(p.withoutExtension(relativePath));

      // Sanitize segments for URL safety (basic example: replace space with -, remove unsafe chars)
      final sanitizedSegments = pathSegments.map((s) => s
        .replaceAll(' ', '-')
        .replaceAll(RegExp(r'[^\w\-\.~]'), '') // Keep word chars, -, ., ~, _
        .toLowerCase() // Normalize to lowercase
      ).toList();

      if (sanitizedSegments.last.toLowerCase() == "index") {
         sanitizedSegments.removeLast(); // Remove 'index' part
         if (sanitizedSegments.isEmpty) {
            route = '/'; // Root index
         } else {
            route = '/${sanitizedSegments.join('/')}';
         }
      } else {
         route = '/${sanitizedSegments.join('/')}';
      }
    }

    // Ensure leading slash, remove trailing slash if not root
    if (!route.startsWith('/')) {
      route = '/$route';
    }
    if (route != '/' && route.endsWith('/')) {
      route = route.substring(0, route.length - 1);
    }

    print("Parsed ${file.path} -> route: $route");

    return PageModel(
        html: html,
        source: filePath,
        layoutId: layoutId,
        templateId: templateId,
        title: title,
        route: route,
        date: date,
        blurb: blurb,
        markdown: markdownContent,
        metadata: metadata,
        draft: doc["published"] != true
    );
  }

  factory PageModel.index(
      Directory directory, Directory baseDirectory, List<PageModel> children) {
    var relativePath = p.relative(directory.path, from: baseDirectory.path);
    var pathSegments = p.split(relativePath).map((s) => s.toLowerCase()).toList();

    var fullpath = '/${pathSegments.join('/')}';
    if (fullpath != '/' && fullpath.endsWith('/')) {
      fullpath = fullpath.substring(0, fullpath.length - 1);
    }
    if (fullpath == '/.') {
        fullpath = '/';
    }

    var dirname = p.basename(directory.path);
    var title = dirname.isNotEmpty ? _capitalize(dirname) : 'Index';

    var indexConfigFile = File(p.join(directory.path, "config.yaml"));
    String? layoutId;
    Map<String, String> metadata = {};

    if (indexConfigFile.existsSync()) {
      try {
        var indexConfig = loadYaml(indexConfigFile.readAsStringSync()) as YamlMap;
        title = indexConfig["title"]?.toString() ?? title;
        layoutId = indexConfig["layout"]?.toString();
         if (indexConfig["meta"] != null && indexConfig["meta"] is YamlMap) {
           for (final key in indexConfig["meta"].keys) {
             metadata[key.toString()] = indexConfig["meta"][key]?.toString() ?? '';
           }
         }
      } catch (e) {
         print("Warning: Could not parse index config file ${indexConfigFile.path}: $e");
      }
    }

    metadata.putIfAbsent("og:title", () => title);
    metadata.putIfAbsent("og:description", () => "Index of $title");

    return PageIndexPageModel(
        html: "", // Index pages typically generate HTML via layout
        source: directory.path,
        title: title,
        route: fullpath,
        children: children,
        layoutId: layoutId ?? 'list', // Default layout for indexes
        metadata: metadata,
        blurb: "Index page for $title",
        draft: false, // Index pages are usually not drafts
        isIndex: true);
  }

      Map<String, dynamic> toMap() {
    return {
      'html': html,
      'layoutId': layoutId,
      'templateId': templateId,
      'title': title,
      'route': route,
      // CHANGE: Pass metadata directly as a Map
      'metadata': metadata,
      'date': date?.toIso8601String(),
      'blurb': blurb,
      'source': source,
      'draft': draft,
      'isIndex': isIndex,
    };
  }

   static String _capitalize(String s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}

class PageIndexPageModel extends PageModel {
  final List<PageModel> children;

  PageIndexPageModel(
      {required this.children,
      required super.source,
      required super.title,
      required super.route,
      required super.html,
      required super.metadata,
      required super.blurb,
      super.markdown = "",
      super.layoutId,
      super.templateId = "index",
      super.draft = false,
      super.isIndex = true,
      super.date}) {}


     @override
   Map<String, dynamic> toMap() {
     final map = super.toMap(); // Calls the modified PageModel.toMap()
     // Add children data, maybe sorted by date (descending)
     final sortedChildren = List<PageModel>.from(children)
        ..sort((a, b) {
            if (a.date == null && b.date == null) return 0;
            if (a.date == null) return 1; // Put pages without dates last
            if (b.date == null) return -1;
            return b.date!.compareTo(a.date!); // Newest first
        });
     map['children'] = sortedChildren
          .where((c) => !c.draft)
          .map((c) => c.toMap())
          .toList();
     return map;
   }

}