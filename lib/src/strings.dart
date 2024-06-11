// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';

import 'utils.dart';

/// Given [value], tries to format it into a plain string recognizable by YAML.
/// If it fails, it defaults to returning a double-quoted string.
///
/// Not all values can be formatted into a plain string. If the string contains
/// an escape sequence, it can only be detected when in a double-quoted
/// sequence. Plain strings may also be misinterpreted by the YAML parser (e.g.
/// ' null').
String? _tryYamlEncodePlain(Object? value) {
  if (value is YamlNode) {
    AssertionError(
      'YamlNodes should not be passed directly into getSafeString!',
    );
  }

  assertValidScalar(value);

  if (value is String) {
    /// If it contains a dangerous character we want to wrap the result with
    /// double quotes because the double quoted style allows for arbitrary
    /// strings with "\" escape sequences.
    ///
    /// See 7.3.1 Double-Quoted Style
    /// https://yaml.org/spec/1.2/spec.html#id2787109
    return isDangerousString(value) ? null : value;
  }

  return value.toString();
}

/// Checks if [string] has unprintable characters according to
/// [unprintableCharCodes].
bool _hasUnprintableCharacters(String string) {
  final codeUnits = string.codeUnits;

  for (final key in unprintableCharCodes.keys) {
    if (codeUnits.contains(key)) return true;
  }

  return false;
}

/// Checks if a [string] has any unprintable characters or characters that
/// should be explicitly wrapped in double quotes according to
/// [unprintableCharCodes] and [doubleQuoteEscapeChars] respectively.
///
/// It should be noted that this check excludes the `\n` (line break)
/// character as it is encoded correctly when using [ScalarStyle.LITERAL] or
/// [ScalarStyle.FOLDED].
bool _shouldDoubleQuote(String string) {
  if (string.isEmpty || string.trimLeft().length != string.length) return true;

  final codeUnits = string.codeUnits;

  return doubleQuoteEscapeChars.keys
      .whereNot((charUnit) => charUnit == 10) // Anything but line breaks
      .any(codeUnits.contains);
}

/// Returns the correct block chomping indicator for [ScalarStyle.FOLDED]
/// and [ScalarStyle.LITERAL].
///
/// See https://yaml.org/spec/1.2.2/#8112-block-chomping-indicator
String _getChompingIndicator(String string) {
  /// By default, we apply an indent to the string after every new line.
  ///
  /// Apply the `keep (+)` chomping indicator for trailing whitespace to be
  /// treated as content.
  ///
  /// [NOTE]: We only check for trailing whitespace rather than `\n `. This is
  /// a coin-toss approach. If there is a new line after this, it will be kept.
  /// If not, nothing happens.
  if (string.endsWith(' ') || string.endsWith('\n')) return '+';

  return '-';
}

/// Generates a YAML-safe double-quoted string based on [string], escaping the
/// list of characters as defined by the YAML 1.2 spec.
///
/// See 5.7 Escaped Characters https://yaml.org/spec/1.2/spec.html#id2776092
String _yamlEncodeDoubleQuoted(String string) {
  final buffer = StringBuffer();
  for (final codeUnit in string.codeUnits) {
    if (doubleQuoteEscapeChars[codeUnit] != null) {
      buffer.write(doubleQuoteEscapeChars[codeUnit]);
    } else {
      buffer.writeCharCode(codeUnit);
    }
  }

  return '"$buffer"';
}

/// Encodes [string] as YAML single quoted string.
///
/// Returns `null`, if the [string] can't be encoded as single-quoted string.
/// This might happen if it contains line-breaks or [_hasUnprintableCharacters].
///
/// See: https://yaml.org/spec/1.2.2/#732-single-quoted-style
String? _tryYamlEncodeSingleQuoted(String string) {
  // If [string] contains a newline we'll use double quoted strings instead.
  // Single quoted strings can represent newlines, but then we have to use an
  // empty line (replace \n with \n\n). But since leading spaces following
  // line breaks are ignored, we can't represent "\n ".
  // Thus, if the string contains `\n` and we're asked to do single quoted,
  // we'll fallback to a double quoted string.
  if (_hasUnprintableCharacters(string) || string.contains('\n')) return null;

  final result = string.replaceAll('\'', '\'\'');
  return '\'$result\'';
}

