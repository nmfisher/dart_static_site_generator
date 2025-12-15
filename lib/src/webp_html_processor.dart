// lib/src/webp_html_processor.dart
import 'dart:io';
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
    // Use string manipulation approach instead of complex regex
    var result = html;

    _webpMappings.forEach((originalPath, webpPath) {
      // Look for img tags with the original image src
      final searchPattern = 'src="$originalPath"';
      final searchPattern2 = "src='$originalPath'";

      if (result.contains(searchPattern) || result.contains(searchPattern2)) {
        // Find the img tag
        final imgTagStart = result.indexOf('<img');
        while (imgTagStart != -1) {
          final imgTagEnd = result.indexOf('>', imgTagStart);
          if (imgTagEnd == -1) break;

          final imgTag = result.substring(imgTagStart, imgTagEnd + 1);

          // Check if this img tag contains our src
          if (imgTag.contains(searchPattern) || imgTag.contains(searchPattern2)) {
            // Extract alt attribute
            var alt = '';
            final altStart = imgTag.indexOf('alt="');
            if (altStart != -1) {
              final altValueStart = altStart + 5;
              final altValueEnd = imgTag.indexOf('"', altValueStart);
              if (altValueEnd != -1) {
                alt = imgTag.substring(altValueStart, altValueEnd);
              }
            }

            // Create the new picture element
            final normalizedWebpPath = webpPath.startsWith('/') ? webpPath : '/$webpPath';
            final normalizedOriginalPath = originalPath.startsWith('/') ? originalPath : '/$originalPath';

            final pictureElement = '<picture>\n'
                                 '  <source srcset="$normalizedWebpPath" type="image/webp">\n'
                                 '  <img src="$normalizedOriginalPath" alt="$alt">\n'
                                 '</picture>';

            // Replace the img tag
            result = result.substring(0, imgTagStart) +
                     pictureElement +
                     result.substring(imgTagEnd + 1);

            // Adjust position since we replaced the tag
            break;
          }

          // Look for next img tag
          final nextImgStart = result.indexOf('<img', imgTagStart + 1);
          if (nextImgStart == -1) break;
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