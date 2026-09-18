/// Regression probes for the liquify templating engine behaviours that
/// ticket 001 (i18n hreflang rendering in `seo.liquid`) depends on.
///
/// liquify 1.3.1 rendered nested `{% if %}` inside `{% for %}` as literal
/// text; upgrading to ^1.6.1 fixed it. These tests pin the fixed behaviours
/// so a future downgrade / regression is caught immediately.
///
/// Shopify reference semantics ("Liquid for Designers"): hash access is
/// `my_variable[<KEY EXPRESSION>]` where the key may be "an expression that
/// resolves to a string". liquify 1.6.1 cannot parse a variable-key bracket
/// lookup (ParsingException), so `seo.liquid` uses the equivalent
/// `for` + literal-comparison idiom instead. The last test pins that
/// limitation: if it starts failing, liquify gained the feature and
/// `seo.liquid` can be simplified.
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
    expect(out, 'X');
  });

  test('literal if with dotted variable', () {
    final out = raw('{% if site.i18n.default.code == "en" %}X{% endif %}',
        data({'en': '/'}));
    expect(out, 'X');
  });

  test('for with if...else (else branch)', () {
    final out = raw(
        '{% for pair in page.extras.alternates %}'
        '{% if pair[0] == "de" %}D{% else %}o{% endif %}'
        '{% endfor %}',
        data({'en': '/', 'de': '/de/'}));
    expect(out, 'oD');
  });

  test('bracket access with variable key is unsupported (ParsingException)',
      () {
    // Shopify Liquid resolves the key expression ('/en-route'); liquify
    // 1.6.1 fails at parse time. seo.liquid avoids this construct.
    // Note: liquify has two ParsingException classes and only the
    // non-throwing one is exported, so assert on the message, not the type.
    expectLater(
        () => raw('{{ alternates[site.i18n.default.code] }}',
            data({'en': '/en-route'})),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message',
                contains('ParsingException'))
            .having((e) => e.toString(), 'detail', contains('expected'))));
  });
}
