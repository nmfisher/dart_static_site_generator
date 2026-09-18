import 'package:liquify/liquify.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> data(Map<String, dynamic> alternates) => {
        'site': {
          'i18n': {
            'default': {'code': 'en'}
          }
        },
        'page': {
          'extras': {
            'alternates': alternates,
          }
        },
      };

  // Workaround-free rendering, to judge upstream behaviour on its own.
  String raw(String template, Map<String, dynamic> d) =>
      Template.parse(template, data: d).render();

  test('nested if inside for', () {
    final out = raw(
        '{% for pair in page.extras.alternates %}'
        '{% if pair[0] == "en" %}X{% endif %}'
        '{% endfor %}',
        data({'en': '/', 'de': '/de/'}));
    // Correct output would be 'X'.
    print('nested-if-in-for   -> $out');
  });

  test('literal if with dotted variable', () {
    final out = raw(
        '{% if site.i18n.default.code == "en" %}X{% endif %}',
        data({'en': '/'}));
    // Correct output would be 'X'.
    print('literal-if-dotted  -> $out');
  });

  test('bracket access with variable key', () {
    final out = raw(
        '{{ alternates[site.i18n.default.code] }}',
        data({'en': '/en-route'}));
    // Correct output would be '/en-route' (liquid-possible in Shopify).
    print('var-key-bracket    -> $out');
  });

  test('for with if...else (else branch)', () {
    final out = raw(
        '{% for pair in page.extras.alternates %}'
        '{% if pair[0] == "de" %}D{% else %}o{% endif %}'
        '{% endfor %}',
        data({'en': '/', 'de': '/de/'}));
    // Correct output would be 'oD'.
    print('for-if-else        -> $out');
  });
}