/// Attempts to encode a [string] as a _YAML folded string_ and apply the
/// appropriate _chomping indicator_.
///
/// Returns `null`, if the [string] cannot be encoded as a _YAML folded
/// string_.
///
/// **Examples** of folded strings.
/// ```yaml
/// # With the "strip" chomping indicator
/// key: >-
///   my folded
///   string
///
/// # With the "keep" chomping indicator
/// key: >+
///   my folded
///   string
/// ```
///
/// See: https://yaml.org/spec/1.2.2/#813-folded-style
String? _tryYamlEncodeFolded(String string, int indentSize, String lineEnding) {
  if (_shouldDoubleQuote(string)) return null;

  final indent = ' ' * indentSize;

  /// Remove trailing `\n` & white-space to ease string folding
  var trimmed = string.trimRight();
  final stripped = string.substring(trimmed.length);

  final trimmedSplit =
      trimmed.replaceAll('\n', lineEnding + indent).split(lineEnding);

  /// Try folding to match specification:
  /// * https://yaml.org/spec/1.2.2/#65-line-folding
  trimmed = trimmedSplit.reduceIndexed((index, previous, current) {
    var updated = current;

    /// If initially empty, this line holds only `\n` or white-space. This
    /// tells us we don't need to apply an additional `\n`.
    ///
    /// See https://yaml.org/spec/1.2.2/#64-empty-lines
    ///
    /// If this line is not empty, we need to apply an additional `\n` if and
    /// only if:
    ///   1. The preceding line was non-empty too
    ///   2. If the current line doesn't begin with white-space
    ///
    /// Such that we apply `\n` for `foo\nbar` but not `foo\n bar`.
    if (current.trim().isNotEmpty &&
        trimmedSplit[index - 1].trim().isNotEmpty &&
        !current.replaceFirst(indent, '').startsWith(' ')) {
      updated = lineEnding + updated;
    }

    /// Apply a `\n` by default.
    return previous + lineEnding + updated;
  });

  return '>${_getChompingIndicator(string)}\n'
      '$indent$trimmed'
      '${stripped.replaceAll('\n', lineEnding + indent)}';
}

/// Attempts to encode a [string] as a _YAML literal string_ and apply the
/// appropriate _chomping indicator_.
///
/// Returns `null`, if the [string] cannot be encoded as a _YAML literal
/// string_.
///
/// **Examples** of literal strings.
/// ```yaml
/// # With the "strip" chomping indicator
/// key: |-
///   my literal
///   string
///
/// # With the "keep" chomping indicator
/// key: |+
///   my literal
///   string
/// ```
///
/// See: https://yaml.org/spec/1.2.2/#812-literal-style
String? _tryYamlEncodeLiteral(
    String string, int indentSize, String lineEnding) {
  if (_shouldDoubleQuote(string)) return null;

  final indent = ' ' * indentSize;

  /// Simplest block style.
  /// * https://yaml.org/spec/1.2.2/#812-literal-style
  return '|${_getChompingIndicator(string)}\n$indent'
      '${string.replaceAll('\n', lineEnding + indent)}';
}

///Encodes a flow [YamlScalar] based on the provided [YamlScalar.style].
///
/// Falls back to [ScalarStyle.DOUBLE_QUOTED] if the [yamlScalar] cannot be
/// encoded with the [YamlScalar.style] or with [ScalarStyle.PLAIN] when the
/// [yamlScalar] is not a [String].
String _yamlEncodeFlowScalar(YamlScalar yamlScalar) {
  final YamlScalar(:value, :style) = yamlScalar;

  final isString = value is String;

  switch (style) {
    /// Only encode as double-quoted if it's a string.
    case ScalarStyle.DOUBLE_QUOTED when isString:
      return _yamlEncodeDoubleQuoted(value);

    case ScalarStyle.SINGLE_QUOTED when isString:
      return _tryYamlEncodeSingleQuoted(value) ??
          _yamlEncodeDoubleQuoted(value);

    /// Cast into [String] if [null] as this condition only returns [null]
    /// for a [String] that can't be encoded.
    default:
      return _tryYamlEncodePlain(value) ??
          _yamlEncodeDoubleQuoted(value as String);
  }
}

/// Encodes a block [YamlScalar] based on the provided [YamlScalar.style].
///
/// Falls back to [ScalarStyle.DOUBLE_QUOTED] if the [yamlScalar] cannot be
/// encoded with the [YamlScalar.style] provided.
String _yamlEncodeBlockScalar(
  YamlScalar yamlScalar,
  int indentation,
  String lineEnding,
) {
  final YamlScalar(:value, :style) = yamlScalar;
  assertValidScalar(value);

  final isString = value is String;

  if (isString && _hasUnprintableCharacters(value)) {
    return _yamlEncodeDoubleQuoted(value);
  }

  switch (style) {
    /// Prefer 'plain', fallback to "double quoted". Cast into [String] if
    /// null as this condition only returns [null] for a [String] that can't
    /// be encoded.
    case ScalarStyle.PLAIN:
      return _tryYamlEncodePlain(value) ??
          _yamlEncodeDoubleQuoted(value as String);

    // Prefer 'single quoted', fallback to "double quoted"
    case ScalarStyle.SINGLE_QUOTED when isString:
      return _tryYamlEncodeSingleQuoted(value) ??
          _yamlEncodeDoubleQuoted(value);

    /// Prefer folded string, try literal as fallback
    /// otherwise fallback to "double quoted"
    case ScalarStyle.FOLDED when isString:
      return _tryYamlEncodeFolded(value, indentation, lineEnding) ??
          _yamlEncodeDoubleQuoted(value);

    /// Prefer literal string, try folded as fallback
    /// otherwise fallback to "double quoted"
    case ScalarStyle.LITERAL when isString:
      return _tryYamlEncodeLiteral(value, indentation, lineEnding) ??
          _yamlEncodeDoubleQuoted(value);

    /// Prefer plain, fallback to "double quoted"
    default:
      return _tryYamlEncodePlain(value) ??
          _yamlEncodeDoubleQuoted(value as String);
  }
}

