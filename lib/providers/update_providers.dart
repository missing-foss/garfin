// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/update_repository.dart';

/// The transport for the update check, and **not** the one Jellyfin uses.
///
/// This is the whole reason it is built here rather than borrowed. The Jellyfin
/// `Dio` carries an interceptor that attaches
/// `Authorization: MediaBrowser … Token="…"` to every request it sends — an
/// admin token for the user's own server. Reusing that client for a call to
/// api.github.com would post that token to a third party, silently, on a button
/// press. This one has no interceptors, no token reader and nothing to attach;
/// `test/update_check_test.dart` asserts the request leaves without an
/// `Authorization` header and mutation-tests that assertion.
final updateDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  ),
);

final updateRepositoryProvider = Provider<UpdateRepository>(
  (ref) => UpdateRepository(dio: ref.watch(updateDioProvider)),
);
