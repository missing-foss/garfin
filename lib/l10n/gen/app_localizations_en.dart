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
}
