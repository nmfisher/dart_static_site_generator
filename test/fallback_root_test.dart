import 'package:blog_builder/src/fallback_root.dart';
import 'package:liquify/liquify.dart';
import 'package:test/test.dart';

class BrokenRoot implements Root {
  @override
  Source resolve(String path) => throw StateError('Storage failed');
  @override
  Future<Source> resolveAsync(String path) async => resolve(path);
}

void main() {
  test('falls back for missing templates in sync and async rendering',
      () async {
    final root = FallbackRoot(MapRoot({}, throwOnMissing: true),
        MapRoot({'partial': 'fallback'}, throwOnMissing: true));
    expect(root.resolve('partial').content, 'fallback');
    expect((await root.resolveAsync('partial')).content, 'fallback');
    expect(() => root.resolve('missing'),
        throwsA(isA<TemplateNotFoundException>()));
    await expectLater(root.resolveAsync('missing'),
        throwsA(isA<TemplateNotFoundException>()));
  });
  test('preserves intentionally empty partial overrides', () async {
    final root = FallbackRoot(MapRoot({'partial': ''}, throwOnMissing: true),
        MapRoot({'partial': 'fallback'}, throwOnMissing: true));
    expect(root.resolve('partial').content, '');
    expect((await root.resolveAsync('partial')).content, '');
  });
  test('does not conceal unrelated storage errors', () async {
    final root = FallbackRoot(
        BrokenRoot(), MapRoot({'partial': 'fallback'}, throwOnMissing: true));
    expect(() => root.resolve('partial'), throwsStateError);
    await expectLater(root.resolveAsync('partial'), throwsStateError);
  });
}
