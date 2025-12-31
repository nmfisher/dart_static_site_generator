// lib/src/webp_html_processor.dart
import 'package:file/file.dart';
import 'package:path/path.dart' as path;

/// Tracks WebP conversions and replaces image references in HTML
class WebPHtmlProcessor {
  final Map<String, String> _webpMappings = {}; // Original path -> WebP path
  final FileSystem fileSystem;

  WebPHtmlProcessor({required this.fileSystem});

  /// Register a WebP conversion
  void registerWebPConversion(String originalPath, String webpPath) {
    _webpMappings[originalPath] = webpPath;
  }

  /// Check if a file has a WebP version available
  bool hasWebPVersion(String imagePath) {
    // Remove any leading slashes for consistent lookup
    final normalizedPath = path.normalize(imagePath.startsWith('/')
        ? imagePath.substring(1)
        : imagePath);
    return _webpMappings.containsKey(normalizedPath);
  }

  /// Get the WebP path for an image
  String? getWebPPath(String imagePath) {
    // Remove any leading slashes for consistent lookup
    final normalizedPath = path.normalize(imagePath.startsWith('/')
        ? imagePath.substring(1)
        : imagePath);
    return _webpMappings[normalizedPath];
  }

  /// Process HTML content to replace img tags with picture elements where WebP is available
  String processHtml(String html, {String basePath = ''}) {
    var result = html;

    _webpMappings.forEach((originalPath, webpPath) {
      // Look for img tags with the original image src (both quote styles, with or without leading slash)
      final patterns = [
        'src="$originalPath"',
        "src='$originalPath'",
        'src="/$originalPath"',
        "src='/$originalPath'",
      ];

      // Keep replacing until no more matches are found
      var searchStart = 0;
      while (searchStart < result.length) {
        // Find the next img tag
        final imgTagStart = result.indexOf('<img', searchStart);
        if (imgTagStart == -1) break;

        final imgTagEnd = result.indexOf('>', imgTagStart);
        if (imgTagEnd == -1) break;

        final imgTag = result.substring(imgTagStart, imgTagEnd + 1);

        // Check if this img tag contains any of our src patterns
        final matchesPattern = patterns.any((p) => imgTag.contains(p));

        if (matchesPattern) {
          // Extract all attributes except src from the original img tag
          final attrRegex = RegExp(r'''(\w+)=["']([^"']*)["']''');
          final attributes = <String, String>{};
          for (final match in attrRegex.allMatches(imgTag)) {
            final name = match.group(1)!;
            final value = match.group(2)!;
            if (name != 'src') {
              attributes[name] = value;
            }
          }

          // Build attributes string for the new img tag
          final normalizedWebpPath = webpPath.startsWith('/') ? webpPath : '/$webpPath';
          final normalizedOriginalPath = originalPath.startsWith('/') ? originalPath : '/$originalPath';

          final attrString = attributes.entries
              .map((e) => '${e.key}="${e.value}"')
              .join(' ');
          final imgAttrs = attrString.isNotEmpty ? ' $attrString' : '';

          final pictureElement = '<picture>\n'
                               '  <source srcset="$normalizedWebpPath" type="image/webp">\n'
                               '  <img src="$normalizedOriginalPath"$imgAttrs>\n'
                               '</picture>';

          // Replace the img tag
          result = result.substring(0, imgTagStart) +
                   pictureElement +
                   result.substring(imgTagEnd + 1);

          // Continue searching after the inserted picture element
          searchStart = imgTagStart + pictureElement.length;
        } else {
          // Move past this img tag
          searchStart = imgTagEnd + 1;
        }
      }
    });

    return result;
  }

  /// Process an HTML file to replace image references
  Future<void> processHtmlFile(File htmlFile) async {
    if (!await htmlFile.exists()) return;

    String content = await htmlFile.readAsString();
    String processed = processHtml(content);

    // Only write if content changed
    if (processed != content) {
      await htmlFile.writeAsString(processed);
    }
  }

  /// Process all HTML files in a directory recursively
  Future<void> processHtmlDirectory(Directory dir) async {
    if (!await dir.exists()) return;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.html')) {
        await processHtmlFile(entity);
      }
    }
  }

  /// Get summary of WebP mappings
  void printSummary() {
    if (_webpMappings.isEmpty) {
      print('\n--- WebP HTML Processing ---');
      print('No WebP conversions registered');
      print('----------------------------');
      return;
    }

    print('\n--- WebP HTML Processing ---');
    print('WebP conversions registered:');
    _webpMappings.forEach((original, webp) {
      print('  $original -> $webp');
    });
    print('----------------------------');
  }

  /// Clear all mappings
  void clear() {
    _webpMappings.clear();
  }
}