/// Returns [value] with the necessary formatting applied in a flow context.
///
/// If [value] is a [YamlNode], we try to respect its [YamlScalar.style]
/// parameter where possible. Certain cases make this impossible (e.g. a plain
/// string scalar that starts with '>', a child having a block style
/// parameters), in which case we will produce [value] with default styling
/// options.
String yamlEncodeFlowString(YamlNode value) {
  if (value is YamlList) {
    final list = value.nodes;

    final safeValues = list.map(yamlEncodeFlowString);
    return '[${safeValues.join(', ')}]';
  } else if (value is YamlMap) {
    final safeEntries = value.nodes.entries.map((entry) {
      final safeKey = yamlEncodeFlowString(entry.key as YamlNode);
      final safeValue = yamlEncodeFlowString(entry.value);
      return '$safeKey: $safeValue';
    });

    return '{${safeEntries.join(', ')}}';
  }

  return _yamlEncodeFlowScalar(value as YamlScalar);
}

/// Returns [value] with the necessary formatting applied in a block context.
String yamlEncodeBlockString(
  YamlNode value,
  int indentation,
  String lineEnding,
) {
  const additionalIndentation = 2;

  if (!isBlockNode(value)) return yamlEncodeFlowString(value);

  final newIndentation = indentation + additionalIndentation;

  if (value is YamlList) {
    if (value.isEmpty) return '${' ' * indentation}[]';

    Iterable<String> safeValues;

    final children = value.nodes;

    safeValues = children.map((child) {
      var valueString =
          yamlEncodeBlockString(child, newIndentation, lineEnding);
      if (isCollection(child) && !isFlowYamlCollectionNode(child)) {
        valueString = valueString.substring(newIndentation);
      }

      return '${' ' * indentation}- $valueString';
    });

    return safeValues.join(lineEnding);
  } else if (value is YamlMap) {
    if (value.isEmpty) return '${' ' * indentation}{}';

    return value.nodes.entries.map((entry) {
      final MapEntry(:key, :value) = entry;

      final safeKey = yamlEncodeFlowString(key as YamlNode);
      final formattedKey = ' ' * indentation + safeKey;

      final formattedValue = yamlEncodeBlockString(
        value,
        newIndentation,
        lineEnding,
      );

      /// Empty collections are always encoded in flow-style, so new-line must
      /// be avoided
      if (isCollection(value) && !isEmpty(value)) {
        return '$formattedKey:$lineEnding$formattedValue';
      }

      return '$formattedKey: $formattedValue';
    }).join(lineEnding);
  }

  return _yamlEncodeBlockScalar(
    value as YamlScalar,
    newIndentation,
    lineEnding,
  );
}

/// List of unprintable characters.
///
/// See 5.7 Escape Characters https://yaml.org/spec/1.2/spec.html#id2776092
final Map<int, String> unprintableCharCodes = {
  0: '\\0', //  Escaped ASCII null (#x0) character.
  7: '\\a', //  Escaped ASCII bell (#x7) character.
  8: '\\b', //  Escaped ASCII backspace (#x8) character.
  11: '\\v', // 	Escaped ASCII vertical tab (#xB) character.
  12: '\\f', //  Escaped ASCII form feed (#xC) character.
  13: '\\r', //  Escaped ASCII carriage return (#xD) character. Line Break.
  27: '\\e', //  Escaped ASCII escape (#x1B) character.
  133: '\\N', //  Escaped Unicode next line (#x85) character.
  160: '\\_', //  Escaped Unicode non-breaking space (#xA0) character.
  8232: '\\L', //  Escaped Unicode line separator (#x2028) character.
  8233: '\\P', //  Escaped Unicode paragraph separator (#x2029) character.
};

/// List of escape characters.
///
/// See 5.7 Escape Characters https://yaml.org/spec/1.2/spec.html#id2776092
final Map<int, String> doubleQuoteEscapeChars = {
  ...unprintableCharCodes,
  9: '\\t', //  Escaped ASCII horizontal tab (#x9) character. Printable
  10: '\\n', //  Escaped ASCII line feed (#xA) character. Line Break.
  34: '\\"', //  Escaped ASCII double quote (#x22).
  47: '\\/', //  Escaped ASCII slash (#x2F), for JSON compatibility.
  92: '\\\\', //  Escaped ASCII back slash (#x5C).
};
