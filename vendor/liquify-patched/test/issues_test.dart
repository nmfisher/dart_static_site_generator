import 'package:liquify/liquify.dart';
import 'package:liquify/src/context.dart';
import 'package:liquify/src/evaluator.dart';
import 'package:test/test.dart';
import 'support/shared.dart';

void main() {
  late Evaluator evaluator;

  setUp(() {
    evaluator = Evaluator(Environment());
  });

  tearDown(() {
    evaluator.context.clear();
  });

  test("issue #23", () async {
    await testParser(
      '''
{% assign name = "hello" %}
{% if name contains "ello" %}
These shoes are awesome! {{name}}
{% endif %}
    ''',
      (document) {
        evaluator.evaluateNodes(document.children);
        expect(
          evaluator.buffer.toString().trim(),
          equals('These shoes are awesome! hello'),
        );
      },
    );
  });

  test("hash key can be any expression (root array access)", () async {
    await testParser(
      '''
{{ my_hash[site.i18n.default.code] }}
    ''',
      (document) {
        evaluator.context.setVariable('my_hash', {
          'en': '/en-route',
          'fr': '/fr-route',
        });
        evaluator.context.setVariable('site', {
          'i18n': {
            'default': {'code': 'en'},
          },
        });
        evaluator.evaluateNodes(document.children);
        expect(
          evaluator.buffer.toString().trim(),
          equals('/en-route'),
        );
      },
    );
  });

  test("hash key can be any expression (member chain)", () async {
    await testParser(
      '''
{{ wrapper.data[key.name] }}
    ''',
      (document) {
        evaluator.context.setVariable('wrapper', {
          'data': {'deep': 'found'},
        });
        evaluator.context.setVariable('key', {'name': 'deep'});
        evaluator.evaluateNodes(document.children);
        expect(
          evaluator.buffer.toString().trim(),
          equals('found'),
        );
      },
    );
  });

  test("list index can be any expression", () async {
    await testParser(
      '''
{{ wrap.list[i] }}
    ''',
      (document) {
        evaluator.context.setVariable('wrap', {
          'list': [10, 20, 30],
        });
        evaluator.context.setVariable('i', 1);
        evaluator.evaluateNodes(document.children);
        expect(
          evaluator.buffer.toString().trim(),
          equals('20'),
        );
      },
    );
  });
}
