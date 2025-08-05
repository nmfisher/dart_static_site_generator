import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/renderer.dart';
import 'package:liquify/liquify.dart';
import 'package:test/test.dart';
import 'package:blog_builder/src/site_data_model.dart'; // New import

void main() {
  group('TemplateRenderer', () {
    late TemplateRenderer renderer;
    late ConfigModel testConfig;
    late SiteData dummySiteData; // New field

    final testPageData = {
      'rawMarkdown': 'Test content', // Changed from html and markdown
      'title': 'Test Page Title',
      'route': '/test-page',
      'source': '/path/to/source.md',
      'blurb': 'Test blurb',
      'metadata': {'custom_key': 'custom value', 'og:title': 'Test OG Title'},
      'date': DateTime(2023, 10, 27),
      'draft': false,
      'isIndex': false,
    };

    final testIndexPageData = {
      'rawMarkdown': '', // Index pages often rely on layout for content structure
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
          rawMarkdown: 'Child 1 md', // Changed from html and markdown
          title: 'Child Page 1',
          route: '/test-index/child1',
          source: '/path/to/test-index/child1.md',
          blurb: 'Child 1 blurb',
          metadata: {},
          date: DateTime(2023, 10, 26),
          draft: false,
        ),
        PageModel(
          rawMarkdown: 'Child 2 md', // Changed from html and markdown
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

    // Common template definitions used by block tests
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
            {{ content }} {# Renders the page.html content by default #}
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
      dummySiteData = SiteData(name: 'dummy', route: '/'); // Initialize dummy SiteData
    });

    MapRoot createTestRoot(Map<String, String> templates) {
      return MapRoot(templates);
    }

    test('should return correct path for default layout', () {
      final testRoot = createTestRoot({
        '_layouts/default.liquid': '<html></html>',
        '_layouts/list.liquid': '<html></html>',
      });

      renderer = TemplateRenderer(testRoot);
      final path = renderer.resolveLayoutPath(null, false);
      expect(path, equals('_layouts/default.liquid'));
    });

    test('should return correct path for list layout (index)', () {
      final testRoot = createTestRoot({
        '_layouts/default.liquid': '<html></html>',
        '_layouts/list.liquid': '<html></html>',
      });

      renderer = TemplateRenderer(testRoot);
      final path = renderer.resolveLayoutPath(null, true);
      expect(path, equals('_layouts/list.liquid'));
    });

    test('should return correct path for custom layout', () {
      final testRoot = createTestRoot({
        '_layouts/custom.liquid': '<html></html>',
      });

      renderer = TemplateRenderer(testRoot);
      final path = renderer.resolveLayoutPath('custom', false);
      expect(path, equals('_layouts/custom.liquid'));
    });

    test('should return correct path for custom layout (index)', () {
      final testRoot = createTestRoot({
        '_layouts/custom.liquid': '<html></html>',
      });

      renderer = TemplateRenderer(testRoot);
      final path = renderer.resolveLayoutPath('custom', true);
      expect(path, equals('_layouts/custom.liquid'));
    });

    test(
        'should throw exception if template specified by layoutId cannot be resolved/found',
        () async {
      final testRoot = createTestRoot({
        '_layouts/default.liquid': '<html></html>',
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'nonexistent',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      expectLater(
        () => renderer.renderPage(page),
        throwsA(
            isA<Exception>()),
      );
    });

    test('should throw exception if resolved template file is empty', () async {
      final testRoot = createTestRoot({
        '_layouts/empty.liquid': '',
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'empty',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      // Liquify itself might handle empty templates differently,
      // but we expect our renderer to potentially throw if the *result* is empty.
      // Let's refine the check to expect an empty result exception later.
      expectLater(
         () => renderer.renderPage(page),
          throwsA(isA<Exception>()),
      );
    });

     test(
        'should throw exception if rendered content is empty or whitespace only',
        () async {
      final testRoot = createTestRoot({
        '_layouts/empty_output.liquid':
            '{% if false %}This should not render{% endif %}', // Renders nothing
        '_layouts/whitespace_output.liquid': '   \n  \t ', // Renders only whitespace
      });

      renderer = TemplateRenderer(testRoot);

      final emptyOutputPage = PageModel(
        layoutId: 'empty_output',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

       final whitespaceOutputPage = PageModel(
        layoutId: 'whitespace_output',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      expectLater(
        () => renderer.renderPage(emptyOutputPage),
        throwsA(isA<Exception>()),
      );
       expectLater(
        () => renderer.renderPage(whitespaceOutputPage),
        throwsA(isA<Exception>()),
      );
    });


    test('should render content successfully using default layout', () async {
      final testRoot = createTestRoot({
        '_layouts/default.liquid':
            '<html><head><title>Default - {{ page.title }}</title></head><body>Default Layout: {{ content }}</body></html>',
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: null, // Explicitly null for default
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      final result = await renderer.renderPage(page);
      expect(
          result,
          equals(
              '<html><head><title>Default - Test Page Title</title></head><body>Default Layout: <p>Test content</p>\n</body></html>'));
    });

    test(
        'should render content successfully using custom layout and access page metadata',
        () async {
      final testRoot = createTestRoot({
        '_layouts/custom.liquid':
            '<html><head><title>Custom - {{ page.title }}</title></head><body><h1>{{ page.title }} ({{ page.metadata.custom_key }})</h1>{{ content }}</body></html>',
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'custom',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      final result = await renderer.renderPage(page);
      expect(
          result,
          equals(
              '<html><head><title>Custom - Test Page Title</title></head><body><h1>Test Page Title (custom value)</h1><p>Test content</p>\n</body></html>'));
    });

    test('should include site config in rendered output', () async {
      final testRoot = createTestRoot({
        '_layouts/site.liquid':
            '<html><head><title>{{ site.title }} - {{ page.title }}</title></head><body>Site Owner: {{ site.owner }} | {{ content }}</body></html>',
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'site',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      final result = await renderer.renderPageWithSiteConfig(page, testConfig, dummySiteData);
      expect(
          result,
          equals(
              '<html><head><title>Test Site - Test Page Title</title></head><body>Site Owner: Tester | <p>Test content</p>\n</body></html>'));
    });

    test('should render index page using list layout and access children',
        () async {
      final testRoot = createTestRoot({
        '_layouts/list.liquid':
            '<html><head><title>List - {{ page.title }}</title></head><body><h1>List</h1>\n<ul>{% for item in page.children %}<li><a href="{{ item.route }}">{{ item.title }}</a></li>{% endfor %}</ul>\n{{ content }}</body></html>',
      });

      renderer = TemplateRenderer(testRoot);

      final indexPage = PageIndexPageModel(
        layoutId: null, // Use default for index -> list.liquid
        rawMarkdown: testIndexPageData['rawMarkdown'] as String, // Changed
        title: testIndexPageData['title'] as String,
        route: testIndexPageData['route'] as String,
        source: testIndexPageData['source'] as String,
        blurb: testIndexPageData['blurb'] as String,
        metadata: testIndexPageData['metadata'] as Map<String, String>,
        children: testIndexPageData['children'] as List<PageModel>,
        // Note: isIndex is implicit in PageIndexPageModel
      );

      final result = await renderer.renderPage(indexPage);

      expect(result, contains('<h1>List</h1>'));
      expect(result,
          contains('<li><a href="/test-index/child1">Child Page 1</a></li>'));
      expect(result,
          contains('<li><a href="/test-index/child2">Child Page 2</a></li>'));
      expect(result, matches(RegExp(r'<ul>.*</ul>', dotAll: true)));
      // Index html is empty, so {{ content }} renders nothing
      expect(result, endsWith('</ul>\n\n</body></html>'));
    });

    test('should render page with include correctly', () async {
      final testRoot = createTestRoot({
        '_layouts/with_include.liquid':
            '{% render "_includes/header.liquid" with site: site %}<html><body>{{ content }}</body></html>',
        '_includes/header.liquid': '<header>Site: {{ site.title }}</header>',
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'with_include',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String,
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      final result = await renderer.renderPageWithSiteConfig(page, testConfig, dummySiteData);

      expect(
          result,
          equals(
              '<header>Site: Test Site</header><html><body><p>Test content</p>\n</body></html>'));
    });

     test('should render content using layout blocks correctly', () async {
      final testRoot = createTestRoot({
        '_layouts/page_with_blocks.liquid': pageWithBlocksLayoutContent,
        '_layouts/base.liquid': baseLayoutContent,
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'page_with_blocks',
        rawMarkdown: testPageData['rawMarkdown'] as String, // Changed
        title: testPageData['title'] as String, // This will be overridden by the block
        route: testPageData['route'] as String,
        source: testPageData['source'] as String,
        blurb: testPageData['blurb'] as String,
        metadata: testPageData['metadata'] as Map<String, String>,
        date: testPageData['date'] as DateTime?,
        draft: testPageData['draft'] as bool,
        isIndex: testPageData['isIndex'] as bool,
      );

      final result = await renderer.renderPageWithSiteConfig(page, testConfig, dummySiteData);
      // print(result); // Keep for debugging if needed

      expect(result, startsWith('<!DOCTYPE html>'));
      expect(result, contains('<html>'));
      expect(result, contains('<body>'));
      expect(result, contains('<header>'));
      expect(result, contains('<main>'));
      expect(result, contains('<footer>'));
      expect(result, endsWith('</html>'));

      // --- Check Overridden Blocks ---
      expect(
          result, contains('<title>Specific Child Title - Test Site</title>'),
          reason: "Title block should be overridden");
      expect(
          result, contains('<meta name="author" content="Block Test Author">'),
          reason: "Head Extra block should be overridden");
      expect(result, contains('<h2>Overridden Content Heading</h2>'),
          reason: "Main content block should be overridden (heading)");
      expect(
          result, contains('<p>This content comes from the child block.</p>'),
          reason: "Main content block should be overridden (paragraph)");
      expect(result, contains('<p>Test content</p>'), // From {{ content }} inside overridden block
          reason:
              "Main content block should include original page html via {{ content }}");
      expect(result, contains('<script src="/child.js"></script>'),
          reason: "Scripts block should be overridden");

      // --- Check Non-Overridden (Base) Blocks ---
      expect(result, contains('<header>Base Header</header>'),
          reason: "Header block should use base default");
      expect(result, contains('<footer>Base Footer</footer>'),
          reason: "Footer block should use base default");

      // --- Check Absence of Base Defaults That Were Overridden ---
      expect(result, isNot(contains('Default Base Title')),
          reason: "Default base title should not be present");
      expect(result, isNot(contains('<h1>Default Content Area</h1>')),
          reason: "Default base main content H1 should not be present");
      expect(result, isNot(contains('<p>Base layout content.</p>')),
          reason: "Default base main content P should not be present");
      expect(result, isNot(contains('<!-- Default Scripts -->')),
          reason: "Default scripts comment should not be present");
      expect(result, isNot(contains('<!-- Extra head elements -->')),
          reason: "Default head extra comment should not be present");
    });


    test('should render content using base layout directly without blocks', () async {
      const selfExtendBaseLayoutContent = '{% layout \'_layouts/base.liquid\' %}';

      final testRoot = createTestRoot({
        '_layouts/base.liquid': baseLayoutContent,
        '_layouts/self_extend_base.liquid': selfExtendBaseLayoutContent,
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'self_extend_base', // Use the self-extending layout
        rawMarkdown: 'Some content',
        title: 'Hardcoded Page Title', // Hardcode the title
        route: '/test-page',
        source: '/path/to/source.md',
        blurb: 'A blurb',
        metadata: {},
        date: DateTime(2023, 1, 1),
        draft: false,
        isIndex: false,
      );

      final result = await renderer.renderPageWithSiteConfig(page, testConfig, dummySiteData);
      // print(result); // Keep for debugging if needed

      expect(result, startsWith('<!DOCTYPE html>'));
      expect(result, contains('<html>'));
      expect(result, contains('<body>'));
      expect(result, contains('<header>'));
      expect(result, contains('<main>'));
      expect(result, contains('<footer>'));
      expect(result, endsWith('</html>'));

      // --- Check Base Defaults are Used ---
      expect(
          result, contains('<title>Hardcoded Page Title - Test Site</title>'),
          reason: "Title block should use hardcoded page.title and site.title");
       // Default head_extra block is just a comment, which Liquify might render or omit.
       // It's safer to check for the *absence* of specific content than presence of a comment.
       // expect(result, contains('<!-- Extra head elements -->'), reason: "Head Extra block should use default comment");
       expect(result, isNot(contains('<meta')), reason: "No meta tags should be in default head_extra");

      expect(result, contains('<header>Base Header</header>'),
          reason: "Header block should use base default");
      expect(result, contains('<h1>Default Content Area</h1>'),
          reason: "Main content block should use base default (heading)");
      expect(result, contains('<p>Base layout content.</p>'),
          reason: "Main content block should use base default (paragraph)");
      expect(result, contains('<p>Some content</p>'), // From {{ content }} inside default block
          reason:
              "Main content block should include page html via {{ content }} in default");

      expect(result, contains('<footer>Base Footer</footer>'),
          reason: "Footer block should use base default");

      // Default scripts block is just a comment. Similar to head_extra, check absence of specific tags.
      // expect(result, contains('<!-- Default Scripts -->'), reason: "Scripts block should use default comment");
       expect(result, isNot(contains('<script')), reason: "No script tags should be in default scripts");
    });

    test('should render date properly with date filter', () async {
      final testRoot = createTestRoot({
        '_layouts/post_date.liquid':
            '<div>Post Date: {{ page.formatted_date }}</div>', // Use pre-formatted date
      });

      renderer = TemplateRenderer(testRoot);

      final page = PageModel(
        layoutId: 'post_date',
        rawMarkdown: 'Some content',
        title: 'Post with Date',
        route: '/post-with-date',
        source: '/path/to/post.md',
        blurb: 'A post blurb',
        metadata: {},
        date: DateTime(2023, 1, 15, 10, 30, 0), // January 15, 2023
        draft: false,
        isIndex: false,
      );

      final result = await renderer.renderPage(page);
      expect(result, equals('<div>Post Date: 2023-01-15</div>')); // Changed expected output
    });

  });
}
