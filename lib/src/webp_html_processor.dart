// lib/src/webp_html_processor.dart
import 'package:file/file.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;

/// Tracks WebP conversions and replaces image references in HTML
class WebPHtmlProcessor {
  final Map<String, String> _webpMappings = {}; // Original path -> WebP path
  final FileSystem fileSystem;

  WebPHtmlProcessor({required this.fileSystem});

  /// Register a WebP conversion
  void registerWebPConversion(String originalPath, String webpPath) {
    _webpMappings[_normalize(originalPath)] = _normalize(webpPath);
  }

  String _normalize(String value) =>
      path.posix.normalize(value.startsWith('/') ? value.substring(1) : value);

  bool hasWebPVersion(String imagePath) =>
      _webpMappings.containsKey(_normalize(imagePath));

  String? getWebPPath(String imagePath) => _webpMappings[_normalize(imagePath)];

  /// Process HTML content to replace img tags with picture elements where WebP is available
  String processHtml(String html,
      {String basePath = '', String mountPath = ''}) {
    if (_webpMappings.isEmpty) return html;
    final isDocument =
        RegExp(r'<!doctype|<html(?:\s|>)', caseSensitive: false).hasMatch(html);
    final document = isDocument ? html_parser.parse(html) : null;
    final fragment = isDocument ? null : html_parser.parseFragment(html);
    final images =
        document?.querySelectorAll('img') ?? fragment!.querySelectorAll('img');
    var changed = false;
    for (final img in images) {
      if (img.parent?.localName == 'picture') continue;
      final uri = Uri.tryParse(img.attributes['src'] ?? '');
      if (uri == null || uri.hasScheme || uri.hasAuthority || uri.path.isEmpty)
        continue;
      var originalPath = path.posix.normalize(uri.path.startsWith('/')
          ? uri.path.substring(1)
          : path.posix.join(basePath, uri.path));
      if (mountPath.isNotEmpty &&
          originalPath.startsWith('${mountPath.substring(1)}/'))
        originalPath = originalPath.substring(mountPath.length);
      final webpPath = _webpMappings[originalPath];
      if (webpPath == null || webpPath == originalPath) continue;
      final source = dom.Element.tag('source')
        ..attributes['srcset'] =
            uri.replace(path: '$mountPath/$webpPath').toString()
        ..attributes['type'] = 'image/webp';
      final picture = dom.Element.tag('picture');
      img.replaceWith(picture);
      picture.nodes.add(source);
      picture.nodes.add(img);
      changed = true;
    }
    if (!changed) return html;
    return document?.outerHtml ?? fragment!.outerHtml;
  }

  /// Process an HTML file to replace image references
  Future<void> processHtmlFile(File htmlFile,
      {String basePath = '', String mountPath = ''}) async {
    if (!await htmlFile.exists()) return;

    String content = await htmlFile.readAsString();
    String processed =
        processHtml(content, basePath: basePath, mountPath: mountPath);

    // Only write if content changed
    if (processed != content) {
      await htmlFile.writeAsString(processed);
    }
  }

  /// Process all HTML files in a directory recursively
  Future<void> processHtmlDirectory(Directory dir,
      {String basePath = ''}) async {
    if (!await dir.exists()) return;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.html')) {
        final relative = fileSystem.path
            .relative(entity.path, from: dir.path)
            .replaceAll(fileSystem.path.separator, '/');
        await processHtmlFile(entity,
            basePath: path.posix.dirname(relative), mountPath: basePath);
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
