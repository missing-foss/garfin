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

  /// Shown when the item is a collection. Measured: labelling only the container gives the child an empty collection, and labelling only the members hands over the films without the set, so both are written.
  ///
  /// In en, this message translates to:
  /// **'Labels land on all {count} titles inside, and on the collection itself.'**
  String assignCollectionNote(int count);

  /// Shown when a single film belongs to a collection. A film can be in several sets, so this line can appear more than once.
  ///
  /// In en, this message translates to:
  /// **'Part of {name} — {count} titles in the set.'**
  String assignPartOfSet(String name, int count);

  /// Title of the dialog asked once when a film being given away belongs to a collection. Additions only — removing a label never cascades.
  ///
  /// In en, this message translates to:
  /// **'Keep the set together?'**
  String get assignSetTogetherTitle;

  /// Body of the keep-the-set-together dialog, above a list of the other titles and their ratings.
  ///
  /// In en, this message translates to:
  /// **'{title} is part of {name}. The rest of the set can go at the same time.'**
  String assignSetTogetherBody(String title, String name);

  /// Declines the cascade: write the single film only.
  ///
  /// In en, this message translates to:
  /// **'Just this one'**
  String get assignSetTogetherJustThis;

  /// Accepts the cascade: write every title in the set.
  ///
  /// In en, this message translates to:
  /// **'All {count}'**
  String assignSetTogetherAll(int count);

  /// Ground rule 5's exact state after a collection write partly failed — the rule's own example is '7 of 12 tagged'. Worded for what changed rather than for tagging, because the same notice reports a partly-failed removal, and the change preview directly above already says which direction it went. Nothing that succeeded is undone; the parent chooses what happens next.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} titles changed.'**
  String assignBatchPartial(int done, int total);

  /// The other half-done state: every member took the change and the container did not. Used when the diff went both ways at once, so nothing directional can be said about what the child now sees. The two directional versions below carry the consequence.
  ///
  /// In en, this message translates to:
  /// **'All {count} titles changed, but the collection itself didn\'t.'**
  String assignBatchSetIncomplete(int count);

  /// Labels went on to every title and not to the container. Measured — the child gets the films while the collection stays absent from their library, so this is not finished.
  ///
  /// In en, this message translates to:
  /// **'All {count} titles are labelled, but the collection itself isn\'t. The films are there; the set isn\'t.'**
  String assignBatchSetIncompleteAdded(int count);

  /// The mirror image, and it must not be described as the one above. Labels came off every title and not off the container, so — measured — the child keeps the collection and finds nothing inside it.
  ///
  /// In en, this message translates to:
  /// **'All {count} titles are unlabelled, but the collection itself still is. The films are gone; the set is still there, and it will look empty.'**
  String assignBatchSetIncompleteRemoved(int count);

  /// The reversing button when the change was a removal, or went both ways: reversing it puts labels back on. Saying 'Remove all' there would name the opposite of what the button does.
  ///
  /// In en, this message translates to:
  /// **'Put it all back'**
  String get assignBatchPutBack;

  /// Retries the titles that failed. Tag writes are idempotent, so this is safe to press twice.
  ///
  /// In en, this message translates to:
  /// **'Finish the rest'**
  String get assignBatchFinish;

  /// Takes the change back off the whole set, as a forward write. Not a rollback — see ground rule 5.
  ///
  /// In en, this message translates to:
  /// **'Remove all'**
  String get assignBatchRemoveAll;

  /// Ground rule 5's pre-flight: every member is read before anything is written, and one unreadable member cancels the write.
  ///
  /// In en, this message translates to:
  /// **'Nothing was changed. {count} titles in this set couldn\'t be read, so Garfin left the whole set alone.'**
  String assignBatchPreflightFailed(int count);

  /// The fourth navigation destination, and the title of its screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings section: which Jellyfin, signed in as whom.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get settingsSectionServer;

  /// Settings section: how writing labels behaves.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get settingsSectionLabels;

  /// Settings section: how the Library opens.
  ///
  /// In en, this message translates to:
  /// **'Picking'**
  String get settingsSectionPicking;

  /// Settings section: theme, colour and poster size.
  ///
  /// In en, this message translates to:
  /// **'Looks'**
  String get settingsSectionLooks;

  /// Settings section: version, licence, source.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// Throws away the loaded library, children and collections so everything is asked for again.
  ///
  /// In en, this message translates to:
  /// **'Refresh what Garfin has cached'**
  String get settingsRefreshCache;

  /// Confirms the cache was dropped.
  ///
  /// In en, this message translates to:
  /// **'Asking the server again'**
  String get settingsRefreshCacheDone;

  /// Setting for the keep-the-set-together question. Additions only — removing a label never cascades.
  ///
  /// In en, this message translates to:
  /// **'When a title belongs to a collection'**
  String get settingsCollectionPrompt;

  /// The default. Jurassic Park and Jurassic Park III are not the same decision.
  ///
  /// In en, this message translates to:
  /// **'Ask each time'**
  String get settingsCollectionPromptAsk;

  /// Answers the question once, here, in favour of the set.
  ///
  /// In en, this message translates to:
  /// **'Hand over the whole set'**
  String get settingsCollectionPromptAlways;

  /// Answers it in favour of the single title. Never cascades.
  ///
  /// In en, this message translates to:
  /// **'Just the one title'**
  String get settingsCollectionPromptNever;

  /// Asks Jellyfin to re-read the item's metadata after a write.
  ///
  /// In en, this message translates to:
  /// **'Refresh the title after labelling it'**
  String get settingsRefreshAfterWrite;

  /// The cost of the setting above, stated plainly. One extra server round-trip per title.
  ///
  /// In en, this message translates to:
  /// **'Slower. Makes the change show up in Jellyfin straight away.'**
  String get settingsRefreshAfterWriteSubtitle;

  /// Which child is picked when the app starts.
  ///
  /// In en, this message translates to:
  /// **'Open the Library on'**
  String get settingsStartingChild;

  /// No child picked at startup. Matches the Everyone chip on the Library.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get settingsStartingChildEveryone;

  /// The stored default for the Library's Show/Hide shared button, which turns the grid into a to-do list.
  ///
  /// In en, this message translates to:
  /// **'Hide what a child already has'**
  String get settingsHideShared;

  /// Light, dark or follow the phone.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// Theme option: whatever the system is set to.
  ///
  /// In en, this message translates to:
  /// **'Follow the phone'**
  String get settingsThemeSystem;

  /// Theme option.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme option, and the default.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Material You. Off means Garfin's own purple.
  ///
  /// In en, this message translates to:
  /// **'Use the phone\'s colours'**
  String get settingsDynamicColour;

  /// How many posters fit across the Library grid.
  ///
  /// In en, this message translates to:
  /// **'Poster size'**
  String get settingsPosterSize;

  /// Poster size option: fewest per row.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settingsPosterLarge;

  /// Poster size option, and the default.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get settingsPosterRegular;

  /// Poster size option: most per row.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get settingsPosterSmall;

  /// The app version, on the About section.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// The licence line. Stays plain — docs/DECISIONS.md § Voice.
  ///
  /// In en, this message translates to:
  /// **'GPL-3.0-or-later. Garfin is free software, and comes with no warranty.'**
  String get settingsLicence;

  /// The non-affiliation line, required by BRANDING.md and kept plain.
  ///
  /// In en, this message translates to:
  /// **'Not affiliated with the Jellyfin project. Jellyfin is a trademark of Jellyfin, Inc.'**
  String get settingsNotAffiliated;

  /// Label for the repository address.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get settingsSource;

  /// Opens Flutter's licence page, which lists every bundled package.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsLicences;

  /// Shown when the item is a series. Measured on 10.11.11 (#53): the policy filter inherits from the series, so labelling it is enough for the child to reach every episode. Says what happens rather than promising anything, because it is a statement about the server's behaviour on a measured version.
  ///
  /// In en, this message translates to:
  /// **'Everything inside the series follows it — seasons and episodes included.'**
  String get assignSeriesNote;

  /// The tune button's tooltip, and the title of the sheet that opens every filter group at once.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filterAll;

  /// Clears every filter. Disabled when none is set.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get filterReset;

  /// The unset option inside a filter group — no restriction on this one.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get filterAny;

  /// Filter chip: film, series or collection. Shows this word when unset.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterType;

  /// Type filter value.
  ///
  /// In en, this message translates to:
  /// **'Films'**
  String get filterTypeMovie;

  /// Type filter value.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get filterTypeSeries;

  /// Type filter value.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get filterTypeCollection;

  /// Filter chip: the genre, from the server's own list. Hidden when the server indexes none.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get filterGenre;

  /// Filter chip: which ten years. Hidden when the server lists no production years.
  ///
  /// In en, this message translates to:
  /// **'Decade'**
  String get filterDecade;

  /// A decade as a label — 1990 becomes 1990s.
  ///
  /// In en, this message translates to:
  /// **'{decade}s'**
  String filterDecadeValue(int decade);

  /// The rating filter, shown only when a child with a rating cap is selected. Deliberately NOT 'what they can see': the server applies this as maxOfficialRating over the administrator's view, and measured, an unrated title passes every cap here while a child whose policy blocks unrated items cannot see it. Ground rule 4.
  ///
  /// In en, this message translates to:
  /// **'Within {name}\'s limit'**
  String filterWithinCap(String name);

  /// The number on the tune button's badge — how many filters are set. A string of nothing but the placeholder on purpose: it is a number, and numbers are formatted per locale, so it goes through the catalogue rather than through string interpolation.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String filterActiveCount(int count);

  /// The third navigation destination: what Garfin has written.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activityTitle;

  /// Shown when Garfin has not written anything on this phone.
  ///
  /// In en, this message translates to:
  /// **'Nothing handed over yet.'**
  String get activityEmpty;

  /// The honesty note. Measured for #57: Jellyfin records nothing for a metadata edit, so there is no history to read back — a log that looked complete would be worse than no log.
  ///
  /// In en, this message translates to:
  /// **'This is what Garfin did on this phone. Changes made in Jellyfin, or from another phone, aren\'t here.'**
  String get activityScope;

  /// An entry where the child gained access. By what it did to the child, never by what it did to the tag — ground rule 3.
  ///
  /// In en, this message translates to:
  /// **'Handed to {name}'**
  String activityHandedTo(String name);

  /// An entry where the child lost access.
  ///
  /// In en, this message translates to:
  /// **'Taken from {name}'**
  String activityTakenFrom(String name);

  /// Relative time, under a minute.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get activityJustNow;

  /// Relative time in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String activityMinutesAgo(int count);

  /// Relative time in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String activityHoursAgo(int count);

  /// Relative time in days, up to a week; older entries show a date.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Yesterday} other{{count} days ago}}'**
  String activityDaysAgo(int count);

  /// A collection entry: when it happened, and how many titles it covered. One entry per action, not per title.
  ///
  /// In en, this message translates to:
  /// **'{when} · {count} titles'**
  String activityWhenCollection(String when, int count);

  /// Shown when the entry's child no longer has a shortlist Garfin can interpret. Ground rule 3 forbids guessing a verb, so the undo is refused rather than attempted.
  ///
  /// In en, this message translates to:
  /// **'That account isn\'t on the shortlist any more, so Garfin can\'t tell what undoing would mean.'**
  String get activityUndoUnknown;

  /// On a child's card: approve the Quick Connect code their device is showing, so they can sign in without ever knowing a password.
  ///
  /// In en, this message translates to:
  /// **'Sign in on a device'**
  String get deviceSignInAction;

  /// Title of the sheet that approves a Quick Connect code for this child.
  ///
  /// In en, this message translates to:
  /// **'Sign {name} in on a device'**
  String deviceSignInTitle(String name);

  /// How to get a code. Plain instructions, no jargon about secrets or tokens.
  ///
  /// In en, this message translates to:
  /// **'On their device, open Jellyfin and choose Quick Connect. Type the six digits it shows here.'**
  String get deviceSignInHow;

  /// Label of the code field.
  ///
  /// In en, this message translates to:
  /// **'Six-digit code'**
  String get deviceSignInCodeLabel;

  /// Performs the approval, and confirms it in the dialog.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get deviceSignInApprove;

  /// Confirmation before approving — ground rule 6, because this mints a session on a device.
  ///
  /// In en, this message translates to:
  /// **'Sign {name} in?'**
  String deviceSignInConfirmTitle(String name);

  /// Reads the code back before approving. A mistyped digit is the mistake most likely here, and the only one Garfin can help with.
  ///
  /// In en, this message translates to:
  /// **'Code {code}'**
  String deviceSignInConfirmCode(String code);

  /// Measured: only the requesting device holds the secret, and no endpoint turns a code into device details. So this says plainly that nothing was verified, rather than implying Garfin checked.
  ///
  /// In en, this message translates to:
  /// **'Garfin can\'t check which device this code came from. Only approve a code you\'ve just seen on {name}\'s own screen.'**
  String deviceSignInUnverified(String name);

  /// Confirms the approval went through.
  ///
  /// In en, this message translates to:
  /// **'{name} is signed in on that device.'**
  String deviceSignInDone(Object name);

  /// Measured: a reused code and a userId that no longer exists both answer 500, so 'already used' is offered as the likely reason rather than asserted as fact.
  ///
  /// In en, this message translates to:
  /// **'The server wouldn\'t take that code. If it\'s already been used, ask for a fresh one on their device.'**
  String get errorQuickConnectRefused;

  /// Garfin's own refusal, not the server's. Measured: POST /QuickConnect/Authorize with an empty or all-zero userId answers 200 and signs the device in as the approving administrator — so an unusable id must stop the request rather than be sent.
  ///
  /// In en, this message translates to:
  /// **'Garfin doesn\'t have a usable account id for that child, so it hasn\'t approved anything. Refresh what Garfin has cached, in Settings, and try again.'**
  String get errorUnusableUserId;

  /// Shown when a child has no access schedule. Stated rather than left blank: no schedule means unrestricted hours, and a blank line would read as the opposite.
  ///
  /// In en, this message translates to:
  /// **'Can watch at any time of day.'**
  String get kidsScheduleNone;

  /// Wraps the windows with whose clock they are on. Measured for #49: the API exposes the server's UTC instant and nothing about its offset, so Garfin cannot convert these into the phone's time and must not imply it has.
  ///
  /// In en, this message translates to:
  /// **'{windows} — the server\'s hours'**
  String kidsScheduleServerTime(String windows);

  /// One access window: the day or group of days, and the hours. Hours are 24-hour because they carry no date and no zone to hang an am/pm on.
  ///
  /// In en, this message translates to:
  /// **'{day} {start}–{end}'**
  String kidsScheduleWindow(String day, String start, String end);

  /// Jellyfin's `Everyday` — one of three convenience values beside the seven days, and the one a parent most often picks.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get kidsScheduleEveryday;

  /// Jellyfin's `Weekday` convenience value.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get kidsScheduleWeekday;

  /// Jellyfin's `Weekend` convenience value.
  ///
  /// In en, this message translates to:
  /// **'Weekends'**
  String get kidsScheduleWeekend;

  /// Measured for #49: outside the window the approval and the exchange both succeed, and the session then answers 403 on every request until the hours begin. Garfin cannot tell whether now is inside the window — the server's offset is not exposed — so this says what happens rather than predicting which case applies.
  ///
  /// In en, this message translates to:
  /// **'{name} has set hours. Approving outside them works, but their device won\'t until their hours start.'**
  String deviceSignInOutsideHours(String name);

  /// Heading above the live sessions on the Kids screen. Shown only when there are any.
  ///
  /// In en, this message translates to:
  /// **'Signed in now'**
  String get sessionsHeading;

  /// Which device a child is signed in on.
  ///
  /// In en, this message translates to:
  /// **'on {device}'**
  String sessionsOn(String device);

  /// What is playing on that session.
  ///
  /// In en, this message translates to:
  /// **'Watching {title}'**
  String sessionsWatching(String title);

  /// Playback is paused. A distinct fact from watching, and the server reports it.
  ///
  /// In en, this message translates to:
  /// **'Paused — {title}'**
  String sessionsPaused(String title);

  /// Signed in but not watching anything — the ordinary case, and NowPlayingItem is simply absent.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get sessionsNotPlaying;

  /// The kindest first move: put a line of text on the child's screen.
  ///
  /// In en, this message translates to:
  /// **'Send a message'**
  String get sessionsMessage;

  /// Placeholder in the message field — an example, not a default.
  ///
  /// In en, this message translates to:
  /// **'Ten more minutes'**
  String get sessionsMessageHint;

  /// Sends the typed message.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sessionsMessageSend;

  /// Deliberately 'sent', not 'shown'. Measured: the server answers 204 even for a session that cannot display anything, so acceptance is all Garfin can honestly report.
  ///
  /// In en, this message translates to:
  /// **'Sent to {device}.'**
  String sessionsMessageSent(String device);

  /// Stops the film and leaves them signed in.
  ///
  /// In en, this message translates to:
  /// **'Stop playback'**
  String get sessionsStop;

  /// Ground rule 6: disruptive, so it is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Stop what {name} is watching?'**
  String sessionsStopConfirm(String name);

  /// 'Asked', for the same reason as sent: a 204 is the server accepting the command, not the client obeying it.
  ///
  /// In en, this message translates to:
  /// **'Asked {device} to stop.'**
  String sessionsStopSent(Object device);

  /// Revokes the device's token, signing that device out.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get sessionsEnd;

  /// Ground rule 6. Names the device as well as the child, because a child may have several.
  ///
  /// In en, this message translates to:
  /// **'Sign {name} out of {device}?'**
  String sessionsEndConfirm(String name, String device);

  /// What ending a session costs, stated in the confirmation. With #40 the way back is approving a code, which is cheap — that is what makes ending one reasonable.
  ///
  /// In en, this message translates to:
  /// **'They\'ll need you to approve a new code to sign in again.'**
  String get sessionsEndExplain;

  /// Confirms the revoke, which unlike the other two commands the server really did do — the token stops working.
  ///
  /// In en, this message translates to:
  /// **'{device} is signed out.'**
  String sessionsEnded(String device);

  /// Shown when SupportsRemoteControl is false. Measured: the message and stop commands answer 204 anyway, so without this the parent would be told something was sent to a device that cannot receive it.
  ///
  /// In en, this message translates to:
  /// **'This device doesn\'t accept remote commands. Ending the session still works.'**
  String get sessionsUncontrollable;

  /// Placeholder in the library search field (#73). 'Titles' rather than 'library', because the server matches the title and nothing else — measured: not the overview, the cast, tags or genres.
  ///
  /// In en, this message translates to:
  /// **'Search titles'**
  String get librarySearchHint;

  /// Tooltip on the x inside the search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get librarySearchClear;

  /// Top bar of the About screen (#66), reached from Settings.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// Button. One call to GitHub per press, never automatic — the copy says 'check', not 'checking automatically', because the distinction is the point.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get aboutCheckUpdates;

  /// Result: a newer release exists. Shows GitHub's own tag verbatim so it matches the releases page.
  ///
  /// In en, this message translates to:
  /// **'{tag} is available'**
  String aboutUpdateAvailable(Object tag);

  /// Result: asked, answered, nothing newer.
  ///
  /// In en, this message translates to:
  /// **'Garfin is up to date'**
  String get aboutUpdateUpToDate;

  /// Result: the repository has releases turned on but nothing published. True of Garfin itself until the first one ships, so it is not phrased as a failure.
  ///
  /// In en, this message translates to:
  /// **'No releases published yet'**
  String get aboutUpdateNone;

  /// Result: 60 anonymous requests an hour per address, measured.
  ///
  /// In en, this message translates to:
  /// **'GitHub is rate-limiting this connection. Try again in a while.'**
  String get aboutUpdateRateLimited;

  /// Result: the request never arrived. Distinct from a bad answer, because the fix is different.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach GitHub.'**
  String get aboutUpdateOffline;

  /// Result: it arrived and made no sense. Says what happened rather than blaming the network.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read GitHub\'s answer.'**
  String get aboutUpdateFailed;

  /// Action on the update-available notice: opens that release's page.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get aboutOpenRelease;

  /// Section heading on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get aboutSectionLinks;

  /// Section heading on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Licences'**
  String get aboutSectionLicences;

  /// Link to the docs/ folder in the repository.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get aboutDocs;

  /// Link to the issue tracker.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get aboutIssues;

  /// Link to the releases page, where the APKs are.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get aboutReleases;

  /// Shown when no app on the phone would take an https intent.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that link.'**
  String get aboutOpenFailed;

  /// Settings tile that opens the About screen. Replaces the four tiles that used to be the About section.
  ///
  /// In en, this message translates to:
  /// **'About Garfin'**
  String get settingsAbout;
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
