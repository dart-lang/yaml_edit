[![Dart CI](https://github.com/dart-lang/yaml_edit/actions/workflows/test-package.yml/badge.svg)](https://github.com/dart-lang/yaml_edit/actions/workflows/test-package.yml)
[![pub package](https://img.shields.io/pub/v/yaml_edit.svg)](https://pub.dev/packages/yaml_edit)
[![package publisher](https://img.shields.io/pub/publisher/yaml_edit.svg)](https://pub.dev/packages/yaml_edit/publisher)

A library for [YAML](https://yaml.org) manipulation while preserving comments.

## Usage

A simple usage example:

```dart
import 'package:yaml_edit/yaml_edit.dart';

void main() {
  final yamlEditor = YamlEditor('{YAML: YAML}');
  yamlEditor.update(['YAML'], "YAML Ain't Markup Language");
  print(yamlEditor);
  // Expected output:
  // {YAML: YAML Ain't Markup Language}
}
```

## Testing

Testing is done in two strategies: Unit testing (`/test/editor_test.dart`) and
Golden testing (`/test/golden_test.dart`). More information on Golden testing
and the input/output format can be found at `/test/testdata/README.md`.

These tests are automatically run with `pub run test`.

## Limitations

1. Users are not allowed to define tags in the modifications.
2. Map keys will always be added in the flow style.
