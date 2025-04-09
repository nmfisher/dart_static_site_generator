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
      // It's better to enforce '/' for the root index explicitly
       throw Exception("Route cannot be empty (source $source)");
    }
     if (title.isEmpty) {
      print("Warning: Page title is empty for source: $source");
      // Consider throwing an error if title is mandatory
    }
  }

  ///
  /// Parse a Markdown (.md) file.
  ///
  factory PageModel.from(File file, Directory baseDir) {
    final filePath = file.path;
    final content = file.readAsStringSync();
    final parts = content.split('---');

    if (parts.length < 3 || !content.startsWith('---')) {
      throw Exception(
          "Invalid frontmatter format in $filePath. Expected '---' delimiters.");
    }

    final frontmatterContent = parts[1];
    final markdownContent = parts.skip(2).join('---').trim();

    dynamic doc;
    try {
      doc = loadYaml(frontmatterContent);
      if (doc == null || doc is! YamlMap) {
         throw Exception("Frontmatter is not a valid YAML map.");
      }
    } catch (e) {
      throw Exception("Failed to parse YAML frontmatter in $filePath: $e\nContent:\n$frontmatterContent");
    }


    final layoutId = doc["layout"]?.toString();
    // Default templateId to parent directory name, unless overridden
    final templateId = doc["template"]?.toString();

    final title = doc["title"]?.toString() ?? p.basenameWithoutExtension(filePath); // Fallback title
    if (title.isEmpty){
        print("Warning: Determined title is empty for $filePath");
    }

    DateTime? date;
    if (doc["date"] != null) {
      try {
        // Try parsing common formats
        date = DateTime.parse(doc["date"].toString());
      } catch (err) {
        print("Warning: Could not parse date '${doc["date"]}' in $filePath: $err");
      }
    }

    final html = md.markdownToHtml(markdownContent, inlineSyntaxes: [md.InlineHtmlSyntax()]); // Allow inline HTML
    final plainText = html.replaceAll(RegExp(r'<[^>]*>'), ''); // Strip HTML tags

    final normalizedText = plainText.replaceAll(RegExp(r'\s+'), ' '); // Normalize whitespace FIRST
    final blurb = normalizedText.substring(0, min(normalizedText.length, 200)).trim(); // Calculate min/substring AFTER normalization

    // Default metadata
     final metadata = <String, String>{
      "og:description": blurb,
      "og:title": title.replaceAll('"', '"'), // Basic escaping
      "twitter:title": title.replaceAll('"', '"'),
      "twitter:description": blurb,
    };


    // Add frontmatter metadata, overwriting defaults if necessary
    if (doc["meta"] != null && doc["meta"] is YamlMap) {
      try {
        for (final key in doc["meta"].keys) {
          metadata[key.toString()] = doc["meta"][key]?.toString() ?? '';
        }
      } catch (e) {
         print("Warning: Could not parse 'meta' section in frontmatter for $filePath: $e");
      }
    }

    // Determine the route/URL
    var route = doc["url"]?.toString() ?? doc["route"]?.toString();

    if (route == null) {
      // Auto-generate route based on file path relative to baseDir
      final relativePath = p.relative(filePath, from: baseDir.path);
      if (p.basename(filePath).toLowerCase() == "index.md") {
        // /content/posts/index.md -> /posts
        // /content/index.md -> /
        route = p.dirname(relativePath);
        // Handle root index.md
        if (route == '.') route = '/';
        else route = '/$route'; // Add leading slash
      } else {
        // /content/posts/my-post.md -> /posts/my-post
         route = '/${p.withoutExtension(relativePath)}';
      }
      // Normalize path separators
      route = route.replaceAll(r'\', '/');
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
        draft: doc["published"] != true // Default to draft if 'published: true' is not set
        );
  }

  ///
  /// Creates a PageModel representing the "index" for a number of sub-pages (e.g. the "Articles" page for a blog)
  /// Note: This specific implementation isn't used by the main build loop below,
  /// but could be used for custom index generation logic.
  ///
  factory PageModel.index(
      Directory directory, Directory baseDirectory, List<PageModel> children) {
    var fullpath = '/${p.relative(directory.path, from: baseDirectory.path)}'.replaceAll(r'\', '/');
     if (fullpath != '/' && fullpath.endsWith('/')) {
      fullpath = fullpath.substring(0, fullpath.length - 1);
    }
     if (fullpath == '/.') { // Handle root case
        fullpath = '/';
     }


    var dirname = p.basename(directory.path);
    var title = dirname.isNotEmpty ? dirname[0].toUpperCase() + dirname.substring(1) : 'Index'; // Default title

    var indexConfigFile = File(p.join(directory.path, "config.yaml")); // Look for config.yaml for index page overrides

    String? layoutId;
    Map<String, String> metadata = {};

    if (indexConfigFile.existsSync()) {
      try {
        var indexConfig = loadYaml(indexConfigFile.readAsStringSync()) as YamlMap;
        title = indexConfig["title"]?.toString() ?? title;
        layoutId = indexConfig["layout"]?.toString(); // Allow specifying layout for index
         if (indexConfig["meta"] != null && indexConfig["meta"] is YamlMap) {
           for (final key in indexConfig["meta"].keys) {
             metadata[key.toString()] = indexConfig["meta"][key]?.toString() ?? '';
           }
         }
      } catch (e) {
         print("Warning: Could not parse index config file ${indexConfigFile.path}: $e");
      }
    }

    // Provide default metadata if needed
    metadata.putIfAbsent("og:title", () => title);
    metadata.putIfAbsent("og:description", () => "Index of $title");


    return PageIndexPageModel(
        html: "", // No direct HTML content for generated index
        source: directory.path, // Source is the directory itself
        title: title,
        route: fullpath,
        children: children,
        layoutId: layoutId, // Use layout from config if available
        metadata: metadata, blurb: '');
  }

   // Helper to convert PageModel data to a Map for template rendering
   Map<String, dynamic> toMap() {
     return {
       'html': html, // The core HTML content generated from markdown
       'layoutId': layoutId,
       'templateId': templateId,
       'title': title,
       'route': route,
       'metadata': metadata,
       // 'markdown': markdown, // Usually not needed in template
       'date': date?.toIso8601String(), // Format date for template
       'blurb': blurb,
       'source': source,
       'draft': draft,
       'isIndex': isIndex,
       // Add other fields as needed
     };
   }
}

class PageIndexPageModel extends PageModel {
  final List<PageModel> children;

  PageIndexPageModel(
      {required this.children,
      required super.source,
      required super.title,
      required super.route,
      required super.html, // Usually empty
      required super.metadata,
      super.markdown = "",
      super.layoutId,
      super.templateId = "index", // Default template for index pages
      super.draft = false,
      super.isIndex = true, required super.blurb}) {}


   @override
   Map<String, dynamic> toMap() {
     final map = super.toMap();
     // Add children data, maybe sorted or filtered
     map['children'] = children
          .where((c) => !c.draft) // Example: only show published children
          .map((c) => c.toMap()) // Convert children to maps too
          .toList();
     return map;
   }

}
