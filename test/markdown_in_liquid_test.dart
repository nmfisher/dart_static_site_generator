import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/renderer.dart';
import 'package:liquify/liquify.dart';
import 'package:test/test.dart';
import 'package:blog_builder/src/site_data_model.dart';

void main() {
  group('Markdown in Liquid Templates', () {
    late TemplateRenderer renderer;
    late ConfigModel testConfig;
    late SiteData dummySiteData;

    setUp(() {
      testConfig = ConfigModel(
        title: 'Test Site',
        owner: 'Tester',
        metadata: {'site_meta': 'global value'},
        baseUrl: 'http://example.com',
      );
      dummySiteData = SiteData(name: 'dummy', route: '/');
    });

    MapRoot createTestRoot(Map<String, String> templates) {
      return MapRoot(templates);
    }

    test('should demonstrate the markdown-in-liquid issue', () async {
      // This test shows that markdown syntax in Liquid templates
      // is NOT processed as markdown, which explains why
      // ![logo](./assets/logo.png) appears as raw text
      final testRoot = createTestRoot({
        '_layouts/markdown_test.liquid': '''
<!DOCTYPE html>
<html>
<head>
    <title>Test</title>
</head>
<body>
    <h1>This should render</h1>
    ![logo](./assets/logo.png)
    <p>This is **bold** text in template.</p>
    {{ content }}
</body>
</html>
        ''',
      });
      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        rawMarkdown: 'This is page content with **markdown**',
        title: 'Test Page',
        route: '/test',
        source: '/test.md',
        blurb: 'Test blurb',
        metadata: {},
        date: null,
        draft: false,
        isIndex: false,
      )..renderedContent = '<p>This is page content with <strong>markdown</strong></p>\n';

      final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData, layoutName: 'markdown_test');

      // The page content markdown should be processed
      expect(result, contains('<p>This is page content with <strong>markdown</strong></p>'));

      // But the markdown syntax in the template should remain as raw text
      expect(result, contains('![logo](./assets/logo.png)'));
      expect(result, contains('This is **bold** text in template.'));

      // And it should NOT be converted to HTML
      expect(result, isNot(contains('<img src="./assets/logo.png"')));
      expect(result, isNot(contains('<strong>bold</strong>')));
    });

    test('should show proper HTML img tag works in Liquid templates', () async {
      // This test shows that using proper HTML in templates works correctly
      final testRoot = createTestRoot({
        '_layouts/html_test.liquid': '''
<!DOCTYPE html>
<html>
<head>
    <title>Test</title>
</head>
<body>
    <h1>HTML Image Test</h1>
    <img src="./assets/logo.png" alt="logo" />
    {{ content }}
</body>
</html>
        ''',
      });
      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        rawMarkdown: 'Page content',
        title: 'Test Page',
        route: '/test',
        source: '/test.md',
        blurb: 'Test blurb',
        metadata: {},
        date: null,
        draft: false,
        isIndex: false,
      )..renderedContent = '<p>Page content</p>\n';

      final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData, layoutName: 'html_test');

      // The HTML img tag should be preserved
      expect(result, contains('<img src="./assets/logo.png" alt="logo" />'));
    });

    test('should process markdown in page content but not in layout', () async {
      final testRoot = createTestRoot({
        '_layouts/separation_test.liquid': '''
<html>
<body>
    <div class="template-content">
        # This is a heading in template (should stay as text)
        * List item in template (should stay as text)
    </div>
    <div class="page-content">
        {{ content }}
    </div>
</body>
</html>
        ''',
      });
      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        rawMarkdown: '''# This is a heading in page content
* This is a list item in page content
Both should be converted to HTML''',
        title: 'Test Page',
        route: '/test',
        source: '/test.md',
        blurb: 'Test blurb',
        metadata: {},
        date: null,
        draft: false,
        isIndex: false,
      );

      // First pass - render markdown content
      final renderedContent = await renderer.renderContent(page, testConfig, dummySiteData);
      page.renderedContent = renderedContent;

      // Second pass - render with layout
      final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData, layoutName: 'separation_test');

      // Page content markdown should be processed
      expect(result, contains('<h1>This is a heading in page content</h1>'));
      expect(result, contains('<ul>'));
      expect(result, contains('<li>This is a list item in page content\nBoth should be converted to HTML</li>'));

      // Template markdown should remain as raw text
      expect(result, contains('# This is a heading in template (should stay as text)'));
      expect(result, contains('* List item in template (should stay as text)'));
    });
  });
}