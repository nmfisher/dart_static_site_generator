import 'package:html/parser.dart' as html;
import 'config_models.dart';
import 'page_models.dart';
import 'site_urls.dart';

class BuildDiagnostic {
  final String source, message;
  BuildDiagnostic(this.source, this.message);
  @override
  String toString() => '$source: $message';
}

class SiteValidator {
  static List<BuildDiagnostic> outputs(
      List<PageModel> pages, Set<String> assets) {
    final files = <String, String>{
      for (final path in assets) path.toLowerCase(): 'asset $path'
    };
    final issues = <BuildDiagnostic>[];
    for (final page in pages) {
      final path =
          '${page.route == '/' ? '' : page.route}/index.html'.toLowerCase();
      if (files.containsKey(path))
        issues.add(BuildDiagnostic(
            page.source, 'Output conflicts with ${files[path]}'));
      files[path] = page.source;
    }
    for (final path in files.keys) {
      var parent = path;
      while (parent.lastIndexOf('/') > 0) {
        parent = parent.substring(0, parent.lastIndexOf('/'));
        if (files.containsKey(parent))
          issues.add(BuildDiagnostic(
              files[path]!, 'Output directory conflicts with file $parent'));
      }
    }
    return issues;
  }

  static List<BuildDiagnostic> routes(List<PageModel> pages) {
    final seen = <String, PageModel>{};
    final issues = <BuildDiagnostic>[];
    for (final page in pages) {
      final key = page.route.replaceAll(RegExp(r'/+$'), '').toLowerCase();
      if (seen.containsKey(key))
        issues.add(BuildDiagnostic(page.source,
            'Duplicate route ${page.route}; also used by ${seen[key]!.source}'));
      else
        seen[key] = page;
    }
    return issues;
  }

  static List<BuildDiagnostic> links(Map<String, String> rendered,
      List<PageModel> pages, Set<String> assets, ConfigModel config) {
    final issues = <BuildDiagnostic>[];
    final urls = SiteUrls(config);
    final docs =
        rendered.map((route, value) => MapEntry(route, html.parse(value)));
    final sources = {for (final page in pages) page.route: page.source};
    final base = Uri.tryParse(config.baseUrl ?? 'https://site.invalid');
    String routeOf(String path) {
      if (path.endsWith('/index.html'))
        path = path.substring(0, path.length - 11);
      if (path.length > 1 && path.endsWith('/'))
        path = path.substring(0, path.length - 1);
      return path.isEmpty ? '/' : path;
    }

    for (final entry in docs.entries) {
      final seen = <String>{};
      final pageUrl = Uri.parse(
          'https://site.invalid${urls.relative(entry.key == '/' ? '/' : '${entry.key}/')}');
      for (final node
          in entry.value.querySelectorAll('[href],[src],[poster],[srcset]')) {
        final references = <MapEntry<String, String?>>[
          for (final attr in ['href', 'src', 'poster'])
            MapEntry(attr, node.attributes[attr]),
          if (node.attributes['srcset'] != null &&
              !node.attributes['srcset']!.contains('data:'))
            for (final candidate in node.attributes['srcset']!.split(','))
              MapEntry('src', candidate.trim().split(RegExp(r'\s+')).first),
        ];
        for (final reference in references) {
          final attr = reference.key;
          final text = reference.value;
          if (text == null || text.isEmpty || !seen.add(text)) continue;
          final uri = Uri.tryParse(text);
          if (uri == null) {
            issues.add(
                BuildDiagnostic(sources[entry.key]!, 'Invalid URL: $text'));
            continue;
          }
          if (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http')
            continue;
          if ((uri.hasAuthority || uri.hasScheme) && uri.host != base?.host)
            continue;
          final target = pageUrl.resolveUri(uri);
          final local = urls.unmount(Uri.decodeComponent(target.path));
          if (local == null)
            continue; // Link outside a subdirectory-hosted site.
          final route = routeOf(local);
          final document = docs[route];
          if (document == null && !assets.contains(local)) {
            issues.add(BuildDiagnostic(sources[entry.key]!,
                'Missing ${attr == 'src' || attr == 'poster' ? 'asset' : 'internal link'}: $text'));
          } else if (document != null && target.fragment.isNotEmpty) {
            final fragment = Uri.decodeComponent(target.fragment);
            if (!document.querySelectorAll('[id],[name]').any(
                (e) => e.id == fragment || e.attributes['name'] == fragment)) {
              issues.add(BuildDiagnostic(
                  sources[entry.key]!, 'Missing anchor: $text'));
            }
          }
        }
      }
    }
    return issues;
  }
}
