// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'editor.dart';
import 'wrap.dart';

/// Invoke [fn] while setting [yamlWarningCallback] to [warn], and restore
/// [YamlWarningCallback] after [fn] returns.
///
/// Defaults to a [warn] function that ignores all warnings.
T withYamlWarningCallback<T>(
  T Function() fn, {
  YamlWarningCallback warn = _ignoreWarning,
}) {
  final original = yamlWarningCallback;
  try {
    yamlWarningCallback = warn;
    return fn();
  } finally {
    yamlWarningCallback = original;
  }
}

void _ignoreWarning(String warning, [SourceSpan? span]) {/* ignore warning */}

/// Determines if [string] is dangerous by checking if parsing the plain string
/// can return a result different from [string].
///
/// This function is also capable of detecting if non-printable characters are
/// in [string].
bool isDangerousString(String string) {
  try {
    final node = withYamlWarningCallback(() => loadYamlNode(string));
    if (node.value != string) {
      return true;
    }

    // [string] should also not contain the `[`, `]`, `,`, `{` and `}` indicator
    // characters.
    return string.contains(RegExp(r'\{|\[|\]|\}|,'));
  } catch (e) {
    /// This catch statement catches [ArgumentError] in `loadYamlNode` when
    /// a string can be interpreted as a URI tag, but catches for other
    /// [YamlException]s
    return true;
  }
}

/// Asserts that [value] is a valid scalar according to YAML.
///
/// A valid scalar is a number, String, boolean, or null.
void assertValidScalar(Object? value) {
  if (value is num || value is String || value is bool || value == null) {
    return;
  }

  throw ArgumentError.value(value, 'value', 'Not a valid scalar type!');
}

/// Checks if [node] is a [YamlNode] with block styling.
///
/// [ScalarStyle.ANY] and [CollectionStyle.ANY] are considered to be block
/// styling by default for maximum flexibility.
bool isBlockNode(YamlNode node) {
  if (node is YamlScalar) {
    if (node.style == ScalarStyle.LITERAL ||
        node.style == ScalarStyle.FOLDED ||
        node.style == ScalarStyle.ANY) {
      return true;
    }
  }

  if (node is YamlList &&
      (node.style == CollectionStyle.BLOCK ||
          node.style == CollectionStyle.ANY)) return true;
  if (node is YamlMap &&
      (node.style == CollectionStyle.BLOCK ||
          node.style == CollectionStyle.ANY)) return true;

  return false;
}

/// Returns the content sensitive ending offset of [yamlNode] (i.e. where the
/// last meaningful content happens)
int getContentSensitiveEnd(YamlNode yamlNode) {
  if (yamlNode is YamlList) {
    if (yamlNode.style == CollectionStyle.FLOW) {
      return yamlNode.span.end.offset;
    } else {
      return getContentSensitiveEnd(yamlNode.nodes.last);
    }
  } else if (yamlNode is YamlMap) {
    if (yamlNode.style == CollectionStyle.FLOW) {
      return yamlNode.span.end.offset;
    } else {
      return getContentSensitiveEnd(yamlNode.nodes.values.last);
    }
  }

  return yamlNode.span.end.offset;
}

/// Checks if the item is a Map or a List
bool isCollection(Object item) => item is Map || item is List;

/// Checks if [index] is [int], >=0, < [length]
bool isValidIndex(Object? index, int length) {
  return index is int && index >= 0 && index < length;
}

/// Checks if the item is empty, if it is a List or a Map.
///
/// Returns `false` if [item] is not a List or Map.
bool isEmpty(Object item) {
  if (item is Map) return item.isEmpty;
  if (item is List) return item.isEmpty;

  return false;
}

/// Creates a [SourceSpan] from [sourceUrl] with no meaningful location
/// information.
///
/// Mainly used with [wrapAsYamlNode] to allow for a reasonable
/// implementation of [SourceSpan.message].
SourceSpan shellSpan(Object? sourceUrl) {
  final shellSourceLocation = SourceLocation(0, sourceUrl: sourceUrl);
  return SourceSpanBase(shellSourceLocation, shellSourceLocation, '');
}

/// Returns if [value] is a [YamlList] or [YamlMap] with [CollectionStyle.FLOW].
bool isFlowYamlCollectionNode(Object value) =>
    value is YamlNode && value.collectionStyle == CollectionStyle.FLOW;

