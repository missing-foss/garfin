// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Garfin';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get serverStepTitle => 'Which server?';

  @override
  String get serverAddressLabel => 'Server address';

  @override
  String get serverAddressHint => 'http://jellyfin.local:8096';

  @override
  String get serverAddressHelp =>
      'Garfin remembers this, so you only type it once.';

  @override
  String get continueLabel => 'Continue';

  @override
  String get changeServerLabel => 'Change server';

  @override
  String get signInMethodQuickConnect => 'Quick Connect';

  @override
  String get signInMethodPassword => 'Password';

  @override
  String get quickConnectStarting => 'Asking the server for a code…';

  @override
  String get quickConnectHowTo =>
      'Open Jellyfin on any device, go to Quick Connect, and enter this code.';

  @override
  String get quickConnectWaiting => 'Waiting for the code to be approved…';

  @override
  String get quickConnectNewCode => 'Get a new code';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signInAction => 'Sign in';

  @override
  String signedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String connectedTo(String server) {
    return 'Connected to $server';
  }

  @override
  String get signOutAction => 'Sign out';

  @override
  String get homeNextUpBody =>
      'Sign-in is done. The Kids and Library screens come next.';

  @override
  String get offlineNotice =>
      'Garfin can\'t reach the server right now. This is what it already knew.';

  @override
  String get noticeCredentialsDropped =>
      'That address had a username and password in it. Garfin removed them — it can\'t sign in through a server that sits behind its own separate login.';

  @override
  String get errorMalformedServerAddress =>
      'That doesn\'t look like a web address. Try something like http://jellyfin.local:8096';

  @override
  String errorUnreachable(String server) {
    return 'Garfin couldn\'t reach $server. Check the address, and that this phone is on the same network.';
  }

  @override
  String get errorTimeout => 'The server didn\'t answer in time. Try again.';

  @override
  String get errorUnauthorized => 'That username or password didn\'t match.';

  @override
  String get errorForbidden =>
      'That account isn\'t allowed to do this on the server.';

  @override
  String get errorNotFound =>
      'Something answered at that address, but it wasn\'t Jellyfin.';

  @override
  String get errorServer =>
      'The server ran into a problem. Try again in a moment.';

  @override
  String get errorQuickConnectExpired =>
      'That code ran out. Ask for a new one.';

  @override
  String get errorQuickConnectUnavailable =>
      'Quick Connect is switched off on this server. Use a password instead.';

  @override
  String errorNotAdministrator(String name) {
    return '$name isn\'t an administrator on this server. Garfin reads and edits every account\'s shortlist, so it needs an admin account. Sign in with one.';
  }

  @override
  String get errorCancelled => 'That was stopped before it finished.';

  @override
  String get unlockPromptReason => 'Unlock Garfin';

  @override
  String get unlockTitle => 'Garfin is locked';

  @override
  String get unlockBody =>
      'Garfin signs in to Jellyfin as an admin, so it asks who you are before it opens.';

  @override
  String get unlockAction => 'Unlock';

  @override
  String get unlockFailed => 'That didn\'t match. Try again.';

  @override
  String get unlockCancelled =>
      'That was cancelled. Tap Unlock when you\'re ready.';

  @override
  String get unlockTooManyTries =>
      'Too many tries. Wait a moment, then try again.';

  @override
  String get unlockUsePinInstead =>
      'Too many fingerprint tries. Use your device PIN or pattern.';

  @override
  String get unlockError =>
      'The phone couldn\'t ask for that just now. Try again.';

  @override
  String get unlockCannotEnforce =>
      'This phone has no PIN, pattern or fingerprint set, so Garfin can\'t ask for one. Set one up in the phone\'s settings if you\'d like Garfin to ask.';

  @override
  String get unlockContinue => 'Continue';

  @override
  String get settingsUnlockTitle => 'Unlock';

  @override
  String get settingsUnlockRequire => 'Ask when Garfin opens';

  @override
  String get settingsUnlockRequireSubtitle =>
      'Garfin holds an admin sign-in to your Jellyfin server.';

  @override
  String get settingsUnlockTimeout => 'Ask again after';

  @override
  String get settingsUnlockTimeoutSubtitle =>
      'How long Garfin can sit in the background before it asks again.';

  @override
  String get unlockTimeoutImmediate => 'Straight away';

  @override
  String unlockTimeoutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get kidsTitle => 'Kids';

  @override
  String get kidsNoShortlistHeading => 'No shortlist yet';

  @override
  String get kidsNoShortlistExplanation =>
      'Set their shortlist up in Jellyfin first, then come back here.';

  @override
  String kidsVisibleOfTotal(int visible, int total) {
    return '$visible of $total things visible';
  }

  @override
  String get kidsModeAllowList => 'Shortlist';

  @override
  String get kidsModeBlockList => 'Blocklist';

  @override
  String get kidsModeConflicting => 'Both lists are set';

  @override
  String get kidsModeConflictingDetail =>
      'This account has a shortlist and a blocklist at the same time. Sort it out in Jellyfin — Garfin can\'t tell which one you meant.';

  @override
  String kidsAgeYears(int years) {
    return '$years years old';
  }

  @override
  String get kidsAgeUnknown => 'Add a birth year';

  @override
  String kidsRatingCap(String rating) {
    return 'Up to $rating';
  }

  @override
  String kidsRatingCapValue(int value) {
    return 'Rating limit $value';
  }

  @override
  String get kidsRatingCapNone => 'No rating limit';

  @override
  String get kidsBirthYearTitle => 'Birth year';

  @override
  String get kidsBirthYearHelp =>
      'Jellyfin doesn\'t store this, so Garfin keeps it on this phone. The year is enough.';

  @override
  String kidsBirthYearInvalid(int min, int max) {
    return 'Enter a year between $min and $max.';
  }

  @override
  String get kidsBirthYearClear => 'Remove';

  @override
  String get kidsEmpty => 'No accounts on this server yet.';

  @override
  String get kidsRetry => 'Try again';

  @override
  String get saveAction => 'Save';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get libraryTitle => 'Library';

  @override
  String get libraryPickingFor => 'Picking for';

  @override
  String get libraryEveryone => 'Everyone';

  @override
  String libraryNotYetGiven(int count, String name) {
    return '$count things $name hasn\'t got yet';
  }

  @override
  String libraryItemCount(int count) {
    return '$count things';
  }

  @override
  String get libraryShowShared => 'Show shared';

  @override
  String get libraryHideShared => 'Hide shared';

  @override
  String get libraryEmpty => 'Nothing here yet.';

  @override
  String libraryNothingLeft(String name) {
    return '$name has everything already.';
  }

  @override
  String get libraryBadgeGiven => 'Given';

  @override
  String get libraryBadgeBlocked => 'Blocked';

  @override
  String get libraryBadgeHeldBack => 'Held back';

  @override
  String libraryHeldBackExplanation(String name) {
    return '$name has this, but the server isn\'t showing it to them. Their age limit is the usual reason.';
  }

  @override
  String libraryCollectionCount(int count) {
    return '$count titles';
  }

  @override
  String get libraryRetry => 'Try again';

  @override
  String libraryHintAboveAge(String name) {
    return 'Above $name\'s age';
  }

  @override
  String get libraryHintUnknownAge => 'No age rating';

  @override
  String get assignTitle => 'Who gets this?';

  @override
  String assignSees(String name, int visible, int total) {
    return '$name sees $visible of $total';
  }

  @override
  String get assignChangesHeading => 'About to change';

  @override
  String assignWillGive(String name) {
    return 'Give to $name';
  }

  @override
  String assignWillTake(String name) {
    return 'Take from $name';
  }

  @override
  String get assignApply => 'Apply';

  @override
  String assignLastItemTitle(String name) {
    return '$name would see nothing';
  }

  @override
  String assignLastItemBody(Object name) {
    return 'This is the last thing labelled for $name. Take it away and their list matches nothing, so they\'ll see an empty library rather than everything.';
  }

  @override
  String get assignLastItemConfirm => 'Take it anyway';

  @override
  String assignResult(String name, int visible, int total) {
    return '$name now sees $visible of $total';
  }

  @override
  String get assignUndo => 'Undo';

  @override
  String get assignUndone => 'Put back';

  @override
  String get assignNoChildren => 'No children have a shortlist set up yet.';

  @override
  String assignCollectionNote(int count) {
    return 'Labels land on all $count titles inside, and on the collection itself.';
  }

  @override
  String assignPartOfSet(String name, int count) {
    return 'Part of $name — $count titles in the set.';
  }

  @override
  String get assignSetTogetherTitle => 'Keep the set together?';

  @override
  String assignSetTogetherBody(String title, String name) {
    return '$title is part of $name. The rest of the set can go at the same time.';
  }

  @override
  String get assignSetTogetherJustThis => 'Just this one';

  @override
  String assignSetTogetherAll(int count) {
    return 'All $count';
  }

  @override
  String assignBatchPartial(int done, int total) {
    return '$done of $total titles changed.';
  }

  @override
  String assignBatchSetIncomplete(int count) {
    return 'All $count titles changed, but the collection itself didn\'t.';
  }

  @override
  String assignBatchSetIncompleteAdded(int count) {
    return 'All $count titles are labelled, but the collection itself isn\'t. The films are there; the set isn\'t.';
  }

  @override
  String assignBatchSetIncompleteRemoved(int count) {
    return 'All $count titles are unlabelled, but the collection itself still is. The films are gone; the set is still there, and it will look empty.';
  }

  @override
  String get assignBatchPutBack => 'Put it all back';

  @override
  String get assignBatchFinish => 'Finish the rest';

  @override
  String get assignBatchRemoveAll => 'Remove all';

  @override
  String assignBatchPreflightFailed(int count) {
    return 'Nothing was changed. $count titles in this set couldn\'t be read, so Garfin left the whole set alone.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionServer => 'Server';

  @override
  String get settingsSectionLabels => 'Labels';

  @override
  String get settingsSectionPicking => 'Picking';

  @override
  String get settingsSectionLooks => 'Looks';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsRefreshCache => 'Refresh what Garfin has cached';

  @override
  String get settingsRefreshCacheDone => 'Asking the server again';

  @override
  String get settingsCollectionPrompt => 'When a title belongs to a collection';

  @override
  String get settingsCollectionPromptAsk => 'Ask each time';

  @override
  String get settingsCollectionPromptAlways => 'Hand over the whole set';

  @override
  String get settingsCollectionPromptNever => 'Just the one title';

  @override
  String get settingsRefreshAfterWrite =>
      'Refresh the title after labelling it';

  @override
  String get settingsRefreshAfterWriteSubtitle =>
      'Slower. Makes the change show up in Jellyfin straight away.';

  @override
  String get settingsStartingChild => 'Open the Library on';

  @override
  String get settingsStartingChildEveryone => 'Everyone';

  @override
  String get settingsHideShared => 'Hide what a child already has';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'Follow the phone';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsDynamicColour => 'Use the phone\'s colours';

  @override
  String get settingsPosterSize => 'Poster size';

  @override
  String get settingsPosterLarge => 'Large';

  @override
  String get settingsPosterRegular => 'Regular';

  @override
  String get settingsPosterSmall => 'Small';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsLicence =>
      'GPL-3.0-or-later. Garfin is free software, and comes with no warranty.';

  @override
  String get settingsNotAffiliated =>
      'Not affiliated with the Jellyfin project. Jellyfin is a trademark of Jellyfin, Inc.';

  @override
  String get settingsSource => 'Source code';

  @override
  String get settingsLicences => 'Open-source licences';

  @override
  String get assignSeriesNote =>
      'Everything inside the series follows it — seasons and episodes included.';

  @override
  String get filterAll => 'Filters';

  @override
  String get filterReset => 'Reset';

  @override
  String get filterAny => 'Any';

  @override
  String get filterType => 'Type';

  @override
  String get filterTypeMovie => 'Films';

  @override
  String get filterTypeSeries => 'Series';

  @override
  String get filterTypeCollection => 'Collections';

  @override
  String get filterGenre => 'Genre';

  @override
  String get filterDecade => 'Decade';

  @override
  String filterDecadeValue(int decade) {
    final intl.NumberFormat decadeNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String decadeString = decadeNumberFormat.format(decade);

    return '${decadeString}s';
  }

  @override
  String filterWithinCap(String name) {
    return 'Within $name\'s limit';
  }

  @override
  String filterActiveCount(int count) {
    return '$count';
  }

  @override
  String get activityTitle => 'Activity';

  @override
  String get activityEmpty => 'Nothing handed over yet.';

  @override
  String get activityScope =>
      'This is what Garfin did on this phone. Changes made in Jellyfin, or from another phone, aren\'t here.';

  @override
  String activityHandedTo(String name) {
    return 'Handed to $name';
  }

  @override
  String activityTakenFrom(String name) {
    return 'Taken from $name';
  }

  @override
  String get activityJustNow => 'Just now';

  @override
  String activityMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String activityHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String activityDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: 'Yesterday',
    );
    return '$_temp0';
  }

  @override
  String activityWhenCollection(String when, int count) {
    return '$when · $count titles';
  }

  @override
  String get activityUndoUnknown =>
      'That account isn\'t on the shortlist any more, so Garfin can\'t tell what undoing would mean.';

  @override
  String get deviceSignInAction => 'Sign in on a device';

  @override
  String deviceSignInTitle(String name) {
    return 'Sign $name in on a device';
  }

  @override
  String get deviceSignInHow =>
      'On their device, open Jellyfin and choose Quick Connect. Type the six digits it shows here.';

  @override
  String get deviceSignInCodeLabel => 'Six-digit code';

  @override
  String get deviceSignInApprove => 'Approve';

  @override
  String deviceSignInConfirmTitle(String name) {
    return 'Sign $name in?';
  }

  @override
  String deviceSignInConfirmCode(String code) {
    return 'Code $code';
  }

  @override
  String deviceSignInUnverified(String name) {
    return 'Garfin can\'t check which device this code came from. Only approve a code you\'ve just seen on $name\'s own screen.';
  }

  @override
  String deviceSignInDone(Object name) {
    return '$name is signed in on that device.';
  }

  @override
  String get errorQuickConnectRefused =>
      'The server wouldn\'t take that code. If it\'s already been used, ask for a fresh one on their device.';

  @override
  String get errorUnusableUserId =>
      'Garfin doesn\'t have a usable account id for that child, so it hasn\'t approved anything. Refresh what Garfin has cached, in Settings, and try again.';

  @override
  String get kidsScheduleNone => 'Can watch at any time of day.';

  @override
  String kidsScheduleServerTime(String windows) {
    return '$windows — the server\'s hours';
  }

  @override
  String kidsScheduleWindow(String day, String start, String end) {
    return '$day $start–$end';
  }

  @override
  String get kidsScheduleEveryday => 'Every day';

  @override
  String get kidsScheduleWeekday => 'Weekdays';

  @override
  String get kidsScheduleWeekend => 'Weekends';

  @override
  String deviceSignInOutsideHours(String name) {
    return '$name has set hours. Approving outside them works, but their device won\'t until their hours start.';
  }

  @override
  String get sessionsHeading => 'Signed in now';

  @override
  String sessionsOn(String device) {
    return 'on $device';
  }

  @override
  String sessionsWatching(String title) {
    return 'Watching $title';
  }

  @override
  String sessionsPaused(String title) {
    return 'Paused — $title';
  }

  @override
  String get sessionsNotPlaying => 'Nothing playing';

  @override
  String get sessionsMessage => 'Send a message';

  @override
  String get sessionsMessageHint => 'Ten more minutes';

  @override
  String get sessionsMessageSend => 'Send';

  @override
  String sessionsMessageSent(String device) {
    return 'Sent to $device.';
  }

  @override
  String get sessionsStop => 'Stop playback';

  @override
  String sessionsStopConfirm(String name) {
    return 'Stop what $name is watching?';
  }

  @override
  String sessionsStopSent(Object device) {
    return 'Asked $device to stop.';
  }

  @override
  String get sessionsEnd => 'End session';

  @override
  String sessionsEndConfirm(String name, String device) {
    return 'Sign $name out of $device?';
  }

  @override
  String get sessionsEndExplain =>
      'They\'ll need you to approve a new code to sign in again.';

  @override
  String sessionsEnded(String device) {
    return '$device is signed out.';
  }

  @override
  String get sessionsUncontrollable =>
      'This device doesn\'t accept remote commands. Ending the session still works.';
}
