// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import 'editor.dart';
import 'equality.dart';
import 'source_edit.dart';
import 'strings.dart';
import 'utils.dart';
import 'wrap.dart';

/// Performs the string operation on [yamlEdit] to achieve the effect of setting
/// the element at [key] to [newValue] when re-parsed.
SourceEdit updateInMap(
    YamlEditor yamlEdit, YamlMap map, Object? key, YamlNode newValue) {
  if (!containsKey(map, key)) {
    final keyNode = wrapAsYamlNode(key);

    if (map.style == CollectionStyle.FLOW) {
      return _addToFlowMap(yamlEdit, map, keyNode, newValue);
    } else {
      return _addToBlockMap(yamlEdit, map, keyNode, newValue);
    }
  } else {
    if (map.style == CollectionStyle.FLOW) {
      return _replaceInFlowMap(yamlEdit, map, key, newValue);
    } else {
      return _replaceInBlockMap(yamlEdit, map, key, newValue);
    }
  }
}

/// Performs the string operation on [yamlEdit] to achieve the effect of
/// removing the element at [key] when re-parsed.
SourceEdit removeInMap(YamlEditor yamlEdit, YamlMap map, Object? key) {
  assert(containsKey(map, key));
  final (_, keyNode) = getKeyNode(map, key);
  final valueNode = map.nodes[keyNode]!;

  if (map.style == CollectionStyle.FLOW) {
    return _removeFromFlowMap(yamlEdit, map, keyNode, valueNode);
  } else {
    return _removeFromBlockMap(yamlEdit, map, keyNode, valueNode);
  }
}

/// Performs the string operation on [yamlEdit] to achieve the effect of adding
/// the [key]:[newValue] pair when reparsed, bearing in mind that this is a
/// block map.
SourceEdit _addToBlockMap(
    YamlEditor yamlEdit, YamlMap map, Object key, YamlNode newValue) {
  final yaml = yamlEdit.toString();
  final newIndentation =
      getMapIndentation(yaml, map) + getIndentation(yamlEdit);
  final keyString = yamlEncodeFlow(wrapAsYamlNode(key));
  final lineEnding = getLineEnding(yaml);

  var formattedValue = ' ' * getMapIndentation(yaml, map);
  var offset = map.span.end.offset;

  final insertionIndex = getMapInsertionIndex(map, keyString);

  if (map.isNotEmpty) {
    /// Adjusts offset to after the trailing newline of the last entry, if it
    /// exists
    if (insertionIndex == map.length) {
      final lastValueSpanEnd = getContentSensitiveEnd(map.nodes.values.last);
      final nextNewLineIndex = yaml.indexOf('\n', lastValueSpanEnd);

      if (nextNewLineIndex != -1) {
        offset = nextNewLineIndex + 1;
      } else {
        formattedValue = lineEnding + formattedValue;
      }
    } else {
      final keyAtIndex = map.nodes.keys.toList()[insertionIndex] as YamlNode;
      final keySpanStart = keyAtIndex.span.start.offset;
      final prevNewLineIndex = yaml.lastIndexOf('\n', keySpanStart);

      offset = prevNewLineIndex + 1;
    }
  }

  final valueString = yamlEncodeBlock(newValue, newIndentation, lineEnding);

  if (isCollection(newValue) &&
      !isFlowYamlCollectionNode(newValue) &&
      !isEmpty(newValue)) {
    formattedValue += '$keyString:$lineEnding$valueString';
  } else {
    formattedValue += '$keyString: $valueString';
  }

  return SourceEdit(offset, 0, formattedValue);
}

/// Performs the string operation on [yamlEdit] to achieve the effect of adding
/// the [key]:[newValue] pair when reparsed, bearing in mind that this is a flow
/// map.
SourceEdit _addToFlowMap(
    YamlEditor yamlEdit, YamlMap map, YamlNode keyNode, YamlNode newValue) {
  final keyString = yamlEncodeFlow(keyNode);
  final valueString = yamlEncodeFlow(newValue);

  // The -1 accounts for the closing bracket.
  if (map.isEmpty) {
    return SourceEdit(map.span.end.offset - 1, 0, '$keyString: $valueString');
  }

  final insertionIndex = getMapInsertionIndex(map, keyString);

  if (insertionIndex == map.length) {
    return SourceEdit(map.span.end.offset - 1, 0, ', $keyString: $valueString');
  }

  final insertionOffset =
      (map.nodes.keys.toList()[insertionIndex] as YamlNode).span.start.offset;

  return SourceEdit(insertionOffset, 0, '$keyString: $valueString, ');
}

