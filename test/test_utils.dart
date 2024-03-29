// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:yaml_edit/src/equality.dart';
import 'package:yaml_edit/src/errors.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Asserts that a string containing a single YAML document is unchanged
/// when dumped right after loading.
void Function() expectLoadPreservesYAML(String source) {
  final doc = YamlEditor(source);
  return () => expect(doc.toString(), equals(source));
}

/// Asserts that [builder] has the same internal value as [expected].
void expectYamlBuilderValue(YamlEditor builder, Object expected) {
  final builderValue = builder.parseAt([]);
  expectDeepEquals(builderValue, expected);
}

/// Asserts that [actual] has the same internal value as [expected].
void expectDeepEquals(Object? actual, Object expected) {
  expect(
      actual, predicate((actual) => deepEquals(actual, expected), '$expected'));
}

Matcher notEquals(dynamic expected) => isNot(equals(expected));

/// A matcher for functions that throw [PathError].
Matcher throwsPathError = throwsA(isA<PathError>());

/// A matcher for functions that throw [AliasException].
Matcher throwsAliasException = throwsA(isA<AliasException>());

/// Enum to hold the possible modification methods.
enum YamlModificationMethod {
  appendTo,
  insert,
  prependTo,
  remove,
  splice,
  update,
}
