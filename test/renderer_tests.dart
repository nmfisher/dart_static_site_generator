import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/renderer.dart';
import 'package:liquify/liquify.dart';
import 'package:test/test.dart';
import 'package:blog_builder/src/site_data_model.dart';

void main() {
  group('TemplateRenderer', () {
    late TemplateRenderer renderer;
    late ConfigModel testConfig;
    late SiteData dummySiteData;

    final testPageData = {
      'rawMarkdown': 'Test content with **bold** text.',
      'title': 'Test Page Title',
      'route': '/test-page',
      'source': '/path/to/source.md',
      'blurb': 'Test blurb',
      'metadata': {'custom_key': 'custom value', 'og:title': 'Test OG Title'},
      'date': DateTime(2023, 10, 27),
      'draft': false,
      'isIndex': false,
    };

    // Expected HTML output from testPageData's rawMarkdown
    const testPageRenderedContent = '<p>Test content with <strong>bold</strong> text.</p>\n';

    final testIndexPageData = {
      'rawMarkdown': 'This is the main content for the index.',
      'title': 'Test Index',
      'route': '/test-index',
      'source': '/path/to/test-index/',
      'blurb': 'Index blurb',
      'metadata': {'og:title': 'Test Index OG Title'},
      'date': null,
      'draft': false,
      'isIndex': true,
      'children': [
        PageModel(
          rawMarkdown: 'Child 1 md',
          title: 'Child Page 1',
          route: '/test-index/child1',
          source: '/path/to/test-index/child1.md',
          blurb: 'Child 1 blurb',
          metadata: {},
          date: DateTime(2023, 10, 26),
          draft: false,
        ),
        PageModel(
          rawMarkdown: 'Child 2 md',
          title: 'Child Page 2',
          route: '/test-index/child2',
          source: '/path/to/test-index/child2.md',
          blurb: 'Child 2 blurb',
          metadata: {},
          date: DateTime(2023, 10, 25),
          draft: false,
        ),
      ]
    };

    const baseLayoutContent = '''
<!DOCTYPE html>
<html>
<head>
    <title>{% block title %}{{ page.title }}{% endblock %} - {{ site.title | default: 'Base Site' }}</title>
    {% block head_extra %}{% comment %}<!-- Extra head elements -->{% endcomment %}{% endblock %}
</head>
<body>
    <header>{% block header %}Base Header{% endblock %}</header>
    <main>
        {% block main_content %}
            <h1>Default Content Area</h1>
            <p>Base layout content.</p>
            {{ content }} {# Renders the page's renderedContent #}
        {% endblock %}
    </main>
    <footer>{% block footer %}Base Footer{% endblock %}</footer>
    {% block scripts %}{% comment %}<!-- Default Scripts -->{% endcomment %}{% endblock %}
</body>
</html>''';

    const pageWithBlocksLayoutContent = '''
{% layout '_layouts/base.liquid' %}

{% block title %}Specific Child Title{% endblock %}

{% block head_extra %}
    <meta name="author" content="Block Test Author">
{% endblock %}

{% block main_content %}
    <h2>Overridden Content Heading</h2>
    <p>This content comes from the child block.</p>
    {{ content }}
{% endblock %}

{% comment %} Footer is NOT overridden, should use Base Footer {% endcomment %}

{% block scripts %}
    <script src="/child.js"></script>
{% endblock %}
''';


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

    group('Path Resolution', () {
      test('should return correct path for default layout', () {
        final testRoot = createTestRoot({});
        renderer = TemplateRenderer(testRoot);
        final path = renderer.resolveLayoutPath(null, false);
        expect(path, equals('_layouts/default.liquid'));
      });

      test('should return correct path for list layout (index)', () {
        final testRoot = createTestRoot({});
        renderer = TemplateRenderer(testRoot);
        final path = renderer.resolveLayoutPath(null, true);
        expect(path, equals('_layouts/list.liquid'));
      });

      test('should return correct path for custom layout', () {
        final testRoot = createTestRoot({});
        renderer = TemplateRenderer(testRoot);
        final path = renderer.resolveLayoutPath('custom', false);
        expect(path, equals('_layouts/custom.liquid'));
      });
    });

    group('Pass 1: renderContent', () {
      test('should render basic markdown to HTML', () async {
        final testRoot = createTestRoot({});
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap(testPageData);

        final result = await renderer.renderContent(page, testConfig, dummySiteData);
        expect(result, equals(testPageRenderedContent));
      });

      test("should render markdown tables correctly", () async {
        final testRoot = createTestRoot({});
        renderer = TemplateRenderer(testRoot);
        const tableMarkdown =
            "| Name | Age |\n|------|----:|\n| Alice | 30 |\n| Bob | 25 |";
        final page = PageModel.fromMap({...testPageData, 'rawMarkdown': tableMarkdown});

        final result = await renderer.renderContent(page, testConfig, dummySiteData);
        expect(result, contains("<table>"));
        expect(result, contains("<thead>"));
        expect(result, contains("<tbody>"));
        expect(result, contains('<th>Name</th>'));
        expect(result, contains('<th align="right">Age</th>'));
        expect(result, contains("<td>Alice</td>"));
        expect(result, contains("<td>Bob</td>"));
      });

      test('should process liquid tags within markdown', () async {
        final testRoot = createTestRoot({});
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({
          ...testPageData,
          'rawMarkdown': 'This page is for {{ site.owner }}.',
        });

        final result = await renderer.renderContent(page, testConfig, dummySiteData);
        expect(result, equals('<p>This page is for Tester.</p>\n'));
      });
    });

    group('Pass 2: renderPageWithLayout', () {
      test(
          'should throw exception if layout cannot be resolved',
          () async {
        final testRoot = createTestRoot({}); // No layouts defined
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({...testPageData, 'layoutId': 'nonexistent'})
          ..renderedContent = testPageRenderedContent; // Simulate pass 1

        expectLater(
          () => renderer.renderPageWithLayout(page, testConfig, dummySiteData),
          throwsA(isA<Exception>()),
        );
      });

      test('should throw exception if layout file is empty', () async {
        final testRoot = createTestRoot({'_layouts/empty.liquid': ''});
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({...testPageData, 'layoutId': 'empty'})
          ..renderedContent = testPageRenderedContent;

        expectLater(
          () => renderer.renderPageWithLayout(page, testConfig, dummySiteData),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Layout template is empty'))),
        );
      });

       test(
          'should throw exception if rendered output is empty or whitespace only',
          () async {
        final testRoot = createTestRoot({
          '_layouts/empty_output.liquid': '{% if false %}This should not render{% endif %}',
          '_layouts/whitespace_output.liquid': '   \n  \t ',
        });
        renderer = TemplateRenderer(testRoot);

        final emptyOutputPage = PageModel.fromMap({...testPageData, 'layoutId': 'empty_output'})
          ..renderedContent = '';
        final whitespaceOutputPage = PageModel.fromMap({...testPageData, 'layoutId': 'whitespace_output'})
          ..renderedContent = '';

        expectLater(
          () => renderer.renderPageWithLayout(emptyOutputPage, testConfig, dummySiteData),
          throwsA(isA<Exception>()),
        );
        expectLater(
          () => renderer.renderPageWithLayout(whitespaceOutputPage, testConfig, dummySiteData),
          throwsA(isA<Exception>()),
        );
      });

      test('should render content successfully using default layout', () async {
        final testRoot = createTestRoot({
          '_layouts/default.liquid': '<html><body>Default Layout: {{ content }}</body></html>',
        });
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap(testPageData)
          ..renderedContent = testPageRenderedContent; // Simulate pass 1

        final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData);
        expect(result, equals('<html><body>Default Layout: $testPageRenderedContent</body></html>'));
      });

      test('should access page and site metadata in layout', () async {
        final testRoot = createTestRoot({
          '_layouts/custom.liquid': '{{ site.title }} - {{ page.metadata.custom_key }}: {{ content }}',
        });
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({...testPageData, 'layoutId': 'custom'})
          ..renderedContent = '<h1>Hi</h1>';

        final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData);
        expect(result, equals('Test Site - custom value: <h1>Hi</h1>'));
      });

      test('should render index page using list layout and access children', () async {
        final testRoot = createTestRoot({
          '_layouts/list.liquid': '<h1>List</h1><ul>{% for item in page.children %}<li>{{ item.title }}</li>{% endfor %}</ul>{{ content }}',
        });
        renderer = TemplateRenderer(testRoot);
        final indexPage = PageIndexPageModel.fromMap(testIndexPageData)
          ..renderedContent = '<p>Index content</p>'; // Simulate pass 1

        final result = await renderer.renderPageWithLayout(indexPage, testConfig, dummySiteData);
        expect(result, contains('<h1>List</h1>'));
        expect(result, contains('<li>Child Page 1</li>'));
        expect(result, contains('<li>Child Page 2</li>'));
        expect(result, endsWith('</ul><p>Index content</p>'));
      });

      test('should render page with include correctly', () async {
        final testRoot = createTestRoot({
          '_layouts/with_include.liquid': '{% render "_includes/header.liquid" with site: site %}{{ content }}',
          '_includes/header.liquid': '<header>{{ site.title }}</header>',
        });
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({...testPageData, 'layoutId': 'with_include'})
          ..renderedContent = '<div>Main</div>';

        final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData);
        expect(result, equals('<header>Test Site</header><div>Main</div>'));
      });

      test('should render content using layout blocks correctly', () async {
        final testRoot = createTestRoot({
          '_layouts/page_with_blocks.liquid': pageWithBlocksLayoutContent,
          '_layouts/base.liquid': baseLayoutContent,
        });
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({...testPageData, 'layoutId': 'page_with_blocks'})
          ..renderedContent = testPageRenderedContent; // Simulate Pass 1

        final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData);

        expect(result, contains('<title>Specific Child Title - Test Site</title>'));
        expect(result, contains('<meta name="author" content="Block Test Author">'));
        expect(result, contains('<h2>Overridden Content Heading</h2>'));
        expect(result, contains('<p>This content comes from the child block.</p>'));
        expect(result, contains(testPageRenderedContent));
        expect(result, contains('<script src="/child.js"></script>'));
        expect(result, contains('<footer>Base Footer</footer>'));
        expect(result, isNot(contains('<h1>Default Content Area</h1>')));
      });

      test('should use default block content when not overridden', () async {
        final testRoot = createTestRoot({
          '_layouts/base.liquid': baseLayoutContent,
          '_layouts/simple.liquid': '{% layout "_layouts/base.liquid" %}',
        });
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({...testPageData, 'layoutId': 'simple'})
          ..renderedContent = 'My Content';

        final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData);
        expect(result, contains('<title>Test Page Title - Test Site</title>'));
        expect(result, contains('<h1>Default Content Area</h1>'));
        expect(result, contains('<p>Base layout content.</p>'));
        expect(result, contains('My Content'));
        expect(result, contains('<footer>Base Footer</footer>'));
      });

      test('should render pre-formatted date correctly in layout', () async {
        final testRoot = createTestRoot({
          '_layouts/post_date.liquid': '<div>Post Date: {{ page.formatted_date }}</div>',
        });
        renderer = TemplateRenderer(testRoot);
        final page = PageModel.fromMap({
          ...testPageData,
          'layoutId': 'post_date',
          'date': DateTime(2023, 1, 15),
        })..renderedContent = '';

        final result = await renderer.renderPageWithLayout(page, testConfig, dummySiteData);
        expect(result, equals('<div>Post Date: 2023-01-15</div>'));
      });
    });
  });
}

