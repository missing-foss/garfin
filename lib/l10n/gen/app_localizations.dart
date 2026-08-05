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

  /// Shown by the phone's own biometric/PIN dialog, not by Garfin. Keep it very short — the system gives it one line.
  ///
  /// In en, this message translates to:
  /// **'Unlock Garfin'**
  String get unlockPromptReason;

  /// Heading on the lock screen.
  ///
  /// In en, this message translates to:
  /// **'Garfin is locked'**
  String get unlockTitle;

  /// Says why the lock exists, in one sentence. Claims nothing about what it prevents — see docs/DECISIONS.md § Voice and SECURITY.md.
  ///
  /// In en, this message translates to:
  /// **'Garfin signs in to Jellyfin as an admin, so it asks who you are before it opens.'**
  String get unlockBody;

  /// Button that asks the phone for a fingerprint or a PIN.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockAction;

  /// Shown when the fingerprint or PIN was wrong.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t match. Try again.'**
  String get unlockFailed;

  /// Shown when the user dismissed the phone's unlock dialog, or the system took it away.
  ///
  /// In en, this message translates to:
  /// **'That was cancelled. Tap Unlock when you\'re ready.'**
  String get unlockCancelled;

  /// Shown when the device has rate-limited unlock attempts and waiting clears it.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait a moment, then try again.'**
  String get unlockTooManyTries;

  /// Shown when biometrics are locked until a device credential is used.
  ///
  /// In en, this message translates to:
  /// **'Too many fingerprint tries. Use your device PIN or pattern.'**
  String get unlockUsePinInstead;

  /// Shown when the unlock attempt failed for a device-level reason that is nothing the user did.
  ///
  /// In en, this message translates to:
  /// **'The phone couldn\'t ask for that just now. Try again.'**
  String get unlockError;

  /// Shown when the device has no credential at all. Garfin cannot enforce a lock the phone does not have, and must not turn that into a lock-out — so this explains and lets the user through.
  ///
  /// In en, this message translates to:
  /// **'This phone has no PIN, pattern or fingerprint set, so Garfin can\'t ask for one. Set one up in the phone\'s settings if you\'d like Garfin to ask.'**
  String get unlockCannotEnforce;

  /// Button that dismisses the 'this phone has no PIN' notice and opens the app.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get unlockContinue;

  /// Title of the Unlock section of Settings.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get settingsUnlockTitle;

  /// Switch that turns the unlock gate on and off.
  ///
  /// In en, this message translates to:
  /// **'Ask when Garfin opens'**
  String get settingsUnlockRequire;

  /// Why the switch is on by default. States a fact rather than making a promise.
  ///
  /// In en, this message translates to:
  /// **'Garfin holds an admin sign-in to your Jellyfin server.'**
  String get settingsUnlockRequireSubtitle;

  /// Heading for the idle-timeout choices.
  ///
  /// In en, this message translates to:
  /// **'Ask again after'**
  String get settingsUnlockTimeout;

  /// Explains what the idle timeout measures.
  ///
  /// In en, this message translates to:
  /// **'How long Garfin can sit in the background before it asks again.'**
  String get settingsUnlockTimeoutSubtitle;

  /// The zero-length idle timeout: ask every time Garfin comes back to the foreground.
  ///
  /// In en, this message translates to:
  /// **'Straight away'**
  String get unlockTimeoutImmediate;

  /// An idle timeout of a whole number of minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String unlockTimeoutMinutes(int count);

  /// Title of the Kids screen, which lists children and their shortlists.
  ///
  /// In en, this message translates to:
  /// **'Kids'**
  String get kidsTitle;

  /// Heading above the list of accounts that have no shortlist tags set.
  ///
  /// In en, this message translates to:
  /// **'No shortlist yet'**
  String get kidsNoShortlistHeading;

  /// Explains why these accounts are listed but cannot be acted on. Garfin cannot give a child their first label; that is a policy write. Deliberately says nothing about why, per docs/UI-SPEC.md.
  ///
  /// In en, this message translates to:
  /// **'Set their shortlist up in Jellyfin first, then come back here.'**
  String get kidsNoShortlistExplanation;

  /// Count on a child's card. Both numbers come from the server, never computed here.
  ///
  /// In en, this message translates to:
  /// **'{visible} of {total} things visible'**
  String kidsVisibleOfTotal(int visible, int total);

  /// Chip on a card whose account uses AllowedTags: the child sees only what is tagged.
  ///
  /// In en, this message translates to:
  /// **'Shortlist'**
  String get kidsModeAllowList;

  /// Chip on a card whose account uses BlockedTags: the child sees everything except what is tagged.
  ///
  /// In en, this message translates to:
  /// **'Blocklist'**
  String get kidsModeBlockList;

  /// Shown when a Jellyfin account has both AllowedTags and BlockedTags populated. Garfin refuses to guess which applies.
  ///
  /// In en, this message translates to:
  /// **'Both lists are set'**
  String get kidsModeConflicting;

  /// Explains the conflicting-lists state and what to do about it.
  ///
  /// In en, this message translates to:
  /// **'This account has a shortlist and a blocklist at the same time. Sort it out in Jellyfin — Garfin can\'t tell which one you meant.'**
  String get kidsModeConflictingDetail;

  /// Age on a child's card, worked out from the birth year the parent entered.
  ///
  /// In en, this message translates to:
  /// **'{years} years old'**
  String kidsAgeYears(int years);

  /// Shown in place of an age when no birth year has been entered. Jellyfin does not store one.
  ///
  /// In en, this message translates to:
  /// **'Add a birth year'**
  String get kidsAgeUnknown;

  /// The child's parental rating cap, named from the server's own rating list.
  ///
  /// In en, this message translates to:
  /// **'Up to {rating}'**
  String kidsRatingCap(String rating);

  /// Fallback when the server's rating list has no entry for the child's cap. Shows the raw number rather than guessing a nearby name.
  ///
  /// In en, this message translates to:
  /// **'Rating limit {value}'**
  String kidsRatingCapValue(int value);

  /// Shown when a child's account has no parental rating cap set.
  ///
  /// In en, this message translates to:
  /// **'No rating limit'**
  String get kidsRatingCapNone;

  /// Title of the dialog where the parent types a child's birth year.
  ///
  /// In en, this message translates to:
  /// **'Birth year'**
  String get kidsBirthYearTitle;

  /// Explains why the birth year is asked for and that it stays on the device.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin doesn\'t store this, so Garfin keeps it on this phone. The year is enough.'**
  String get kidsBirthYearHelp;

  /// Validation message for the birth year field.
  ///
  /// In en, this message translates to:
  /// **'Enter a year between {min} and {max}.'**
  String kidsBirthYearInvalid(int min, int max);

  /// Button that forgets a stored birth year.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get kidsBirthYearClear;

  /// Shown when the server reports no users at all.
  ///
  /// In en, this message translates to:
  /// **'No accounts on this server yet.'**
  String get kidsEmpty;

  /// Button that reloads the Kids screen after an error.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get kidsRetry;

  /// Confirms a dialog.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// Dismisses a dialog without changing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// Title of the library grid screen.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// Label above the row of child avatars at the top of the library.
  ///
  /// In en, this message translates to:
  /// **'Picking for'**
  String get libraryPickingFor;

  /// The option in the picking-for row that clears the child selection.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get libraryEveryone;

  /// Result line when a child is selected. Says what has not been handed over, NOT what the child can see — the second is the server's answer and includes the rating cap.
  ///
  /// In en, this message translates to:
  /// **'{count} things {name} hasn\'t got yet'**
  String libraryNotYetGiven(int count, String name);

  /// Result line when no child is selected.
  ///
  /// In en, this message translates to:
  /// **'{count} things'**
  String libraryItemCount(int count);

  /// Button revealing items already given to the selected child.
  ///
  /// In en, this message translates to:
  /// **'Show shared'**
  String get libraryShowShared;

  /// Button hiding items already given to the selected child.
  ///
  /// In en, this message translates to:
  /// **'Hide shared'**
  String get libraryHideShared;

  /// Shown when the library query returns no items at all.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get libraryEmpty;

  /// Shown when hiding shared items leaves nothing to give.
  ///
  /// In en, this message translates to:
  /// **'{name} has everything already.'**
  String libraryNothingLeft(String name);

  /// Badge on a tile the selected child has been given and can reach.
  ///
  /// In en, this message translates to:
  /// **'Given'**
  String get libraryBadgeGiven;

  /// Badge on a tile taken away from a block-list child.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get libraryBadgeBlocked;

  /// Badge for an item the child has been given but the server still does not show them. Deliberately does not name a cause — the server does not say why.
  ///
  /// In en, this message translates to:
  /// **'Held back'**
  String get libraryBadgeHeldBack;

  /// Explains a held-back item. Offers the likely reason rather than asserting it: the server does not say why it hid something, and a folder permission looks identical.
  ///
  /// In en, this message translates to:
  /// **'{name} has this, but the server isn\'t showing it to them. Their age limit is the usual reason.'**
  String libraryHeldBackExplanation(String name);

  /// Badge on a collection tile saying how many items it holds.
  ///
  /// In en, this message translates to:
  /// **'{count} titles'**
  String libraryCollectionCount(int count);

  /// Button that reloads the library grid after an error.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get libraryRetry;

  /// Hint on a tile whose rating is above the child's age. A suggestion for the parent, not a restriction — nothing is enforced by it.
  ///
  /// In en, this message translates to:
  /// **'Above {name}\'s age'**
  String libraryHintAboveAge(String name);

  /// Shown when Garfin cannot tell whether a title suits the child: the item has no rating, its rating is not on the server's list, no birth year is set, or the value is not an age. Must read as 'not known', never as 'fine'.
  ///
  /// In en, this message translates to:
  /// **'No age rating'**
  String get libraryHintUnknownAge;

  /// Title of the assign sheet, opened by tapping a title in the library.
  ///
  /// In en, this message translates to:
  /// **'Who gets this?'**
  String get assignTitle;

  /// A child's current visible count on their row. Fetched from the server, never predicted.
  ///
  /// In en, this message translates to:
  /// **'{name} sees {visible} of {total}'**
  String assignSees(String name, int visible, int total);

  /// Heading above the preview of exactly what will be written.
  ///
  /// In en, this message translates to:
  /// **'About to change'**
  String get assignChangesHeading;

  /// A line in the change preview: this child gains access.
  ///
  /// In en, this message translates to:
  /// **'Give to {name}'**
  String assignWillGive(String name);

  /// A line in the change preview: this child loses access.
  ///
  /// In en, this message translates to:
  /// **'Take from {name}'**
  String assignWillTake(String name);

  /// Writes the previewed changes.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get assignApply;

  /// Title of the hard warning shown when a removal would take a child's label off the last item carrying it.
  ///
  /// In en, this message translates to:
  /// **'{name} would see nothing'**
  String assignLastItemTitle(String name);

  /// Explains the last-item case. The important part is that the child sees NOTHING, not everything — the opposite of what a parent might assume.
  ///
  /// In en, this message translates to:
  /// **'This is the last thing labelled for {name}. Take it away and their list matches nothing, so they\'ll see an empty library rather than everything.'**
  String assignLastItemBody(Object name);

  /// Confirms the removal despite the last-item warning.
  ///
  /// In en, this message translates to:
  /// **'Take it anyway'**
  String get assignLastItemConfirm;

  /// Reported after a write, using the count re-fetched from the server. This is also what explains a share the rating cap swallowed.
  ///
  /// In en, this message translates to:
  /// **'{name} now sees {visible} of {total}'**
  String assignResult(String name, int visible, int total);

  /// Reverses the change just made. A fresh forward write, not a restore.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get assignUndo;

  /// Confirms the undo completed.
  ///
  /// In en, this message translates to:
  /// **'Put back'**
  String get assignUndone;

  /// Shown on the assign sheet when no account is under shortlist control.
  ///
  /// In en, this message translates to:
  /// **'No children have a shortlist set up yet.'**
  String get assignNoChildren;

  /// Shown when the item is a collection. Cascading to members is build order step 6, and pretending otherwise would silently do nothing useful.
  ///
  /// In en, this message translates to:
  /// **'Collections are handled later — this labels the collection itself, not the titles inside.'**
  String get assignCollectionNote;
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
