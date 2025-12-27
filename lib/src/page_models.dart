import 'dart:io';
import 'dart:math';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class PageModel {
  final String? layoutId; // Template specified in frontmatter
  final String?
      templateId; // Often derived from parent dir, used if layoutId missing
  final String title;
  final String route; // URL path
  final Map<String, String> metadata;
  final String rawMarkdown; // Original markdown content (after frontmatter)
  final DateTime? date;
  final String blurb; // Auto-generated summary
  final String source; // Original file path
  final bool draft;
  final bool isIndex; // Is this an auto-generated index page?
  String? renderedContent;

  PageModel(
      {required this.title,
      required this.route,
      required this.rawMarkdown,
      required this.source,
      required this.blurb,
      this.draft = true,
      required this.metadata,
      this.layoutId,
      this.templateId,
      this.date,
      this.isIndex = false}) {
    if (route.isEmpty && !isIndex) {
      throw ArgumentError.value(
          route, 'route', "Route cannot be empty (source $source)");
    }
    if (title.isEmpty) {
      print("Warning: Page title is empty for source: $source");
    }
  }

  factory PageModel.from(File file, Directory baseDir, {bool useFallbackMetaTags = false}) {
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
        throw FormatException(
            "Frontmatter is not a valid YAML map in $filePath.");
      }
    } catch (e) {
      throw FormatException(
          "Failed to parse YAML frontmatter in $filePath: $e\nContent:\n$frontmatterContent");
    }

    final layoutId = doc["layout"]?.toString();
    final templateId = doc["template"]?.toString();
    final title =
        doc["title"]?.toString() ?? p.basenameWithoutExtension(filePath);

    DateTime? date;
    if (doc["date"] != null) {
      try {
        date = DateTime.parse(doc["date"].toString());
      } catch (err) {
        print(
            "Warning: Could not parse date '${doc["date"]}' in $filePath (expected ISO 8601 format): $err");
      }
    }

    final tempHtmlForBlurb = md.markdownToHtml(markdownContent,
        inlineSyntaxes: [md.InlineHtmlSyntax()]);
    final plainText =
        tempHtmlForBlurb.replaceAll(RegExp(r'<[^>]*>|\s{2,}'), ' ').trim();
    final blurb = plainText.substring(0, min(plainText.length, 200)).trim();

    // Initialize metadata with title tags (always set)
    final metadata = <String, String>{
      "og:title": title.replaceAll('"', '"'),
      "twitter:title": title.replaceAll('"', '"'),
    };

    // Parse meta tags from frontmatter (these override defaults)
    if (doc["meta"] != null && doc["meta"] is YamlMap) {
      try {
        for (final key in doc["meta"].keys) {
          metadata[key.toString()] = doc["meta"][key]?.toString() ?? '';
        }
      } catch (e) {
        print(
            "Warning: Could not parse 'meta' section in frontmatter for $filePath: $e");
      }
    }

    // Apply fallback meta tags if enabled and not already specified
    if (useFallbackMetaTags) {
      // Use first paragraph for description if not specified
      if (!metadata.containsKey("og:description") || metadata["og:description"]!.isEmpty) {
        final firstPara = _extractFirstParagraph(markdownContent);
        if (firstPara != null) {
          metadata["og:description"] = firstPara;
        }
      }

      if (!metadata.containsKey("twitter:description") || metadata["twitter:description"]!.isEmpty) {
        // Use og:description if set, otherwise extract first paragraph
        if (metadata.containsKey("og:description") && metadata["og:description"]!.isNotEmpty) {
          metadata["twitter:description"] = metadata["og:description"]!;
        } else {
          final firstPara = _extractFirstParagraph(markdownContent);
          if (firstPara != null) {
            metadata["twitter:description"] = firstPara;
          }
        }
      }

      // Use first image for og:image if not specified
      if (!metadata.containsKey("og:image") || metadata["og:image"]!.isEmpty) {
        final firstImage = _extractFirstImage(markdownContent);
        if (firstImage != null) {
          metadata["og:image"] = firstImage;
        }
      }
    } else {
      // When fallback is disabled, use blurb as default description
      metadata.putIfAbsent("og:description", () => blurb);
      metadata.putIfAbsent("twitter:description", () => blurb);
    }

    var route = doc["url"]?.toString() ?? doc["route"]?.toString();

    if (route == null) {
      final relativePath = p.relative(filePath, from: baseDir.path);
      final pathSegments = p.split(p.withoutExtension(relativePath));

      final sanitizedSegments = pathSegments
          .map((s) => s
              .replaceAll(' ', '-')
              .replaceAll(RegExp(r'[^\w\-\.~]'), '')
              .toLowerCase())
          .toList();

      if (sanitizedSegments.last.toLowerCase() == "index") {
        sanitizedSegments.removeLast();
        if (sanitizedSegments.isEmpty) {
          route = '/';
        } else {
          route = '/${sanitizedSegments.join('/')}';
        }
      } else {
        route = '/${sanitizedSegments.join('/')}';
      }
    }

    if (!route.startsWith('/')) {
      route = '/$route';
    }
    if (route != '/' && route.endsWith('/')) {
      route = route.substring(0, route.length - 1);
    }

    print("Parsed ${file.path} -> route: $route");

    return PageModel(
        rawMarkdown: markdownContent,
        source: filePath,
        layoutId: layoutId,
        templateId: templateId,
        title: title,
        route: route,
        date: date,
        blurb: blurb,
        metadata: metadata,
        draft: doc["published"] != true);
  }

  factory PageModel.index(
      Directory directory, Directory baseDirectory, List<PageModel> children) {
    var relativePath = p.relative(directory.path, from: baseDirectory.path);
    var pathSegments =
        p.split(relativePath).map((s) => s.toLowerCase()).toList();

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
        var indexConfig =
            loadYaml(indexConfigFile.readAsStringSync()) as YamlMap;
        title = indexConfig["title"]?.toString() ?? title;
        layoutId = indexConfig["layout"]?.toString();
        if (indexConfig["meta"] != null && indexConfig["meta"] is YamlMap) {
          for (final key in indexConfig["meta"].keys) {
            metadata[key.toString()] =
                indexConfig["meta"][key]?.toString() ?? '';
          }
        }
      } catch (e) {
        print(
            "Warning: Could not parse index config file ${indexConfigFile.path}: $e");
      }
    }

    metadata.putIfAbsent("og:title", () => title);
    metadata.putIfAbsent("og:description", () => "Index of $title");

    return PageIndexPageModel(
        rawMarkdown:
            "",
        source: directory.path,
        title: title,
        route: fullpath,
        children: children,
        layoutId: layoutId ?? 'list',
        metadata: metadata,
        blurb: "Index page for $title",
        draft: false,
        isIndex: true);
  }

  factory PageModel.fromMap(Map<String, dynamic> data) {
    return PageModel(
      rawMarkdown: data['rawMarkdown'] ?? '',
      title: data['title'] ?? 'Untitled',
      route: data['route'] ?? '/',
      source: data['source'] ?? '/path/to/source.md',
      blurb: data['blurb'] ?? '',
      metadata: Map<String, String>.from(data['metadata'] ?? {}),
      date: data['date'],
      draft: data['draft'] ?? false,
      layoutId: data['layoutId'],
      templateId: data['templateId'],
      isIndex: data['isIndex'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'layoutId': layoutId,
      'templateId': templateId,
      'title': title,
      'route': route,
      'metadata': metadata,
      'date': date,
      'blurb': blurb,
      'source': source,
      'draft': draft,
      'isIndex': isIndex,
      'raw_markdown': rawMarkdown,
      'rendered_content': renderedContent,
    };
  }

  static String _capitalize(String s) =>
      s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);

  /// Extracts the first paragraph from markdown content for use as meta description
  static String? _extractFirstParagraph(String markdownContent) {
    if (markdownContent.trim().isEmpty) return null;

    // Convert markdown to HTML to get plain text
    final html = md.markdownToHtml(markdownContent,
        inlineSyntaxes: [md.InlineHtmlSyntax()]);

    // Strip HTML tags and clean up whitespace
    final plainText = html.replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (plainText.isEmpty) return null;

    // Split by paragraph breaks (double newlines or period followed by space)
    // Take the first meaningful paragraph
    final paragraphs = plainText.split(RegExp(r'\n\n|\. '));
    for (final para in paragraphs) {
      final cleaned = para.trim();
      // Return first paragraph with at least 20 characters
      if (cleaned.length >= 20) {
        // Limit to ~200 characters for meta description
        return cleaned.substring(0, min(cleaned.length, 200)).trim();
      }
    }

    // Fallback: return first 200 chars if no good paragraph found
    return plainText.substring(0, min(plainText.length, 200)).trim();
  }

  /// Extracts the first image URL from markdown content for use as og:image
  static String? _extractFirstImage(String markdownContent) {
    if (markdownContent.trim().isEmpty) return null;

    // Match markdown image syntax: ![alt](url)
    final markdownImageRegex = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
    final markdownMatch = markdownImageRegex.firstMatch(markdownContent);
    if (markdownMatch != null) {
      return markdownMatch.group(2)?.trim();
    }

    // Match HTML img tags: <img src="url" ... >
    final htmlImageRegex = RegExp("<img[^>]+src=[\"']([^\"']+)[\"']", caseSensitive: false);
    final htmlMatch = htmlImageRegex.firstMatch(markdownContent);
    if (htmlMatch != null) {
      return htmlMatch.group(1)?.trim();
    }

    return null;
  }
}

