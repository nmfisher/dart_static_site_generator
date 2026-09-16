import 'dart:isolate';
import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/renderer.dart';
import 'package:blog_builder/src/site_data_model.dart';
import 'package:html/parser.dart' as html;
import 'package:liquify/liquify.dart';
import 'package:test/test.dart';

void main() {
  late TemplateRenderer renderer;
  setUpAll(() async {
    final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:blog_builder/src/defaults/'));
    renderer = TemplateRenderer(
        FileSystemRoot(uri!.toFilePath(), throwOnMissing: true));
  });
  for (final layout in ['default', 'home', 'post', 'list']) {
    test('bundled $layout renders real page data and inherited partials',
        () async {
      final child = PageModel.fromMap({
        'title': 'Child post',
        'route': '/posts/child',
        'date': DateTime(2024, 1, 15)
      });
      final page = layout == 'list'
          ? PageIndexPageModel.fromMap({
              'title': 'Page title',
              'route': '/posts',
              'layoutId': layout,
              'children': [child]
            })
          : PageModel.fromMap({
              'title': 'Page title',
              'route': '/page',
              'layoutId': layout,
              'date': DateTime(2024, 1, 15),
              'atUri': 'at://did:plc:test/app.bsky.feed.post/test'
            });
      page.renderedContent = '<p>Rendered <strong>body</strong></p>';
      final site = SiteData(name: 'root', route: '/', children: {
        'posts': SiteData(name: 'posts', route: '/posts', pages: [child])
      });
      final result = await renderer.renderPageWithLayout(
          page,
          ConfigModel(
              title: 'Site title',
              owner: 'Site owner',
              metadata: {},
              atProto:
                  AtProtoConfig(enabled: true, turnstileSiteKey: 'test-key')),
          site);
      final doc = html.parse(result);
      expect(doc.querySelector('title')!.text, 'Page title - Site title');
      expect(doc.querySelector('.site-title')!.text, contains('Site title'));
      expect(doc.querySelector('.site-footer')!.text, contains('Site owner'));
      expect(
          doc.querySelector('.site-footer')!.text, matches(RegExp(r'© \d{4}')));
      if (layout != 'list') expect(result, contains(page.renderedContent));
      if (layout == 'post') {
        expect(doc.querySelector('.post-content')!.innerHtml.trim(),
            page.renderedContent);
        expect(doc.querySelector('#comments-section'), isNotNull);
        expect(result, contains('at://did:plc:test/app.bsky.feed.post/test'));
        expect(result, contains('test-key'));
      }
      if (layout != 'default') {
        expect(doc.querySelector('time')!.text.trim(), 'January 15, 2024');
        expect(doc.querySelector('time')!.attributes['datetime'], '2024-01-15');
      }
    });
  }
}
