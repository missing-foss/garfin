// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// One signed-in device, as `GET /Sessions` reports it.
///
/// Read-only. Garfin acts on a session through three commands and never writes
/// one back.
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.userId,
    required this.userName,
    required this.deviceId,
    required this.deviceName,
    required this.client,
    required this.supportsRemoteControl,
    this.nowPlayingName,
    this.positionTicks,
    this.runTimeTicks,
    this.isPaused = false,
  });

  final String id;
  final String userId;
  final String userName;

  /// What `DELETE /Devices?id=` takes — **not** [id]. Ending a session is keyed
  /// on the device, while the commands are keyed on the session.
  final String deviceId;

  final String deviceName;
  final String client;

  /// Whether the client says it can be remote-controlled.
  ///
  /// **Measured on 10.11.11: the commands answer 204 either way.** A session
  /// that cannot act on a message still accepts one, so this flag is the only
  /// hint available about whether anything will happen — and it is the client's
  /// own claim, which is why the copy says what Garfin *sent* rather than what
  /// the child saw.
  final bool supportsRemoteControl;

  /// Absent when nothing is playing, which is the ordinary case — the key is
  /// simply not in the response rather than being null.
  final String? nowPlayingName;

  final int? positionTicks;
  final int? runTimeTicks;
  final bool isPaused;

  bool get isPlaying => nowPlayingName != null;

  /// How far in, 0–1, or null when there is nothing to measure against.
  double? get progress {
    final position = positionTicks;
    final total = runTimeTicks;
    if (position == null || total == null || total <= 0) return null;
    return (position / total).clamp(0.0, 1.0);
  }

  static ActiveSession? fromJson(Map<String, dynamic> json) {
    final id = readString(json, 'Id');
    final userId = readString(json, 'UserId');
    final deviceId = readString(json, 'DeviceId');
    // A session with no user is the server's own housekeeping, and one with no
    // device cannot be ended — neither belongs on a screen about children.
    if (id == null || userId == null || userId.isEmpty || deviceId == null) {
      return null;
    }

    final playing = readMap(json, 'NowPlayingItem');
    final playState = readMap(json, 'PlayState');
    return ActiveSession(
      id: id,
      userId: userId,
      userName: readString(json, 'UserName') ?? '',
      deviceId: deviceId,
      deviceName: readString(json, 'DeviceName') ?? '',
      client: readString(json, 'Client') ?? '',
      supportsRemoteControl: readBool(json, 'SupportsRemoteControl'),
      nowPlayingName: playing == null ? null : readString(playing, 'Name'),
      positionTicks:
          playState == null ? null : readInt(playState, 'PositionTicks'),
      runTimeTicks: playing == null ? null : readInt(playing, 'RunTimeTicks'),
      isPaused: playState != null && readBool(playState, 'IsPaused'),
    );
  }
}