/// Determines the index where [newKey] will be inserted if the keys in [map]
/// are in alphabetical order when converted to strings.
///
/// Returns the length of [map] if the keys in [map] are not in alphabetical
/// order.
int getMapInsertionIndex(YamlMap map, Object newKey) {
  final keys = map.nodes.keys.map((k) => k.toString()).toList();

  // We can't deduce ordering if list is empty, so then we just we just append
  if (keys.length <= 1) {
    return map.length;
  }

  for (var i = 1; i < keys.length; i++) {
    if (keys[i].compareTo(keys[i - 1]) < 0) {
      return map.length;
    }
  }

  final insertionIndex =
      keys.indexWhere((key) => key.compareTo(newKey as String) > 0);

  if (insertionIndex != -1) return insertionIndex;

  return map.length;
}

/// Returns the detected indentation step used in [editor], or defaults to a
/// value of `2` if no indentation step can be detected.
///
/// Indentation step is determined by the difference in indentation of the
/// first block-styled yaml collection in the second level as compared to the
/// top-level elements. In the case where there are multiple possible
/// candidates, we choose the candidate closest to the start of [editor].
int getIndentation(YamlEditor editor) {
  final node = editor.parseAt([]);
  Iterable<YamlNode>? children;
  var indentation = 2;

  if (node is YamlMap && node.style == CollectionStyle.BLOCK) {
    children = node.nodes.values;
  } else if (node is YamlList && node.style == CollectionStyle.BLOCK) {
    children = node.nodes;
  }

  if (children != null) {
    for (final child in children) {
      var indent = 0;
      if (child is YamlList) {
        indent = getListIndentation(editor.toString(), child);
      } else if (child is YamlMap) {
        indent = getMapIndentation(editor.toString(), child);
      }

      if (indent != 0) indentation = indent;
    }
  }
  return indentation;
}

/// Gets the indentation level of [list]. This is 0 if it is a flow list,
/// but returns the number of spaces before the hyphen of elements for
/// block lists.
///
/// Throws [UnsupportedError] if an empty block map is passed in.
int getListIndentation(String yaml, YamlList list) {
  if (list.style == CollectionStyle.FLOW) return 0;

  /// An empty block map doesn't really exist.
  if (list.isEmpty) {
    throw UnsupportedError('Unable to get indentation for empty block list');
  }

  final lastSpanOffset = list.nodes.last.span.start.offset;
  final lastHyphen = yaml.lastIndexOf('-', lastSpanOffset - 1);

  if (lastHyphen == 0) return lastHyphen;

  // Look for '\n' that's before hyphen
  final lastNewLine = yaml.lastIndexOf('\n', lastHyphen - 1);

  return lastHyphen - lastNewLine - 1;
}

/// Gets the indentation level of [map]. This is 0 if it is a flow map,
/// but returns the number of spaces before the keys for block maps.
int getMapIndentation(String yaml, YamlMap map) {
  if (map.style == CollectionStyle.FLOW) return 0;

  /// An empty block map doesn't really exist.
  if (map.isEmpty) {
    throw UnsupportedError('Unable to get indentation for empty block map');
  }

  /// Use the number of spaces between the last key and the newline as
  /// indentation.
  final lastKey = map.nodes.keys.last as YamlNode;
  final lastSpanOffset = lastKey.span.start.offset;
  final lastNewLine = yaml.lastIndexOf('\n', lastSpanOffset);
  final lastQuestionMark = yaml.lastIndexOf('?', lastSpanOffset);

  if (lastQuestionMark == -1) {
    if (lastNewLine == -1) return lastSpanOffset;
    return lastSpanOffset - lastNewLine - 1;
  }

  /// If there is a question mark, it might be a complex key. Check if it
  /// is on the same line as the key node to verify.
  if (lastNewLine == -1) return lastQuestionMark;
  if (lastQuestionMark > lastNewLine) {
    return lastQuestionMark - lastNewLine - 1;
  }

  return lastSpanOffset - lastNewLine - 1;
}

/// Returns the detected line ending used in [yaml], more specifically, whether
/// [yaml] appears to use Windows `\r\n` or Unix `\n` line endings.
///
/// The heuristic used is to count all `\n` in the text and if strictly more
/// than half of them are preceded by `\r` we report that windows line endings
/// are used.
String getLineEnding(String yaml) {
  var index = -1;
  var unixNewlines = 0;
  var windowsNewlines = 0;
  while ((index = yaml.indexOf('\n', index + 1)) != -1) {
    if (index != 0 && yaml[index - 1] == '\r') {
      windowsNewlines++;
    } else {
      unixNewlines++;
    }
  }

  return windowsNewlines > unixNewlines ? '\r\n' : '\n';
}

