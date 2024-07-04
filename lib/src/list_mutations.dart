// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:yaml/yaml.dart';

import 'editor.dart';
import 'source_edit.dart';
import 'strings.dart';
import 'utils.dart';
import 'wrap.dart';

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of setting the element at [index] to [newValue] when
/// re-parsed.
SourceEdit updateInList(
    YamlEditor yamlEdit, YamlList list, int index, YamlNode newValue) {
  RangeError.checkValueInInterval(index, 0, list.length - 1);

  final currValue = list.nodes[index];
  var offset = currValue.span.start.offset;
  final yaml = yamlEdit.toString();
  String valueString;

  /// We do not use [_formatNewBlock] since we want to only replace the contents
  /// of this node while preserving comments/whitespace, while [_formatNewBlock]
  /// produces a string representation of a new node.
  if (list.style == CollectionStyle.BLOCK) {
    final listIndentation = getListIndentation(yaml, list);
    final indentation = listIndentation + getIndentation(yamlEdit);
    final lineEnding = getLineEnding(yaml);

    final encoded = yamlEncodeBlock(
      wrapAsYamlNode(newValue),
      indentation,
      lineEnding,
    );
    valueString = encoded;

    /// We prefer the compact nested notation for collections.
    ///
    /// By virtue of [yamlEncodeBlock], collections automatically
    /// have the necessary line endings.
    if ((newValue is List && (newValue as List).isNotEmpty) ||
        (newValue is Map && (newValue as Map).isNotEmpty)) {
      valueString = valueString.substring(indentation);
    }

    var end = getContentSensitiveEnd(currValue);
    if (end <= offset) {
      offset++;
      end = offset;
      valueString = ' $valueString';
    }

    // Aggressively skip all comments
    final (offsetOfLastComment, _) =
        skipAndExtractCommentsInBlock(yaml, end, null, lineEnding: lineEnding);
    end = offsetOfLastComment;

    valueString = normalizeEncodedBlock(
      yaml,
      lineEnding: lineEnding,
      nodeToReplaceEndOffset: end,
      update: newValue,
      updateAsString: valueString,
    );

    return SourceEdit(offset, end - offset, valueString);
  } else {
    valueString = yamlEncodeFlow(newValue);
    return SourceEdit(offset, currValue.span.length, valueString);
  }
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of appending [item] to the list.
SourceEdit appendIntoList(YamlEditor yamlEdit, YamlList list, YamlNode item) {
  if (list.style == CollectionStyle.FLOW) {
    return _appendToFlowList(yamlEdit, list, item);
  } else {
    return _appendToBlockList(yamlEdit, list, item);
  }
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of inserting [item] to the list at [index].
SourceEdit insertInList(
    YamlEditor yamlEdit, YamlList list, int index, YamlNode item) {
  RangeError.checkValueInInterval(index, 0, list.length);

  /// We call the append method if the user wants to append it to the end of the
  /// list because appending requires different techniques.
  if (index == list.length) {
    return appendIntoList(yamlEdit, list, item);
  } else {
    if (list.style == CollectionStyle.FLOW) {
      return _insertInFlowList(yamlEdit, list, index, item);
    } else {
      return _insertInBlockList(yamlEdit, list, index, item);
    }
  }
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of removing the element at [index] when re-parsed.
SourceEdit removeInList(YamlEditor yamlEdit, YamlList list, int index) {
  final nodeToRemove = list.nodes[index];

  if (list.style == CollectionStyle.FLOW) {
    return _removeFromFlowList(yamlEdit, list, nodeToRemove, index);
  } else {
    return _removeFromBlockList(yamlEdit, list, nodeToRemove, index);
  }
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of addition [item] into [list], noting that this is a
/// flow list.
SourceEdit _appendToFlowList(
    YamlEditor yamlEdit, YamlList list, YamlNode item) {
  final valueString = _formatNewFlow(list, item, true);
  return SourceEdit(list.span.end.offset - 1, 0, valueString);
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of addition [item] into [list], noting that this is a
/// block list.
SourceEdit _appendToBlockList(
    YamlEditor yamlEdit, YamlList list, YamlNode item) {
  /// A block list can never be empty since a `-` must be seen for it to be a
  /// valid block sequence.
  ///
  /// See description of:
  /// https://yaml.org/spec/1.2.2/#82-block-collection-styles.
  assert(
    list.isNotEmpty,
    'A YamlList encoded as CollectionStyle.BLOCK must have a value',
  );

  final yaml = yamlEdit.toString();
  final lineEnding = getLineEnding(yaml);

  // Lazily skip all comments and white-space at the end.
  final (offset, _) = skipAndExtractCommentsInBlock(
    yaml,
    list.nodes.last.span.end.offset,
    null,
    lineEnding: lineEnding,
  );

  var (indentSize, formattedValue) = _formatNewBlock(yamlEdit, list, item);

  formattedValue = normalizeEncodedBlock(
    yaml,
    lineEnding: lineEnding,
    nodeToReplaceEndOffset: offset,
    update: item,
    updateAsString: formattedValue,
  );

  formattedValue = '${' ' * indentSize}$formattedValue';

  // Apply line ending incase it's missing
  if (yaml[offset - 1] != '\n') {
    formattedValue = '$lineEnding$formattedValue';
  }

  return SourceEdit(offset, 0, formattedValue);
}

/// Formats [item] into a new node for block lists.
(int indentSize, String valueStringToIndent) _formatNewBlock(
    YamlEditor yamlEdit, YamlList list, YamlNode item) {
  final yaml = yamlEdit.toString();
  final listIndentation = getListIndentation(yaml, list);
  final newIndentation = listIndentation + getIndentation(yamlEdit);
  final lineEnding = getLineEnding(yaml);

  var valueString = yamlEncodeBlock(item, newIndentation, lineEnding);
  if (isCollection(item) && !isFlowYamlCollectionNode(item) && !isEmpty(item)) {
    valueString = valueString.substring(newIndentation);
  }

  return (listIndentation, '- $valueString');
}

/// Formats [item] into a new node for flow lists.
String _formatNewFlow(YamlList list, YamlNode item, [bool isLast = false]) {
  var valueString = yamlEncodeFlow(item);
  if (list.isNotEmpty) {
    if (isLast) {
      valueString = ', $valueString';
    } else {
      valueString += ', ';
    }
  }

  return valueString;
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of inserting [item] into [list] at [index], noting that
/// this is a block list.
///
/// [index] should be non-negative and less than or equal to `list.length`.
SourceEdit _insertInBlockList(
    YamlEditor yamlEdit, YamlList list, int index, YamlNode item) {
  RangeError.checkValueInInterval(index, 0, list.length);

  if (index == list.length) return _appendToBlockList(yamlEdit, list, item);

  var (indentSize, formattedValue) = _formatNewBlock(yamlEdit, list, item);

  final currNode = list.nodes[index];
  final currNodeStart = currNode.span.start.offset;
  final yaml = yamlEdit.toString();

  final currSequenceOffset = yaml.lastIndexOf('-', currNodeStart - 1);

  final (isNested, offset) = _isNestedInBlockList(currSequenceOffset, yaml);

  /// We have to get rid of the left indentation applied by default
  if (isNested && index == 0) {
    /// The [insertionIndex] will be equal to the start of
    /// [currentSequenceOffset] of the element we are inserting before in most
    /// cases.
    ///
    /// Example:
    ///
    ///   - - value
    ///     ^ Inserting before this and we get rid of indent
    ///
    /// If not, we need to account for the space between them that is not an
    /// indent.
    ///
    /// Example:
    ///
    ///   -   - value
    ///       ^ Inserting before this and we get rid of indent. But also account
    ///         for space in between
    final leftPad = currSequenceOffset - offset;
    final padding = ' ' * leftPad;

    final indent = ' ' * (indentSize - leftPad);

    // Give the indent to the first element
    formattedValue = '$padding${formattedValue.trimLeft()}$indent';
  } else {
    final indent = ' ' * indentSize; // Calculate indent normally
    formattedValue = '$indent$formattedValue';
  }

  return SourceEdit(offset, 0, formattedValue);
}

/// Determines if the list containing an element is nested within another list.
/// The [currentSequenceOffset] indicates the index of the element's `-` and
/// [yaml] represents the entire yaml document.
///
/// ```yaml
/// # Returns true
/// - - value
///
/// # Returns true
/// -       - value
///
/// # Returns false
/// key:
///   - value
///
/// # Returns false. Even though nested, a "\n" precedes the previous "-"
/// -
///   - value
/// ```
(bool isNested, int offset) _isNestedInBlockList(
    int currentSequenceOffset, String yaml) {
  final startOffset = currentSequenceOffset - 1;

  /// Indicates the element we are inserting before is at index `0` of the list
  /// at the root of the yaml
  ///
  /// Example:
  ///
  /// - foo
  /// ^ Inserting before this
  if (startOffset < 0) return (false, 0);

  final newLineStart = yaml.lastIndexOf('\n', startOffset);
  final seqStart = yaml.lastIndexOf('-', startOffset);

  /// Indicates that a `\n` is closer to the last `-`. Meaning this list is not
  /// nested.
  ///
  /// Example:
  ///
  ///   key:
  ///     - value
  ///     ^ Inserting before this and we need to keep the indent.
  ///
  /// Also this list may be nested but the nested list starts its indent after
  /// a new line.
  ///
  /// Example:
  ///
  ///   -
  ///     - value
  ///     ^ Inserting before this and we need to keep the indent.
  if (newLineStart >= seqStart) {
    return (false, newLineStart + 1);
  }

  return (true, seqStart + 2); // Inclusive of space
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of inserting [item] into [list] at [index], noting that
/// this is a flow list.
///
/// [index] should be non-negative and less than or equal to `list.length`.
SourceEdit _insertInFlowList(
    YamlEditor yamlEdit, YamlList list, int index, YamlNode item) {
  RangeError.checkValueInInterval(index, 0, list.length);

  if (index == list.length) return _appendToFlowList(yamlEdit, list, item);

  final formattedValue = _formatNewFlow(list, item);

  final yaml = yamlEdit.toString();
  final currNode = list.nodes[index];
  final currNodeStart = currNode.span.start.offset;
  var start = yaml.lastIndexOf(RegExp(r',|\['), currNodeStart - 1) + 1;
  if (yaml[start] == ' ') start++;

  return SourceEdit(start, 0, formattedValue);
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of removing [nodeToRemove] from [list], noting that this
/// is a block list.
///
/// [index] should be non-negative and less than or equal to `list.length`.
SourceEdit _removeFromBlockList(
    YamlEditor yamlEdit, YamlList list, YamlNode nodeToRemove, int index) {
  RangeError.checkValueInInterval(index, 0, list.length - 1);

  final yaml = yamlEdit.toString();
  final yamlSize = yaml.length;

  final lineEnding = getLineEnding(yaml);
  final YamlNode(:span) = nodeToRemove;

  var startOffset = span.start.offset;
  startOffset =
      span.length == 0 ? startOffset : yaml.lastIndexOf('-', startOffset - 1);

  var endOffset = getContentSensitiveEnd(nodeToRemove);

  /// YamlMap may have `null` value for the last key and we need to ensure the
  /// correct [endOffset] is provided to [skipAndExtractCommentsInBlock],
  /// otherwise [skipAndExtractCommentsInBlock] may prematurely return an
  /// incorrect offset because it immediately saw `:`
  if (nodeToRemove is YamlMap &&
      endOffset < yamlSize &&
      nodeToRemove.nodes.entries.last.value.value == null) {
    endOffset += 1;
  }

  // We remove any content belonging to [nodeToRemove] greedily
  endOffset = skipAndExtractCommentsInBlock(
    yaml,
    endOffset == startOffset ? endOffset + 1 : endOffset,
    null,
    lineEnding: lineEnding,
    greedy: true,
  ).$1;

  final listSize = list.length;

  final isSingleElement = listSize == 1;
  final isLastElementInList = index == listSize - 1;
  final isLastInYaml = endOffset == yamlSize;

  final replacement = listSize == 1 ? '[]' : '';

  /// Adjust [startIndent] to include any indent this element may have had
  /// to prevent it from interfering with the indent of the next [YamlNode]
  /// which isn't in this list. We move it back if:
  ///   1. The [nodeToRemove] is the last element in a [list] with more than
  ///      one element.
  ///   2. It also isn't the first element in the yaml.
  ///
  /// Doing this only for the last element ensures that any value's indent is
  /// automatically given to the next element in the list such that,
  ///
  /// 1. If nested:
  ///     -  - value
  ///      ^ This space goes to the next element that ends up here
  ///
  /// 2. If not nested, then the next element gets the indent if any is present.
  if (isLastElementInList && startOffset != 0 && !isSingleElement) {
    final index = yaml.lastIndexOf('\n', startOffset);
    startOffset = index == -1 ? startOffset : index + 1;
  }

  /// We intentionally [skipAndExtractCommentsInBlock] greedily which also
  /// consumes the next [YamlNode]'s indent.
  ///
  /// For elements at the last index, we need to reclaim the indent belonging
  /// to the next node not in the list and optionally include a line break if
  /// if it is the only element. See [reclaimIndentAndLinebreak] for more info.
  if (isLastElementInList && !isLastInYaml) {
    endOffset = reclaimIndentAndLinebreak(
      yaml,
      endOffset,
      isSingle: isSingleElement,
    );
  } else if (isLastInYaml && yaml[endOffset - 1] == '\n' && isSingleElement) {
    /// Include any trailing line break that may have been part of the yaml:
    ///   -`\r\n` = 2
    ///   - `\n` = 1
    endOffset -= lineEnding == '\n' ? 1 : 2;
  }

  return SourceEdit(startOffset, endOffset - startOffset, replacement);
}

/// Returns a [SourceEdit] describing the change to be made on [yamlEdit] to
/// achieve the effect of removing [nodeToRemove] from [list], noting that this
/// is a flow list.
///
/// [index] should be non-negative and less than or equal to `list.length`.
SourceEdit _removeFromFlowList(
    YamlEditor yamlEdit, YamlList list, YamlNode nodeToRemove, int index) {
  RangeError.checkValueInInterval(index, 0, list.length - 1);

  final span = nodeToRemove.span;
  final yaml = yamlEdit.toString();
  var start = span.start.offset;
  var end = span.end.offset;

  if (index == 0) {
    start = yaml.lastIndexOf('[', start - 1) + 1;
    if (index == list.length - 1) {
      end = yaml.indexOf(']', end);
    } else {
      end = yaml.indexOf(',', end) + 1;
    }
  } else {
    start = yaml.lastIndexOf(',', start - 1);
  }

  return SourceEdit(start, end - start, '');
}
