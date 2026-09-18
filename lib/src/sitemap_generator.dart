import 'package:blog_builder/blog_builder.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:xml/xml.dart';

class SitemapGenerator {
  // Example alternative: Generate using PageModel objects
  static Future<void> generateFromPageModels(List<PageModel> pages, String host,
      {required String outFile,
      FileSystem fileSystem = const LocalFileSystem()}) async {
    await _generateInternal(
        pages
            .where((p) => !p.draft) // Only include non-draft pages
            .map((p) => _SitemapEntry(
                loc: "${host.replaceFirst(RegExp(r'/+$'), '')}${p.route}",
                lastmod: p.date ?? DateTime.now(), // Use page date or fallback
                priority: _calculatePriority(p.route),
                alternates: p.alternatesMap(host)))
            .toList(),
        outFile,
        fileSystem);
  }

  // Internal generation logic
  static Future<void> _generateInternal(List<_SitemapEntry> entries,
      String outFile, FileSystem fileSystem) async {
    XmlElement urlset = XmlElement(
      XmlName('urlset'),
      [
        XmlAttribute(
            XmlName('xmlns'), 'http://www.sitemaps.org/schemas/sitemap/0.9'),
        XmlAttribute(
            XmlName('xmlns:xhtml'), 'http://www.w3.org/1999/xhtml'),
        XmlAttribute(
            XmlName('xmlns:xsi'), 'http://www.w3.org/2001/XMLSchema-instance'),
        XmlAttribute(XmlName('xsi:schemaLocation'),
            'http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd')
      ],
      [],
    );

    for (final entry in entries) {
      urlset.children.add(
        XmlElement(
          XmlName('url'),
          [],
          [
            XmlElement(XmlName('loc'), [], [XmlText(entry.loc)]),
            XmlElement(XmlName('lastmod'), [], [
              // Format date to W3C Datetime format (YYYY-MM-DD)
              XmlText(entry.lastmod.toIso8601String().split('T').first)
            ]),
            XmlElement(XmlName('priority'), [], [
              XmlText(entry.priority.toStringAsFixed(1)) // Format priority
            ]),
            for (final alt in entry.alternates.entries)
              XmlElement(XmlName('xhtml:link'), [
                XmlAttribute(XmlName('rel'), 'alternate'),
                XmlAttribute(XmlName('hreflang'), alt.key),
                XmlAttribute(XmlName('href'), alt.value),
              ]),
          ],
        ),
      );
    }
    var document = XmlDocument([urlset]);

    try {
      final file = fileSystem.file(outFile);
      // Ensure the directory exists
      if (!await file.parent.exists()) {
        // Use async exists with MemoryFileSystem
        await file.parent.create(recursive: true); // Use async create
      }
      await file.writeAsString(
          document.toXmlString(pretty: true, indent: '  ')); // Use async write
      print('Sitemap generated successfully at $outFile');
    } catch (e) {
      print('Error writing sitemap file $outFile: $e');
      rethrow;
    }
  }

  // Helper to calculate priority based on path depth or rules
  static double _calculatePriority(String path) {
    if (path == "/") return 1.0;
    // Example rule: less depth = higher priority
    int depth = path.split('/').where((s) => s.isNotEmpty).length;
    if (depth == 1) return 0.8;
    if (depth == 2) return 0.6;
    return 0.5; // Default priority
    // Add more specific rules if needed (e.g., path.startsWith('/blog'))
  }
}

// Internal helper class for sitemap entries
class _SitemapEntry {
  final String loc;
  final DateTime lastmod;
  final double priority;
  final Map<String, String> alternates;

  _SitemapEntry(
      {required this.loc,
      required this.lastmod,
      required this.priority,
      this.alternates = const {}});
}