/// Extracts comments for a node that is replaced within a [YamlMap] or
/// [YamlList] or a top-level [YamlScalar] of the [yaml] string provided.
///
/// [endOfNodeOffset] represents the end offset of [YamlScalar] or [YamlList]
/// or [YamlMap] being replaced, that is, `end + 1`.
///
/// [nextStartOffset] represents the start offset of the next [YamlNode].
/// May be null if the current [YamlNode] being replaced is the last node
/// in a [YamlScalar] or [YamlList] or if its the only top-level [YamlScalar].
/// If not sure of the next [YamlNode]'s [nextStartOffset] pass in null and
/// allow this function to handle that manually.
///
/// If [greedy] is `true`, whitespace and any line breaks are skipped. If
/// `false`, this function looks for comments lazily and returns the offset of
/// the first line break that was encountered if no comments were found.
///
/// Do note that this function has no context of the structure of the [yaml]
/// but assumes the caller does and requires comments based on the offsets
/// provided and thus, may be erroneus since it exclusively scans for `#`
/// delimiter or extracts the comments between the [endOfNodeOffset] and
/// [nextStartOffset] if both are provided.
///
/// Returns the `endOffset` of the last comment extracted that is `end + 1`
/// and a `List<String> comments`. It is recommended (but not necessary) that
/// the caller checks the `endOffset` is still within the bounds of the [yaml].
(int endOffset, List<String> comments) skipAndExtractCommentsInBlock(
  String yaml,
  int endOfNodeOffset,
  int? nextStartOffset, {
  String lineEnding = '\n',
  bool greedy = false,
}) {
  /// If [nextStartOffset] is null, this may be the last element in a collection
  /// and thus we have to check and extract comments manually.
  ///
  /// Also, the caller may not be sure where the next node starts.
  if (nextStartOffset == null) {
    final comments = <String>[];

    /// Skips white-space while extracting comments.
    ///
    /// Returns [null] if the end of the [yaml] was encountered while
    /// skipping any white-space. Otherwise, returns the [index] of the next
    /// non-white-space character.
    (int? firstLineBreakOffset, int? nextIndex) skipWhitespace(int index) {
      int? firstLineBreak;
      int? nextIndex = index;

      while (true) {
        if (nextIndex == yaml.length) {
          nextIndex = null;
          break;
        }

        final char = yaml[nextIndex!];

        if (char == lineEnding && firstLineBreak == null) {
          firstLineBreak = nextIndex;
        }

        if (char.trim().isNotEmpty) break;
        ++nextIndex;
      }

      if (firstLineBreak != null) firstLineBreak += 1; // Skip it if not null
      return (firstLineBreak, nextIndex);
    }

    /// Returns the [currentOffset] if [greedy] is true. Otherwise, attempts
    /// returning the [firstLineBreakOffset] if not null if [greedy] is false.
    int earlyBreakOffset(int currentOffset, int? firstLineBreakOffset) {
      if (greedy) return currentOffset;
      return firstLineBreakOffset ?? currentOffset;
    }

    var currentOffset = endOfNodeOffset;

    while (true) {
      if (currentOffset == yaml.length) break;

      var leadingChar = yaml[currentOffset].trim();
      var indexOfCommentStart = -1;

      int? firstLineBreak;

      if (leadingChar.isEmpty) {
        final (firstLE, nextIndex) = skipWhitespace(currentOffset);

        /// If the next index is null, it means we reached the end of the
        /// string. Since we lazily evaluated the string, attempt to return the
        /// first [lineEnding] we encountered only if not null.
        if (nextIndex == null) {
          currentOffset = earlyBreakOffset(yaml.length, firstLE);
          break;
        }

        firstLineBreak = firstLE;
        currentOffset = nextIndex;
        leadingChar = yaml[currentOffset];
      }

      /// We need comments only, nothing else. This may be pointless but will
      /// help us avoid extracting comments when provided random offsets
      /// within a string.
      if (leadingChar == '#') indexOfCommentStart = currentOffset;

      /// This is a mindless assumption that the last character was either
      /// `\n` or [white-space] or the last erroneus offset provided.
      ///
      /// Since we lazily evaluated the string, attempt to return the
      /// first [lineEnding] we encountered only if not null.
      if (indexOfCommentStart == -1) {
        currentOffset = earlyBreakOffset(currentOffset, firstLineBreak);
        break;
      }

      final indexOfLineBreak = yaml.indexOf(lineEnding, currentOffset);
      final isEnd = indexOfLineBreak == -1;

      final comment = yaml
          .substring(indexOfCommentStart, isEnd ? null : indexOfLineBreak)
          .trim();

      if (comment.isNotEmpty) comments.add(comment);

      if (isEnd) {
        currentOffset += comment.length;
        break;
      }
      currentOffset = indexOfLineBreak;
    }

    return (currentOffset, comments);
  }

  return (
    nextStartOffset,
    yaml.substring(endOfNodeOffset, nextStartOffset).split(lineEnding).fold(
      <String>[],
      (buffer, current) {
        final comment = current.trim();
        if (comment.isNotEmpty) buffer.add(comment);
        return buffer;
      },
    )
  );
}

