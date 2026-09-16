import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

class RebuildQueue {
  final Future<void> Function() build;
  final void Function(Object)? onError;
  bool _requested = false;
  Future<void>? _running;
  RebuildQueue(this.build, {this.onError});
  Future<void> request() {
    _requested = true;
    return _running ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_requested) {
        _requested = false;
        try {
          await Future.sync(build);
        } catch (error) {
          onError?.call(error);
        }
      }
    } finally {
      _running = null;
    }
  }

  Future<void> get idle => _running ?? Future.value();
}

class PreviewServer {
  final String outputDir;
  String basePath;
  final Set<HttpResponse> _clients = {};
  HttpServer? _server;
  Timer? _heartbeat;
  int _revision = 0;
  PreviewServer(this.outputDir, {this.basePath = ''});
  int get port => _server!.port;
  Future<void> start({String host = '127.0.0.1', int port = 8080}) async {
    _server = await HttpServer.bind(host, port);
    _server!.listen(_handle);
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      for (final client in _clients.toList()) {
        try {
          client.write(': heartbeat\n\n');
        } catch (_) {
          _clients.remove(client);
        }
      }
    });
  }

  void changed() {
    _revision++;
    _broadcast({'revision': _revision});
  }

  void failed(Object error) => _broadcast({'error': error.toString()});
  void _broadcast(Map<String, dynamic> value) {
    for (final client in _clients.toList()) {
      try {
        client.write('data: ${jsonEncode(value)}\n\n');
      } catch (_) {
        _clients.remove(client);
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      var path = Uri.decodeComponent(request.uri.path);
      if (basePath.isNotEmpty) {
        if (path == basePath) {
          response.redirect(Uri.parse('$basePath/'));
          return;
        }
        if (!path.startsWith('$basePath/')) {
          response.statusCode = 404;
          await response.close();
          return;
        }
        path = path.substring(basePath.length);
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = 405;
        await response.close();
        return;
      }
      if (path == '/__reload') {
        if (request.method == 'HEAD') {
          await response.close();
          return;
        }
        response.headers
            .set(HttpHeaders.contentTypeHeader, 'text/event-stream');
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        response.bufferOutput = false;
        response.write(': connected\n\n');
        _clients.add(response);
        response.done.then((_) => _clients.remove(response),
            onError: (_) => _clients.remove(response));
        return;
      }
      final segments = path.split('/');
      if (path.contains('\\') || segments.any((s) => s.startsWith('.'))) {
        response.statusCode = 403;
        await response.close();
        return;
      }
      final root = p.normalize(p.absolute(outputDir));
      var target = p.normalize(p.join(root, path.substring(1)));
      if (target != root && !p.isWithin(root, target)) {
        response.statusCode = 403;
        await response.close();
        return;
      }
      if (await Directory(target).exists()) {
        if (!path.endsWith('/')) {
          response.redirect(request.uri.replace(path: '${request.uri.path}/'));
          return;
        }
        target = p.join(target, 'index.html');
      }
      var file = File(target);
      if (!await file.exists()) {
        response.statusCode = 404;
        file = File(p.join(root, '404.html'));
        if (!await file.exists()) {
          response.write('Page not found');
          await response.close();
          return;
        }
      }
      final realRoot = await Directory(root).resolveSymbolicLinks();
      final realFile = await file.resolveSymbolicLinks();
      if (!p.isWithin(realRoot, realFile)) {
        response.statusCode = 403;
        await response.close();
        return;
      }
      final type = lookupMimeType(file.path) ?? 'application/octet-stream';
      response.headers.set(HttpHeaders.contentTypeHeader, type);
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method != 'HEAD') {
        if (type == 'text/html') {
          final html = await file.readAsString();
          final injection = _reloadScript();
          response.write(html.contains('</body>')
              ? html.replaceFirst('</body>', '$injection</body>')
              : '$html$injection');
        } else {
          await response.addStream(file.openRead());
        }
      }
      await response.close();
    } catch (_) {
      try {
        response.statusCode = 500;
        response.write('Preview is temporarily unavailable');
        await response.close();
      } catch (_) {}
    }
  }

  String _reloadScript() => '''<script>
(() => {
  const events = new EventSource(${jsonEncode('$basePath/__reload').replaceAll('<', r'\u003c')});
  events.onmessage = event => {
    const data = JSON.parse(event.data);
    if (!data.error) { location.reload(); return; }
    let notice = document.getElementById('__build-error');
    if (!notice) {
      notice = document.createElement('pre'); notice.id = '__build-error'; notice.setAttribute('role','alert');
      notice.style.cssText = 'position:fixed;bottom:0;left:0;right:0;margin:0;padding:1rem;background:#400;color:white;z-index:99999;white-space:pre-wrap;max-height:40vh;overflow:auto';
      document.body.append(notice);
    }
    notice.textContent = 'Build failed. Showing the last successful build.\\n' + data.error;
  };
})();
</script>''';
  Future<void> close() async {
    _heartbeat?.cancel();
    for (final client in _clients.toList()) {
      unawaited(client.close());
    }
    _clients.clear();
    await _server?.close(force: true);
  }
}
