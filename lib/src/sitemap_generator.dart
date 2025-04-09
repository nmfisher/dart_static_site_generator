// import 'dart:io';
// import 'package:xml/xml.dart';

// // Example usage might look like this (needs adaptation):
// // import 'page_models.dart';
// // SitemapGenerator.generateFromPageModels(pages, 'https://yourdomain.com');

// class SitemapGenerator {

//   // Generate using jaspr_router Route objects (as originally provided)
//   static void generate(List<Route> routes, String host, { String outFile = "build/sitemap.xml"}) {
//      _generateInternal(
//         routes.map((r) => _SitemapEntry(
//            loc: "$host${r.path}",
//            lastmod: DateTime.now(), // Use current time or fetch from Route if available
//            priority: _calculatePriority(r.path)
//         )).toList(),
//         outFile
//      );
//   }

//   // Example alternative: Generate using PageModel objects
//    static void generateFromPageModels(List<PageModel> pages, String host, { String outFile = "build/sitemap.xml"}) {
//      _generateInternal(
//         pages
//           .where((p) => !p.draft) // Only include non-draft pages
//           .map((p) => _SitemapEntry(
//              loc: "$host${p.route}",
//              lastmod: p.date ?? DateTime.now(), // Use page date or fallback
//              priority: _calculatePriority(p.route)
//           )).toList(),
//         outFile
//      );
//    }


//   // Internal generation logic
//   static void _generateInternal(List<_SitemapEntry> entries, String outFile) {
//       XmlElement urlset = XmlElement(
//       XmlName('urlset'),
//       [
//         XmlAttribute(
//             XmlName('xmlns'), 'http://www.sitemaps.org/schemas/sitemap/0.9'),
//         XmlAttribute(
//             XmlName('xmlns:xsi'), 'http://www.w3.org/2001/XMLSchema-instance'),
//         XmlAttribute(XmlName('xsi:schemaLocation'),
//             'http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd')
//       ],
//       [],
//     );

//     for (final entry in entries) {
//       urlset.children.add(
//         XmlElement(
//           XmlName('url'),
//           [],
//           [
//             XmlElement(XmlName('loc'), [], [XmlText(entry.loc)]),
//             XmlElement(XmlName('lastmod'), [], [
//               // Format date to W3C Datetime format (YYYY-MM-DD)
//               XmlText(entry.lastmod.toIso8601String().split('T').first)
//             ]),
//             XmlElement(XmlName('priority'), [], [
//               XmlText(entry.priority.toStringAsFixed(1)) // Format priority
//             ]),
//           ],
//         ),
//       );
//     }
//     var document = XmlDocument([urlset]);

//     try {
//        final file = File(outFile);
//        // Ensure the directory exists
//        if (!file.parent.existsSync()) {
//           file.parent.createSync(recursive: true);
//        }
//        file.writeAsStringSync(document.toXmlString(pretty: true, indent: '  '));
//        print('Sitemap generated successfully at $outFile');
//     } catch (e) {
//        print('Error writing sitemap file $outFile: $e');
//     }
//   }

//    // Helper to calculate priority based on path depth or rules
//   static double _calculatePriority(String path) {
//      if (path == "/") return 1.0;
//      // Example rule: less depth = higher priority
//      int depth = path.split('/').where((s) => s.isNotEmpty).length;
//      if (depth == 1) return 0.8;
//      if (depth == 2) return 0.6;
//      return 0.5; // Default priority
//      // Add more specific rules if needed (e.g., path.startsWith('/blog'))
//   }
// }

// // Internal helper class for sitemap entries
// class _SitemapEntry {
//    final String loc;
//    final DateTime lastmod;
//    final double priority;

//    _SitemapEntry({required this.loc, required this.lastmod, required this.priority});
// }