/// Reclaims any indent greedily skipped by [skipAndExtractCommentsInBlock]
/// and returns the start `offset` (inclusive).
///
/// If [isSingle] is `true`, then the `offset` of the line-break is included.
/// It is excluded if `false`.
///
/// It is recommended that this function is called when removing the last
/// [YamlNode] in a block [YamlMap] or [YamlList].
int reclaimIndentAndLinebreak(
  String yaml,
  int currentOffset, {
  required bool isSingle,
}) {
  var indexOfLineBreak = yaml.lastIndexOf('\n', currentOffset);

  /// In case, this isn't the only element, we ignore the line-break while
  /// reclaiming the indent. As the element that remains, will have a line
  /// break the next node needs to indicate start of a new node!
  if (!isSingle) indexOfLineBreak += 1;

  final indentDiff = currentOffset - indexOfLineBreak;
  return currentOffset - indentDiff;
}

/// Normalizes an encoded [YamlNode] encoded as a string by pruning any
/// dangling line-breaks.
///
/// This function checks the last `YamlNode` of the [update] that is a
/// `YamlScalar` and removes any dangling line-break within the
/// [updateAsString].
///
/// Line breaks are allowed if a:
///   1. [YamlScalar] has [ScalarStyle.LITERAL] or [ScalarStyle.FOLDED]
///   2. [YamlScalar] has [ScalarStyle.PLAIN] or [ScalarStyle.ANY] and its
///      raw value is a [String] with a trailing line break.
///   3. [YamlNode] being replaced has a line break.
///
/// [skipPreservationCheck] should always remain false if updating a value
/// within a [YamlList] or [YamlMap] that isn't an existing top-level
/// [YamlNode].
String normalizeEncodedBlock(
  String yaml, {
  required String lineEnding,
  required int nodeToReplaceEndOffset,
  required YamlNode update,
  required String updateAsString,
  bool skipPreservationCheck = false,
}) {
  final terminalNode = _findTerminalScalar(update);

  /// Nested function that checks if the dangling line break should be allowed
  /// within the deepest [YamlNode] that is a [YamlScalar].
  bool allowInYamlScalar(ScalarStyle style, dynamic value) {
    /// We never normalize a literal/folded string irrespective of
    /// its position.  We allow the block indicators to define how the
    /// line-break will be treated
    if (style == ScalarStyle.LITERAL || style == ScalarStyle.FOLDED) {
      return true;
    }

    // Allow trailing line break if the raw value has a explicit line break.
    if (style == ScalarStyle.PLAIN || style == ScalarStyle.ANY) {
      return value is String &&
          (value.endsWith('\n') || value.endsWith('\r\n'));
    }

    return false;
  }

  /// The node may end up being an empty [YamlMap] or [YamlList] or
  /// [YamlScalar].
  if (terminalNode case YamlScalar(style: var style, value: var value)
      when allowInYamlScalar(style, value)) {
    return updateAsString;
  }

  if (yaml.isNotEmpty && !skipPreservationCheck) {
    // Move it back one position. Offset passed in is/should be exclusive
    final offsetBeforeEnd = nodeToReplaceEndOffset > 0
        ? nodeToReplaceEndOffset - 1
        : nodeToReplaceEndOffset;

    /// Leave as is. The [update] is:
    ///   1. An element not at the end of [YamlList] or [YamlMap]
    ///   2. [YamlNode] replaced had a `\n`
    if (yaml[offsetBeforeEnd] == '\n') return updateAsString;
  }

  // Remove trailing line-break by default.
  return updateAsString.trimRight();
}

/// Returns the terminal [YamlNode] that is a [YamlScalar].
///
/// If within a [YamlList], then the last value that is a [YamlScalar]. If
/// within a [YamlMap], then the last entry with a value that is a [YamlScalar].
YamlScalar? _findTerminalScalar(YamlNode node) {
  YamlNode? terminalNode = node;

  while (terminalNode is! YamlScalar) {
    switch (terminalNode) {
      case YamlList list:
        {
          if (list.isEmpty) return null;
          terminalNode = list.nodes.last;
        }

      case YamlMap map:
        {
          if (map.isEmpty) return null;
          terminalNode = map.nodes.entries.last.value;
        }

      default:
        return null;
    }
  }

  return terminalNode;
}

extension YamlNodeExtension on YamlNode {
  /// Returns the [CollectionStyle] of `this` if `this` is [YamlMap] or
  /// [YamlList].
  ///
  /// Otherwise, returns `null`.
  CollectionStyle? get collectionStyle {
    final me = this;
    if (me is YamlMap) return me.style;
    if (me is YamlList) return me.style;
    return null;
  }
}
