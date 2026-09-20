import 'dart:async';
import 'package:liquify/liquify.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:html/parser.dart' as html;
import 'config_models.dart';
import 'page_models.dart';
import 'site_data_model.dart';
import 'site_urls.dart';
import 'markdown_features.dart';
import 'build_cache.dart';

const _urlsZone = #blogBuilderUrls;
bool _filtersRegistered = false;

class TemplateRenderer {
  final Root templateRoot;
  final BuildCache? cache;
  TemplateRenderer(this.templateRoot, {this.cache}) {
    if (!_filtersRegistered) {
      FilterRegistry.register(
          'relative_url',
          (value, args, named) =>
              (Zone.current[_urlsZone] as SiteUrls).relative(value));
      FilterRegistry.register(
          'absolute_url',
          (value, args, named) =>
              (Zone.current[_urlsZone] as SiteUrls).absolute(value));
      _filtersRegistered = true;
    }
  }

  String resolveLayoutPath(String? layoutId, bool isIndex) {
    final name = layoutId ?? (isIndex ? 'list' : 'default');
    if (name.startsWith('/') ||
        name.contains('\\') ||
        name.split('/').contains('..'))
      throw FormatException('Invalid layout name: $name');
    return '_layouts/$name.liquid';
  }

  Map<String, dynamic> _data(
      PageModel page, ConfigModel config, SiteData site) {
    final urls = SiteUrls(config);
    final description = page.metadata['description'] ??
        page.metadata['og:description'] ??
        page.blurb;
    final image = page.metadata['og:image'] ?? config.metadata['og:image'];
    return {
      // Collections resolve locale-scoped for this page (ticket 002): a page
      // with locale L sees site.<name> from the @L bucket, falling back to the
      // default bucket when the locale has no override.
      'site': {...site.toLiquidMap(locale: page.locale), ...config.toMap()},
      'page': {
        ...page.toMap(),
        'canonical_url':
            urls.absolute(page.route == '/' ? '/' : '${page.route}/'),
        'seo': {
          'title': page.metadata['og:title'] ?? page.title,
          'description': description,
          'image': image == null ? null : urls.absolute(image),
          'type': page.date == null ? 'website' : 'article'
        }
      },
      'content': page.renderedContent ?? '',
    };
  }

  Future<String> _render(String kind, String source, PageModel page,
      ConfigModel config, SiteData site,
      {String? layoutPath}) async {
    final data = _data(page, config, site);
    final pageData = Map<String, dynamic>.from(data['page']);
    if (kind == 'content') {
      pageData.remove('rendered_content');
      pageData.remove('toc');
      pageData.remove('headings');
    }
    final key = fingerprint([
      2,
      kind,
      source,
      pageData,
      config.toMap(),
      kind == 'layout' ? data['content'] : null
    ]);
    final cached = cache?.read(kind, key);
    if (cached != null &&
        SiteReads.matches(data['site'], cached['site_reads'] as Map)) {
      var valid = true;
      for (final entry in (cached['templates'] as Map).entries) {
        try {
          if (fingerprint(templateRoot.resolve(entry.key).content) !=
              entry.value) valid = false;
        } catch (_) {
          valid = false;
        }
      }
      if (valid) {
        if (kind == 'content') {
          cache!.contentHits++;
          page.tableOfContents = cached['toc'] ?? '';
          page.headings = (cached['headings'] as List? ?? [])
              .map((v) => Map<String, dynamic>.from(v))
              .toList();
        } else {
          cache!.layoutHits++;
        }
        return cached['html'] as String;
      }
    }
    final root = TrackingRoot(templateRoot);
    final reads = SiteReads(data['site']);
    data['site'] = reads.tracked;
    if (layoutPath != null &&
        (await root.resolveAsync(layoutPath)).content.trim().isEmpty)
      throw Exception('Layout template is empty: $layoutPath');
    final rendered = await runZoned(
        () => Template.parse(source, data: data, root: root).renderAsync(),
        zoneValues: {_urlsZone: SiteUrls(config)});
    final result = kind == 'content'
        ? enhanceMarkdown(
            md.markdownToHtml(rendered,
                extensionSet: md.ExtensionSet.gitHubFlavored,
                inlineSyntaxes: [md.InlineHtmlSyntax()]),
            page,
            config)
        : mountHtml(rendered, SiteUrls(config));
    if (kind == 'layout' && result.trim().isEmpty)
      throw Exception('Rendered content is empty');
    if (!root.volatile &&
        !RegExp(r'''['"](?:now|today)['"]''').hasMatch(source)) {
      cache?.write(kind, key, {
        'html': result,
        'templates': root.dependencies,
        'site_reads': reads.reads,
        'toc': page.tableOfContents,
        'headings': page.headings
      });
    }
    return result;
  }

  Future<String> renderContent(
          PageModel page, ConfigModel config, SiteData site) =>
      _render('content', page.rawMarkdown, page, config, site);

  Future<String> renderPageWithLayout(
      PageModel page, ConfigModel config, SiteData site,
      {String? layoutName}) {
    final path = resolveLayoutPath(layoutName ?? page.layoutId, page.isIndex);
    return _render('layout', "{% layout '${path.replaceAll("'", "\\'")}' %}",
        page, config, site,
        layoutPath: path);
  }
}

String mountHtml(String source, SiteUrls urls) {
  if (urls.basePath.isEmpty) return source;
  final isDocument =
      RegExp(r'<!doctype|<html(?:\s|>)', caseSensitive: false).hasMatch(source);
  final document = isDocument ? html.parse(source) : null;
  final fragment = isDocument ? null : html.parseFragment(source);
  final elements =
      document?.querySelectorAll('[href],[src],[action],[poster],[srcset]') ??
          fragment!.querySelectorAll('[href],[src],[action],[poster],[srcset]');
  for (final element in elements) {
    final srcset = element.attributes['srcset'];
    if (srcset != null)
      element.attributes['srcset'] = srcset.replaceAllMapped(
          RegExp(r'(^|,\s*)(/[^\s,]*)(?=\s|,|$)'),
          (match) => '${match[1]}${urls.relative(match[2])}');
    for (final name in ['href', 'src', 'action', 'poster']) {
      final value = element.attributes[name];
      if (value != null && value.startsWith('/') && !value.startsWith('//'))
        element.attributes[name] = urls.relative(value);
    }
  }
  return document?.outerHtml ?? fragment!.outerHtml;
}
