import 'package:blog_builder/blog_builder.dart';
import 'package:file/memory.dart';
import 'package:html/parser.dart' as html;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  test('page URLs preserve roots, locale paths and existing mounts', () {
    for (final base in ['https://example.com', 'https://example.com/docs/']) {
      final urls = SiteUrls(ConfigModel(baseUrl: base, metadata: const {}));
      final prefix = base.contains('/docs') ? '/docs' : '';
      for (final route in ['/', '/privacy', '/privacy/', '/zh', '/zh/']) {
        final expected = '$prefix${SiteUrls.pagePath(route)}';
        expect(urls.pageUrl(route), expected);
        expect(urls.canonical(route), 'https://example.com$expected');
      }
      expect(urls.canonical('$prefix/privacy/'),
          'https://example.com$prefix/privacy/');
    }
    final urls = SiteUrls(ConfigModel(
        baseUrl: 'https://example.com',
        basePath: '/manual',
        metadata: const {}));
    expect(urls.canonical('/'), 'https://example.com/manual/');
    expect(
        urls.canonical('/manual/guide/'), 'https://example.com/manual/guide/');
    expect(SiteUrls.pagePath('/guide///'), '/guide/');
    expect(SiteUrls.pagePath('/guide?q=one#section'), '/guide/?q=one#section');
  });

  for (final base in ['https://example.com', 'https://example.com/docs/']) {
    test('canonical, sitemap, locale and navigation URLs agree under $base',
        () async {
      final fs = MemoryFileSystem();
      void write(String path, String content) => fs.file(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      write('/site/config.yaml',
          'title: Site\nbaseUrl: $base\ndefault_locale: en\nlocales:\n  en: { name: English }\n  zh: { name: Chinese }\n');
      for (final locale in ['', 'zh/']) {
        write('/site/content/${locale}index.md',
            '---\ntitle: Home\npublished: true\n---\nHome');
        write('/site/content/${locale}privacy.md',
            "---\ntitle: Privacy\npublished: true\n---\n<a id=\"canonical-nav\" href=\"{{ page.route | page_url }}\">Privacy</a>");
      }
      final builder = StaticSiteBuilder(
          inputDir: '/site',
          outputDir: '/out',
          fileSystem: fs,
          announce: false);
      final urls = SiteUrls(ConfigModel(baseUrl: base, metadata: const {}));
      for (var build = 0; build < 2; build++) {
        await builder.build();
        final sitemap =
            XmlDocument.parse(fs.file('/out/sitemap.xml').readAsStringSync());
        final locations = sitemap
            .findAllElements('loc')
            .map((node) => node.innerText)
            .toSet();
        for (final route in ['/', '/privacy', '/zh', '/zh/privacy']) {
          final path =
              route == '/' ? '/out/index.html' : '/out$route/index.html';
          final page = html.parse(fs.file(path).readAsStringSync());
          final expected = urls.canonical(route);
          expect(page.querySelector('link[rel=canonical]')!.attributes['href'],
              expected);
          expect(locations, contains(expected));
          if (route.endsWith('privacy')) {
            expect(page.querySelector('#canonical-nav')!.attributes['href'],
                urls.pageUrl(route));
          }
          for (final alternate in page.querySelectorAll('link[hreflang]')) {
            expect(locations, contains(alternate.attributes['href']));
          }
        }
        for (final alternate in sitemap.findAllElements('xhtml:link')) {
          expect(locations, contains(alternate.getAttribute('href')));
        }
      }
    });
  }

  test('sitemap normalizes manual alternates and avoids doubling base paths',
      () async {
    final fs = MemoryFileSystem();
    await SitemapGenerator.generateFromPageModels(
      [
        PageModel.fromMap({
          'route': '/docs/privacy',
          'extras': {
            'alternates': {
              'en': '/docs/privacy',
              'zh': '/zh/privacy/',
            }
          }
        }),
        PageModel.fromMap({'route': '/zh/privacy'}),
      ],
      'https://example.com/docs/',
      outFile: '/sitemap.xml',
      fileSystem: fs,
    );
    final sitemap =
        XmlDocument.parse(fs.file('/sitemap.xml').readAsStringSync());
    expect(sitemap.findAllElements('loc').map((node) => node.innerText), [
      'https://example.com/docs/privacy/',
      'https://example.com/docs/zh/privacy/',
    ]);
    expect(
        sitemap
            .findAllElements('xhtml:link')
            .map((node) => node.getAttribute('href')),
        [
          'https://example.com/docs/privacy/',
          'https://example.com/docs/zh/privacy/',
        ]);
  });
}
