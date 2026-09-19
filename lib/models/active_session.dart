// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// One signed-in device, as `GET /Sessions` reports it.
///
/// Read-only. Garfin acts on a session through three commands and never writes
/// one back.
///
/// **The now-playing fields beyond `Name` and `RunTimeTicks` were inferred from
/// the shape of `BaseItemDto` and have since been measured.** Read off a live
/// server on 2026-08-24, one episode and one film; the inference held exactly.
/// See `docs/JELLYFIN-API.md` for the fields and the aspect ratios.
///
/// They stay optional all the same. That is one server and one version, not a
/// survey, and an absent field still costs only the artwork: [showName] says
/// nothing extra and [artwork] resolves to null, which is the card as it drew
/// before there was any artwork at all.
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
    this.nowPlayingId,
    this.nowPlayingType,
    this.nowPlayingImageTag,
    this.seriesName,
    this.seriesId,
    this.seriesPrimaryImageTag,
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
  ///
  /// For an episode this is the **episode's** name, which is why the six fields
  /// below exist: "Chapter 3" on its own tells a parent nothing about what is
  /// on the screen.
  final String? nowPlayingName;

  /// The playing item's own id, for its artwork.
  final String? nowPlayingId;

  /// `Movie`, `Episode`, `Series` — the server's own string, kept as one for
  /// the same reason `LibraryItem.type` is: an unrecognised kind should render
  /// as a plain card rather than throw.
  final String? nowPlayingType;

  /// The playing item's own primary image tag, absent when it has no image.
  ///
  /// **Not used for an episode.** An episode's primary image is a still from
  /// the episode — measured `PrimaryImageAspectRatio` ≈ 1.78 — and the card's
  /// artwork box is a 2:3 poster, so cropping one into the other gives a parent
  /// a rectangle they cannot place. See [artwork].
  final String? nowPlayingImageTag;

  /// The show an episode belongs to.
  final String? seriesName;

  /// The show's id, for its poster.
  final String? seriesId;

  /// The show's poster tag, which is what makes an episode's card show the
  /// thing a parent recognises.
  final String? seriesPrimaryImageTag;

  final int? positionTicks;
  final int? runTimeTicks;
  final bool isPaused;

  bool get isPlaying => nowPlayingName != null;

  /// The show's name, when what is playing belongs to one.
  ///
  /// Empty is treated as absent: a blank line above the episode name would
  /// read as a missing title rather than as a film.
  String? get showName =>
      (seriesName != null && seriesName!.isNotEmpty) ? seriesName : null;

  /// Which image the card should draw, or null when there is none to draw.
  ///
  /// **The show's poster for an episode**, and the episode's own image is
  /// deliberately not a fallback — see [nowPlayingImageTag]. Measured: the
  /// episode's own primary image is 16:9 (`PrimaryImageAspectRatio` ≈ 1.78)
  /// against a film poster's ≈ 0.67, so cropping it into a poster box is
  /// rejected on a number rather than on taste. Everything else uses its own
  /// primary image, which is the film case and also the sensible default for a
  /// kind Garfin does not recognise.
  ///
  /// Null wherever a tag is missing, and that is the whole failure mode: the
  /// card falls back to the placeholder it drew before there was any artwork
  /// at all.
  NowPlayingArtwork? get artwork {
    // **Branched on `Type`, not on which fields happen to be present.** Asking
    // "is there a `SeriesId`?" gets the same answer for the two kinds measured
    // — the series fields are absent on a film rather than empty — but it is
    // not what was measured, and `Type` is the field the server uses to say
    // what the item is. Anything else carrying a `SeriesId` would otherwise be
    // drawn with a poster chosen for a different kind of thing.
    if (nowPlayingType == 'Episode') {
      final showId = seriesId;
      final showTag = seriesPrimaryImageTag;
      if (showId == null || showTag == null) return null;
      return NowPlayingArtwork(itemId: showId, imageTag: showTag);
    }

    final id = nowPlayingId;
    final tag = nowPlayingImageTag;
    if (id != null && tag != null) {
      return NowPlayingArtwork(itemId: id, imageTag: tag);
    }
    return null;
  }

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
      nowPlayingId: playing == null ? null : _nonEmpty(playing, 'Id'),
      nowPlayingType: playing == null ? null : readString(playing, 'Type'),
      nowPlayingImageTag: playing == null ? null : _primaryImageTag(playing),
      seriesName: playing == null ? null : readString(playing, 'SeriesName'),
      seriesId: playing == null ? null : _nonEmpty(playing, 'SeriesId'),
      seriesPrimaryImageTag:
          playing == null ? null : _nonEmpty(playing, 'SeriesPrimaryImageTag'),
      positionTicks:
          playState == null ? null : readInt(playState, 'PositionTicks'),
      runTimeTicks: playing == null ? null : readInt(playing, 'RunTimeTicks'),
      isPaused: playState != null && readBool(playState, 'IsPaused'),
    );
  }

  /// An item's `ImageTags.Primary`, which items carry in a map — unlike users,
  /// which carry one string. Same shape as `LibraryItem`'s.
  static String? _primaryImageTag(Map<String, dynamic> json) {
    final tags = readMap(json, 'ImageTags');
    return tags == null ? null : _nonEmpty(tags, 'Primary');
  }

  /// A string field where the empty string means the same as absent.
  ///
  /// **Both halves of an artwork reference go through this, and they did not
  /// always.** An empty tag builds a URL asking the server for image version
  /// "", and an empty id builds `/Items//Images/Primary` — a request for
  /// nothing, at a path that is not the item's. Either is drawn as a broken
  /// poster where the placeholder is the honest answer, so guarding one and
  /// not the other was an asymmetry rather than a decision. Raised in review.
  static String? _nonEmpty(Map<String, dynamic> json, String name) {
    final value = readString(json, name);
    return (value != null && value.isNotEmpty) ? value : null;
  }
}

/// Which image to fetch for what is playing: an item, and the version of its
/// artwork.
///
/// The tag is not decoration. It is what makes the URL change when the artwork
/// does, so a cached poster cannot outlive the picture it shows — the same
/// reason the library grid carries one.
class NowPlayingArtwork {
  const NowPlayingArtwork({required this.itemId, required this.imageTag});

  final String itemId;
  final String imageTag;

  @override
  bool operator ==(Object other) =>
      other is NowPlayingArtwork &&
      other.itemId == itemId &&
      other.imageTag == imageTag;

  @override
  int get hashCode => Object.hash(itemId, imageTag);
}