/// Performs the string operation on [yamlEdit] to achieve the effect of
/// replacing the value at [key] with [newValue] when reparsed, bearing in mind
/// that this is a block map.
SourceEdit _replaceInBlockMap(
    YamlEditor yamlEdit, YamlMap map, Object? key, YamlNode newValue) {
  final yaml = yamlEdit.toString();
  final lineEnding = getLineEnding(yaml);
  final mapIndentation = getMapIndentation(yaml, map);
  final newIndentation = mapIndentation + getIndentation(yamlEdit);

  final (_, keyNode) = getKeyNode(map, key);

  var valueAsString = yamlEncodeBlock(
    wrapAsYamlNode(newValue),
    newIndentation,
    lineEnding,
  );

  if (isCollection(newValue) &&
      !isFlowYamlCollectionNode(newValue) &&
      !isEmpty(newValue)) {
    valueAsString = lineEnding + valueAsString;
  }

  if (!valueAsString.startsWith(lineEnding)) {
    // prepend whitespace to ensure there is space after colon.
    valueAsString = ' $valueAsString';
  }

  /// +1 accounts for the colon
  // TODO: What if here is a whitespace following the key, before the colon?
  final start = keyNode.span.end.offset + 1;
  var end = getContentSensitiveEnd(map.nodes[key]!);

  /// `package:yaml` parses empty nodes in a way where the start/end of the
  /// empty value node is the end of the key node.
  ///
  /// In our case, we need to ensure that any line-breaks are included in the
  /// edit such that:
  ///   1. We account for `\n` after a key within other keys or at the start
  ///       Example..
  ///             a:
  ///             b: value
  ///
  ///       or..
  ///             a: value
  ///             b:
  ///             c: value
  ///
  ///   2. We don't suggest edits that are not within the string bounds because
  ///      of the `\n` we need to account for in Rule 1 above. This could be a
  ///      key:
  ///         * At the index `0` but it's the only key
  ///         * At the end in a map with more than one key
  end = start == yaml.length
      ? start
      : end < start
          ? start + 1
          : end;

  // Aggressively skip all comments
  final (offsetOfLastComment, _) =
      skipAndExtractCommentsInBlock(yaml, end, null, lineEnding: lineEnding);
  end = offsetOfLastComment;

  valueAsString = normalizeEncodedBlock(
    yaml,
    lineEnding: lineEnding,
    nodeToReplaceEndOffset: end,
    update: newValue,
    updateAsString: valueAsString,
  );

  return SourceEdit(start, end - start, valueAsString);
}

/// Performs the string operation on [yamlEdit] to achieve the effect of
/// replacing the value at [key] with [newValue] when reparsed, bearing in mind
/// that this is a flow map.
SourceEdit _replaceInFlowMap(
    YamlEditor yamlEdit, YamlMap map, Object? key, YamlNode newValue) {
  final valueSpan = map.nodes[key]!.span;
  final valueString = yamlEncodeFlow(newValue);

  return SourceEdit(valueSpan.start.offset, valueSpan.length, valueString);
}

/// Performs the string operation on [yamlEdit] to achieve the effect of
/// removing the [keyNode] from the map, bearing in mind that this is a block
/// map.
SourceEdit _removeFromBlockMap(
    YamlEditor yamlEdit, YamlMap map, YamlNode keyNode, YamlNode valueNode) {
  final keySpan = keyNode.span;

  final yaml = yamlEdit.toString();
  final yamlSize = yaml.length;

  final lineEnding = getLineEnding(yaml);

  final (keyIndex, _) = getKeyNode(map, keyNode);

  var startOffset = keySpan.start.offset;

  /// Null values have an invalid offset. Include colon.
  ///
  /// See issue open in `package: yaml`.
  var endOffset = valueNode.value == null
      ? keySpan.end.offset + 2
      : getContentSensitiveEnd(valueNode) + 1; // Overeager to avoid issues

  if (endOffset > yamlSize) endOffset -= 1;

  endOffset = skipAndExtractCommentsInBlock(
    yaml,
    endOffset,
    null,
    lineEnding: lineEnding,
    greedy: true,
  ).$1;

  final mapSize = map.length;

  final isSingleEntry = mapSize == 1;
  final isLastEntryInMap = keyIndex == mapSize - 1;
  final isLastNodeInYaml = endOffset == yamlSize;

  final replacement = isSingleEntry ? '{}' : '';

  /// Adjust [startIndent] to include any indent this element may have had
  /// to prevent it from interfering with the indent of the next [YamlNode]
  /// which isn't in this map. We move it back if:
  ///   1. The entry is the last entry in a [map] with more than one element.
  ///   2. It also isn't the first entry of map in the yaml.
  ///
  /// Doing this only for the last element ensures that any value's indent is
  /// automatically given to the next entry in the map.
  if (isLastEntryInMap && startOffset != 0 && !isSingleEntry) {
    final index = yaml.lastIndexOf('\n', startOffset);
    startOffset = index == -1 ? startOffset : index + 1;
  }

  /// We intentionally [skipAndExtractCommentsInBlock] greedily which also
  /// consumes the next [YamlNode]'s indent.
  ///
  /// For elements at the last index, we need to reclaim the indent belonging
  /// to the next node not in the map and optionally include a line break if
  /// if it is the only entry. See [reclaimIndentAndLinebreak] for more info.
  if (isLastEntryInMap && !isLastNodeInYaml) {
    endOffset = reclaimIndentAndLinebreak(
      yaml,
      endOffset,
      isSingle: isSingleEntry,
    );
  } else if (isLastNodeInYaml && yaml[endOffset - 1] == '\n' && isSingleEntry) {
    /// Include any trailing line break that may have been part of the yaml:
    ///   -`\r\n` = 2
    ///   - `\n` = 1
    endOffset -= lineEnding == '\n' ? 1 : 2;
  }

  return SourceEdit(startOffset, endOffset - startOffset, replacement);
}

/// Performs the string operation on [yamlEdit] to achieve the effect of
/// removing the [keyNode] from the map, bearing in mind that this is a flow
/// map.
SourceEdit _removeFromFlowMap(
    YamlEditor yamlEdit, YamlMap map, YamlNode keyNode, YamlNode valueNode) {
  var start = keyNode.span.start.offset;
  var end = valueNode.span.end.offset;
  final yaml = yamlEdit.toString();

  if (deepEquals(keyNode, map.keys.first)) {
    start = yaml.lastIndexOf('{', start - 1) + 1;

    if (deepEquals(keyNode, map.keys.last)) {
      end = yaml.indexOf('}', end);
    } else {
      end = yaml.indexOf(',', end) + 1;
    }
  } else {
    start = yaml.lastIndexOf(',', start - 1);
  }

  return SourceEdit(start, end - start, '');
}
