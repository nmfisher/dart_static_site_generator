import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:blog_builder/blog_builder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
      'rebuild queue coalesces edits, never overlaps, and recovers after failure',
      () async {
    final gate = Completer<void>();
    var calls = 0, active = 0, maximum = 0;
    final errors = <Object>[];
    final queue = RebuildQueue(() async {
      calls++;
      active++;
      if (active > maximum) maximum = active;
      try {
        if (calls == 1) {
          await gate.future;
          throw StateError('bad build');
        }
      } finally {
        active--;
      }
    }, onError: errors.add);
    final first = queue.request();
    queue.request();
    queue.request();
    queue.request();
    gate.complete();
    await first;
    expect(calls, 2);
    expect(maximum, 1);
    expect(errors, hasLength(1));
    await queue.request();
    expect(calls, 3);
  });

  test('rebuild queue also recovers from synchronously thrown errors',
      () async {
    var calls = 0;
    final queue = RebuildQueue(() {
      calls++;
      throw StateError('fail');
    });
    await queue.request();
    await queue.request();
    expect(calls, 2);
  });

  group('preview HTTP server', () {
    late Directory temp;
    late PreviewServer server;
    late HttpClient client;
    late Uri base;
    Future<(int, String, HttpHeaders)> get(String path,
        {String method = 'GET'}) async {
      final request = await client.openUrl(method, base.resolve(path));
      final response = await request.close();
      return (
        response.statusCode,
        await utf8.decoder.bind(response).join(),
        response.headers
      );
    }

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('blog-preview-');
      final output = Directory(p.join(temp.path, 'out'))..createSync();
      File(p.join(output.path, 'index.html'))
          .writeAsStringSync('<body>Home</body>');
      File(p.join(output.path, 'search-index.json')).writeAsStringSync('[]');
      File(p.join(output.path, '.secret')).writeAsStringSync('hidden');
      final outside = File(p.join(temp.path, 'secret.txt'))
        ..writeAsStringSync('outside');
      Link(p.join(output.path, 'escape.txt')).createSync(outside.path);
      Directory(p.join(output.path, 'post')).createSync();
      File(p.join(output.path, 'post', 'index.html')).writeAsStringSync('Post');
      server = PreviewServer(output.path, basePath: '/docs');
      await server.start(port: 0);
      client = HttpClient();
      base = Uri.parse('http://127.0.0.1:${server.port}/');
    });
    tearDown(() async {
      client.close(force: true);
      await server.close();
      await temp.delete(recursive: true);
    });
    test('serves mounted pages, adds reload only to HTML, and supports HEAD',
        () async {
      final home = await get('/docs/');
      expect(home.$1, 200);
      expect(home.$2, contains('Home'));
      expect(home.$2, contains('new EventSource("/docs/__reload")'));
      expect(home.$3.contentType!.mimeType, 'text/html');
      final json = await get('/docs/search-index.json');
      expect(json.$2, '[]');
      expect(json.$3.contentType!.mimeType, 'application/json');
      expect((await get('/docs/', method: 'HEAD')).$2, isEmpty);
      expect((await get('/docs/post')).$2, contains('Post'));
      expect((await get('/')).$1, 404);
      expect((await get('/docs/missing')).$1, 404);
      expect((await get('/docs/', method: 'POST')).$1, 405);
    });
    test('blocks hidden files and symlinks escaping output', () async {
      expect((await get('/docs/.secret')).$1, 403);
      expect((await get('/docs/escape.txt')).$1, 403);
      expect((await get('/docs/%2e%2e/secret.txt')).$1, isNot(200));
    });
    test('streams reload and build failure events', () async {
      final request = await client.getUrl(base.resolve('/docs/__reload'));
      final response = await request.close();
      expect(response.headers.contentType!.mimeType, 'text/event-stream');
      final lines = StreamIterator(
          utf8.decoder.bind(response).transform(const LineSplitter()));
      expect(
          await lines.moveNext().timeout(const Duration(seconds: 3)), isTrue);
      expect(lines.current, ': connected');
      server.failed(StateError('invalid layout'));
      server.changed();
      final events = <String>[];
      while (events.length < 2 &&
          await lines.moveNext().timeout(const Duration(seconds: 3))) {
        if (lines.current.startsWith('data:')) events.add(lines.current);
      }
      expect(events.first, contains('invalid layout'));
      expect(events.last, contains('"revision":1'));
      await lines.cancel();
    });
  });
}
