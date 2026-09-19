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

  test('bracket access with variable key', () {
    // Shopify Liquid: "For hashes, the key must be a literal quoted string
    // or an expression that resolves to a string." liquify 1.6.1 only
    // parsed literal keys; the vendored patch (vendor/liquify) widens the
    // grammar to ref0(expression) and evaluates the key in member chains.
    // Pending upstream PR.
    final out = raw(
        '{% assign t = page.extras.alternates %}'
        '{{ t[site.i18n.default.code] }}',
        data({'en': '/en-route'}));
    expect(out, '/en-route');
  });

  test('bracket access with nested expressions', () {
    // The widened grammar composes: expression keys, including lookups on
    // the result of another lookup.
    final out = Template.parse('{{ a[b.k] }}', data: {
      'a': {'x': 'deep'},
      'b': {'k': 'x'},
    }).render();
    expect(out, 'deep');
  });

  test('member chain ending in expression key', () {
    // x.y[key] — the chain form that needed evaluator support, not just
    // grammar.
    final out = Template.parse('{{ wrap.list[i] }}', data: {
      'wrap': {
        'list': [10, 20, 30],
      },
      'i': 1,
    }).render();
    expect(out, '20');
  });
}
