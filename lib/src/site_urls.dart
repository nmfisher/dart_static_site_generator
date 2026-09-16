import 'config_models.dart';

class SiteUrls {
  final String basePath;
  final Uri? baseUrl;
  SiteUrls(ConfigModel config)
      : basePath = config.basePath,
        baseUrl = config.baseUrl == null ? null : Uri.parse(config.baseUrl!);

  String relative(dynamic value) {
    final text = value?.toString() ?? '';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        text.startsWith('#') ||
        text.startsWith('?')) return text;
    final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
    final mounted =
        basePath.isEmpty || path == basePath || path.startsWith('$basePath/')
            ? path
            : '$basePath$path';
    return uri.replace(path: mounted).toString();
  }

  String absolute(dynamic value) {
    final local = relative(value);
    final uri = Uri.tryParse(local);
    if (uri == null || uri.hasScheme || uri.hasAuthority || baseUrl == null)
      return local;
    return baseUrl!.resolve(local).toString();
  }

  String? unmount(String path) {
    if (basePath.isEmpty) return path;
    if (path == basePath) return '/';
    return path.startsWith('$basePath/')
        ? path.substring(basePath.length)
        : null;
  }
}
