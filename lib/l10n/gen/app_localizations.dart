import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// The app's name. A proper noun — left untranslated in every locale.
  ///
  /// In en, this message translates to:
  /// **'Garfin'**
  String get appTitle;

  /// Title of the sign-in screen.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// Heading for the first sign-in step, where the Jellyfin server address is typed.
  ///
  /// In en, this message translates to:
  /// **'Which server?'**
  String get serverStepTitle;

  /// Label on the text field for the Jellyfin server URL.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddressLabel;

  /// Placeholder inside the server address field. An example URL rather than a sentence — leave it as-is unless the example itself should differ in this locale.
  ///
  /// In en, this message translates to:
  /// **'http://jellyfin.local:8096'**
  String get serverAddressHint;

  /// Helper text under the server address field.
  ///
  /// In en, this message translates to:
  /// **'Garfin remembers this, so you only type it once.'**
  String get serverAddressHelp;

  /// Button that accepts the typed server address and moves on to the sign-in method.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// Button that goes back to the server address step.
  ///
  /// In en, this message translates to:
  /// **'Change server'**
  String get changeServerLabel;

  /// Tab label. Quick Connect is Jellyfin's own feature name — keep it untranslated so it matches what the user sees inside Jellyfin.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect'**
  String get signInMethodQuickConnect;

  /// Tab label for the username-and-password fallback.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get signInMethodPassword;

  /// Shown between opening the Quick Connect tab and the six-digit code arriving.
  ///
  /// In en, this message translates to:
  /// **'Asking the server for a code…'**
  String get quickConnectStarting;

  /// Instructions shown above the six-digit Quick Connect code.
  ///
  /// In en, this message translates to:
  /// **'Open Jellyfin on any device, go to Quick Connect, and enter this code.'**
  String get quickConnectHowTo;

  /// Shown beside the indeterminate progress bar while Garfin polls for approval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the code to be approved…'**
  String get quickConnectWaiting;

  /// Button that starts a fresh Quick Connect pairing after one expired or failed.
  ///
  /// In en, this message translates to:
  /// **'Get a new code'**
  String get quickConnectNewCode;

  /// Label on the username field of the password sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// Label on the password field of the password sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// Button that submits the username and password.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInAction;

  /// Names the Jellyfin account Garfin is using.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String signedInAs(String name);

  /// Names the Jellyfin server address Garfin is talking to.
  ///
  /// In en, this message translates to:
  /// **'Connected to {server}'**
  String connectedTo(String server);

  /// Button that forgets the account and the access token.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutAction;

  /// Body of the temporary home screen shown after signing in, until the Library screen exists.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is done. The Kids and Library screens come next.'**
  String get homeNextUpBody;

  /// Banner shown when a stored session could not be confirmed because the server is unreachable. The app stays usable with what it has cached.
  ///
  /// In en, this message translates to:
  /// **'Garfin can\'t reach the server right now. This is what it already knew.'**
  String get offlineNotice;

  /// Shown when the typed server address contained user:password@. The credentials are dropped rather than stored, because they would otherwise be written to preferences in clear and shown on screen — and Jellyfin offers no way to pass its own identity while the Authorization header is taken by a proxy. Says what happened rather than failing silently.
  ///
  /// In en, this message translates to:
  /// **'That address had a username and password in it. Garfin removed them — it can\'t sign in through a server that sits behind its own separate login.'**
  String get noticeCredentialsDropped;

  /// Shown when the typed server address cannot be parsed at all, so nothing was sent anywhere.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a web address. Try something like http://jellyfin.local:8096'**
  String get errorMalformedServerAddress;

  /// Shown when no answer came back from the server at all.
  ///
  /// In en, this message translates to:
  /// **'Garfin couldn\'t reach {server}. Check the address, and that this phone is on the same network.'**
  String errorUnreachable(String server);

  /// Shown when a request timed out.
  ///
  /// In en, this message translates to:
  /// **'The server didn\'t answer in time. Try again.'**
  String get errorTimeout;

  /// Shown for HTTP 401 during sign-in.
  ///
  /// In en, this message translates to:
  /// **'That username or password didn\'t match.'**
  String get errorUnauthorized;

  /// Shown for HTTP 403.
  ///
  /// In en, this message translates to:
  /// **'That account isn\'t allowed to do this on the server.'**
  String get errorForbidden;

  /// Shown for HTTP 404 — usually a URL pointing at some other service.
  ///
  /// In en, this message translates to:
  /// **'Something answered at that address, but it wasn\'t Jellyfin.'**
  String get errorNotFound;

  /// Shown for HTTP 5xx, or a response that could not be read.
  ///
  /// In en, this message translates to:
  /// **'The server ran into a problem. Try again in a moment.'**
  String get errorServer;

  /// Shown when a Quick Connect code was never approved inside the polling window.
  ///
  /// In en, this message translates to:
  /// **'That code ran out. Ask for a new one.'**
  String get errorQuickConnectExpired;

  /// Shown when the server reports Quick Connect as disabled.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect is switched off on this server. Use a password instead.'**
  String get errorQuickConnectUnavailable;

  /// Shown when an account authenticated but is not a Jellyfin administrator. Ground rule 7 — the refusal happens at sign-in, and the wording says which account was refused and what to do instead.
  ///
  /// In en, this message translates to:
  /// **'{name} isn\'t an administrator on this server. Garfin reads and edits every account\'s shortlist, so it needs an admin account. Sign in with one.'**
  String errorNotAdministrator(String name);

  /// Shown when a request was cancelled — the screen was closed, or the user backed out.
  ///
  /// In en, this message translates to:
  /// **'That was stopped before it finished.'**
  String get errorCancelled;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
