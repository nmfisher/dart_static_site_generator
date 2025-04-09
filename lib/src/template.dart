// Simple Placeholder Template Engine

class Template {
  final String content;

  Template(this.content);

  // Basic recursive rendering function
  String _renderValue(dynamic value, Map<String, dynamic> context) {
    if (value is String) {
      // Render nested placeholders within string values
      return render(context, templateContent: value);
    } else if (value is Map) {
      // Could potentially render map structures, but keep simple for now
      return value.toString();
    } else if (value is List) {
       // Could potentially render list structures, but keep simple for now
      return value.toString();
    }
    return value?.toString() ?? '';
  }

  String render(Map<String, dynamic> data, { String? templateContent }) {
     String result = templateContent ?? content; // Use provided content or instance content

     // Regex to find {{ key.subkey }} or {{ key }}
     final placeholderRegex = RegExp(r'\{\{\s*([\w\.-]+)\s*\}\}');

     // Replace placeholders iteratively until no more changes
     String previousResult;
     do {
        previousResult = result;
        result = result.replaceAllMapped(placeholderRegex, (match) {
           final String keyPath = match.group(1)!;
           final keys = keyPath.split('.');

           dynamic currentValue = data;
           try {
              for (final key in keys) {
                 if (currentValue is Map) {
                    if (currentValue.containsKey(key)) {
                       currentValue = currentValue[key];
                    } else {
                       // Key not found, return placeholder text or empty string
                       print("Warning: Placeholder '{{$keyPath}}' not found in data.");
                       return '{{$keyPath}}'; // Or return ''
                    }
                 } else if (currentValue is List && int.tryParse(key) != null) {
                    // Basic list index access (not robust)
                    currentValue = currentValue[int.parse(key)];
                 }
                  else {
                    // Cannot navigate further
                    print("Warning: Cannot access key '$key' in path '$keyPath'. Value is not a Map.");
                    return '{{$keyPath}}'; // Or return ''
                 }
              }
              // Render the final value (handles nested placeholders in strings)
              return _renderValue(currentValue, data);
           } catch (e) {
              print("Error rendering placeholder '{{$keyPath}}': $e");
              return '{{$keyPath}}'; // Return placeholder on error
           }
        });
     } while (result != previousResult);


    // Handle simple {{content}} specifically (often the main markdown output)
    // This check avoids issues if 'content' itself contains {{...}}
    if (data.containsKey('content') && data['content'] is String) {
       result = result.replaceAll('{{content}}', data['content'] as String);
    }


    return result;
  }
}

// Placeholder Template Parser (just creates a Template)
class TemplateParser {
  static Template parse(String content) {
    print('Parsing template...');
    return Template(content);
  }
}
