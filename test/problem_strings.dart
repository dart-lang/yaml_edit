// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const problemStrings = [
  '[]',
  '{}',
  '',
  ',',
  '~',
  'undefined',
  'undef',
  'null',
  'NULL',
  '(null)',
  'nil',
  'NIL',
  'true',
  'false',
  'True',
  'False',
  'TRUE',
  'FALSE',
  'None',
  '\\',
  '\\\\',
  '0',
  '1',
  '\$1.00',
  '1/2',
  '1E2',
  '-\$1.00',
  '-1/2',
  '-1E+02',
  '1/0',
  '0/0',
  '-0',
  '+0.0',
  '0..0',
  '.',
  '0.0.0',
  '0,00',
  ',',
  '0.0/0',
  '1.0/0.0',
  '0.0/0.0',
  '--1',
  '-',
  '-.',
  '-,',
  '999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',
  'NaN',
  'Infinity',
  '-Infinity',
  'INF',
  '1#INF',
  '0x0',
  '0xffffffffffffffff',
  "1'000.00",
  '1,000,000.00',
  '1.000,00',
  "1'000,00",
  '1.000.000,00',
  ",./;'[]\\-=",
  '<>?:"{}|_+',
  '!@#\$%^&*()`~',
  '\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\u000e\u000f\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b\u001c\u001d\u001e\u001f',
  '\t\u000b\f              ​    　',
  'ด้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็ ด้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็ ด้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็็้้้้้้้้็็็็็้้้้้็็็็',
  "'",
  '"',
  "''",
  '\'"',
  "'\"'",
  '社會科學院語學研究所',
  'Ⱥ',
  'ヽ༼ຈل͜ຈ༽ﾉ ヽ༼ຈل͜ຈ༽ﾉ',
  '❤️ 💔 💌 💕 💞 💓 💗 💖 💘 💝 💟 💜 💛 💚 💙',
  '𝕋𝕙𝕖 𝕢𝕦𝕚𝕔𝕜 𝕓𝕣𝕠𝕨𝕟 𝕗𝕠𝕩 𝕛𝕦𝕞𝕡𝕤 𝕠𝕧𝕖𝕣 𝕥𝕙𝕖 𝕝𝕒𝕫𝕪 𝕕𝕠𝕘',
  ' ',
  '%',
  '%d',
  '%s%s%s%s%s',
  '{0}',
  '%*.*s',
  '%@',
  '%n',
  'The quic\b\b\b\b\b\bk brown fo\u0007\u0007\u0007\u0007\u0007\u0007\u0007\u0007\u0007\u0007\u0007x... [Beeeep]',
];
