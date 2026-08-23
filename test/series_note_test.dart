// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/library_item.dart';

/// The type test behind #53's answer.
///
/// A series and a collection are opposite cases and the app has to tell them
/// apart: measured on 10.11.11, labelling a **series** reaches every season and
/// episode inside it, while labelling a **collection** reaches nothing but the
/// box. One gets a reassuring note; the other gets a cascade.
void main() {
  LibraryItem item(String type) =>
      LibraryItem(id: 'i', name: 'n', type: type, tags: const []);

  test('a series is a series and not a collection', () {
    expect(item('Series').isSeries, isTrue);
    expect(item('Series').isCollection, isFalse);
  });

  test('a collection is neither', () {
    expect(item('BoxSet').isCollection, isTrue);
    expect(item('BoxSet').isSeries, isFalse);
  });

  test('a film is neither, and gets neither note', () {
    expect(item('Movie').isSeries, isFalse);
    expect(item('Movie').isCollection, isFalse);
  });

  test('an unknown type renders as a plain tile rather than throwing', () {
    // The type is kept as the server's own string on purpose — a MusicVideo or
    // a type from a later Jellyfin must not become a cascade decision.
    expect(item('MusicVideo').isSeries, isFalse);
    expect(item('MusicVideo').isCollection, isFalse);
    expect(item('').isSeries, isFalse);
  });
}
