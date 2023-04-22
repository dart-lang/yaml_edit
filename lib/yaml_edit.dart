// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// YAML parsing is supported by `package:yaml`, and each time a change is
/// made, the resulting YAML AST is compared against our expected output
/// with deep equality to ensure that the output conforms to our expectations.
///
/// **Example**
/// ```dart
library yaml_edit;

import 'package:yaml_edit/yaml_edit.dart';

///
/// ```
///
/// [1]: https://yaml.org/

export 'src/editor.dart';
export 'src/source_edit.dart';
import 'src/wrap.dart';

void main() {
  final yamlEditor = YamlEditor('{YAML: YAML}');
  yamlEditor.update(
      [],
      wrapAsCustomStyledYamlNode({
        'title': 'Short string as title',
        'description': [
          'Multiple lines with lots of text',
          'that you really makes you want',
          'the YAML to be written with literal strings',
        ].join('\n'),
      }));

  print(yamlEditor);
  // Expected Output:
  // {YAML: YAML Ain't Markup Language}
}