class PageIndexPageModel extends PageModel {
  final List<PageModel> children;

  PageIndexPageModel(
      {required this.children,
      required super.source,
      required super.title,
      required super.route,
      required super.metadata,
      required super.blurb,
      super.rawMarkdown = "",
      super.layoutId,
      super.templateId = "index",
      super.draft = false,
      super.isIndex = true,
      super.date});

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    final sortedChildren = List<PageModel>.from(children)
      ..sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return b.date!.compareTo(a.date!);
      });
    map['children'] =
        sortedChildren.where((c) => !c.draft).map((c) => c.toMap()).toList();
    return map;
  }
  
  factory PageIndexPageModel.fromMap(Map<String, dynamic> data) {
    final List<PageModel> children = [];
    if (data['children'] is List) {
      for (final childData in data['children']) {
        // If it's ALREADY a PageModel, add it directly.
        if (childData is PageModel) {
          children.add(childData);
        // If it's a map, construct a new PageModel from it.
        } else if (childData is Map<String, dynamic>) {
          children.add(PageModel.fromMap(childData));
        }
      }
    }

    return PageIndexPageModel(
      rawMarkdown: data['rawMarkdown'] ?? '',
      title: data['title'] ?? 'Untitled Index',
      route: data['route'] ?? '/',
      source: data['source'] ?? '/path/to/index/',
      blurb: data['blurb'] ?? '',
      metadata: Map<String, String>.from(data['metadata'] ?? {}),
      children: children,
      layoutId: data['layoutId'],
      templateId: data['templateId'],
      date: data['date'],
    );
  }
}