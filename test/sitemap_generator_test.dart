import 'package:blog_builder/blog_builder.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  late MemoryFileSystem fs;

  void write(String name, String content) {
    fs.file(name)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  PageModel page(
    String route, {
    bool draft = false,
    Map<String, dynamic> extras = const {},
  }) => PageModel.fromMap({'route': route, 'draft': draft, 'extras': extras});

  setUp(() => fs = MemoryFileSystem());

  test(
    'sitemap opt-out preserves defaults, explicit opt-in and error exclusions',
    () async {
      await SitemapGenerator.generateFromPageModels(
        [
          page('/'),
          page('/guide', extras: {'sitemap': true}),
          page('/admin/login', extras: {'sitemap': false}),
          page('/draft', draft: true),
          page('/404'),
          page('/zh/404/'),
          page('/404-guide'),
        ],
        'https://example.com/',
        outFile: '/sitemap.xml',
        fileSystem: fs,
      );
      final document = XmlDocument.parse(
        fs.file('/sitemap.xml').readAsStringSync(),
      );
      expect(
        document.findAllElements('loc').map((node) => node.innerText).toList(),
        [
          'https://example.com/',
          'https://example.com/guide',
          'https://example.com/404-guide',
        ],
      );
    },
  );

  test(
    'excluded locale URLs are omitted from sitemap alternate links too',
    () async {
      await SitemapGenerator.generateFromPageModels(
        [
          page(
            '/guide',
            extras: {
              'alternates': {
                'en': '/guide/',
                'zh': '/zh/guide/',
                'de': '/de/guide/',
              },
            },
          ),
          page('/zh/guide', extras: {'sitemap': false}),
          page('/de/guide'),
        ],
        'https://example.com/docs/',
        outFile: '/sitemap.xml',
        fileSystem: fs,
      );
      final document = XmlDocument.parse(
        fs.file('/sitemap.xml').readAsStringSync(),
      );
      final alternates = document.findAllElements('xhtml:link').toList();
      expect(alternates.map((node) => node.getAttribute('hreflang')).toList(), [
        'en',
        'de',
      ]);
      expect(alternates.map((node) => node.getAttribute('href')).toList(), [
        'https://example.com/docs/guide/',
        'https://example.com/docs/de/guide/',
      ]);
      expect(document.toXmlString(), isNot(contains('/zh/guide')));
    },
  );

  test(
    'real frontmatter keeps excluded pages built across locales and cached rebuilds',
    () async {
      write(
        '/site/config.yaml',
        'title: Site\nbaseUrl: https://example.com\ndefault_locale: en\nlocales:\n  en: { name: English }\n  zh: { name: Chinese }\n',
      );
      for (final locale in ['', 'zh/']) {
        write(
          '/site/content/${locale}admin/index.md',
          '---\ntitle: Admin login\npublished: true\nsitemap: false\n---\nSign in',
        );
        write(
          '/site/content/${locale}guide.md',
          '---\ntitle: Guide\npublished: true\nsitemap: true\n---\nPublic guide',
        );
      }
      final builder = StaticSiteBuilder(
        inputDir: '/site',
        outputDir: '/output',
        fileSystem: fs,
      );
      for (var build = 0; build < 2; build++) {
        await builder.build();
        final document = XmlDocument.parse(
          fs.file('/output/sitemap.xml').readAsStringSync(),
        );
        final urls = document
            .findAllElements('loc')
            .map((node) => node.innerText)
            .toSet();
        expect(
          urls,
          containsAll([
            'https://example.com/guide',
            'https://example.com/zh/guide',
          ]),
        );
        expect(document.toXmlString(), isNot(contains('/admin')));
        expect(
          fs.file('/output/admin/index.html').readAsStringSync(),
          contains('Sign in'),
        );
        expect(
          fs.file('/output/zh/admin/index.html').readAsStringSync(),
          contains('Sign in'),
        );
      }
    },
  );

  for (final invalid in ['"false"', 'no', '0', '[]', '{}']) {
    test('rejects non-boolean sitemap value $invalid', () {
      write(
        '/site/content/login.md',
        '---\ntitle: Login\npublished: true\nsitemap: $invalid\n---\nLogin',
      );
      expect(
        () => PageModel.from(
          fs.file('/site/content/login.md'),
          fs.directory('/site/content'),
        ),
        throwsFormatException,
      );
    });
  }
}
