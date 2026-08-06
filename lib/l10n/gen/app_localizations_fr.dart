// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Garfin';

  @override
  String get signInTitle => 'Connexion';

  @override
  String get serverStepTitle => 'Quel serveur ?';

  @override
  String get serverAddressLabel => 'Adresse du serveur';

  @override
  String get serverAddressHint => 'http://jellyfin.local:8096';

  @override
  String get serverAddressHelp =>
      'Garfin la retient, vous ne la tapez qu\'une fois.';

  @override
  String get continueLabel => 'Continuer';

  @override
  String get changeServerLabel => 'Changer de serveur';

  @override
  String get signInMethodQuickConnect => 'Quick Connect';

  @override
  String get signInMethodPassword => 'Mot de passe';

  @override
  String get quickConnectStarting => 'Demande d\'un code au serveur…';

  @override
  String get quickConnectHowTo =>
      'Ouvrez Jellyfin sur n\'importe quel appareil, allez dans Quick Connect et saisissez ce code.';

  @override
  String get quickConnectWaiting => 'En attente de la validation du code…';

  @override
  String get quickConnectNewCode => 'Obtenir un nouveau code';

  @override
  String get usernameLabel => 'Nom d\'utilisateur';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get signInAction => 'Se connecter';

  @override
  String signedInAs(String name) {
    return 'Connecté en tant que $name';
  }

  @override
  String connectedTo(String server) {
    return 'Relié à $server';
  }

  @override
  String get signOutAction => 'Se déconnecter';

  @override
  String get homeNextUpBody =>
      'La connexion est faite. Les écrans Enfants et Bibliothèque arrivent ensuite.';

  @override
  String get offlineNotice =>
      'Garfin n\'arrive pas à joindre le serveur pour le moment. Voici ce qu\'il savait déjà.';

  @override
  String get noticeCredentialsDropped =>
      'Cette adresse contenait un nom d\'utilisateur et un mot de passe. Garfin les a retirés : il ne peut pas se connecter à travers un serveur placé derrière son propre accès.';

  @override
  String get errorMalformedServerAddress =>
      'Cela ne ressemble pas à une adresse web. Essayez plutôt http://jellyfin.local:8096';

  @override
  String errorUnreachable(String server) {
    return 'Garfin n\'a pas pu joindre $server. Vérifiez l\'adresse, et que ce téléphone est sur le même réseau.';
  }

  @override
  String get errorTimeout => 'Le serveur n\'a pas répondu à temps. Réessayez.';

  @override
  String get errorUnauthorized =>
      'Ce nom d\'utilisateur ou ce mot de passe ne correspond pas.';

  @override
  String get errorForbidden =>
      'Ce compte n\'a pas le droit de faire cela sur le serveur.';

  @override
  String get errorNotFound =>
      'Quelque chose a répondu à cette adresse, mais ce n\'était pas Jellyfin.';

  @override
  String get errorServer =>
      'Le serveur a rencontré un problème. Réessayez dans un instant.';

  @override
  String get errorQuickConnectExpired =>
      'Ce code a expiré. Demandez-en un nouveau.';

  @override
  String get errorQuickConnectUnavailable =>
      'Quick Connect est désactivé sur ce serveur. Utilisez plutôt un mot de passe.';

  @override
  String errorNotAdministrator(String name) {
    return '$name n\'est pas administrateur sur ce serveur. Garfin lit et modifie la liste de chaque compte, il lui faut donc un compte administrateur. Connectez-vous avec un tel compte.';
  }

  @override
  String get errorCancelled => 'L\'opération a été interrompue avant la fin.';

  @override
  String get unlockPromptReason => 'Déverrouiller Garfin';

  @override
  String get unlockTitle => 'Garfin est verrouillé';

  @override
  String get unlockBody =>
      'Garfin se connecte à Jellyfin en tant qu\'administrateur : il demande qui vous êtes avant de s\'ouvrir.';

  @override
  String get unlockAction => 'Déverrouiller';

  @override
  String get unlockFailed => 'Cela ne correspond pas. Réessayez.';

  @override
  String get unlockCancelled =>
      'Annulé. Touchez Déverrouiller quand vous voulez.';

  @override
  String get unlockTooManyTries =>
      'Trop d\'essais. Patientez un instant, puis réessayez.';

  @override
  String get unlockUsePinInstead =>
      'Trop d\'essais avec l\'empreinte. Utilisez le code ou le schéma de l\'appareil.';

  @override
  String get unlockError =>
      'Le téléphone n\'a pas pu le demander pour le moment. Réessayez.';

  @override
  String get unlockCannotEnforce =>
      'Ce téléphone n\'a ni code, ni schéma, ni empreinte : Garfin ne peut donc rien demander. Configurez-en un dans les réglages du téléphone si vous voulez que Garfin le demande.';

  @override
  String get unlockContinue => 'Continuer';

  @override
  String get settingsUnlockTitle => 'Verrouillage';

  @override
  String get settingsUnlockRequire => 'Demander à l\'ouverture de Garfin';

  @override
  String get settingsUnlockRequireSubtitle =>
      'Garfin garde une connexion administrateur à votre serveur Jellyfin.';

  @override
  String get settingsUnlockTimeout => 'Redemander après';

  @override
  String get settingsUnlockTimeoutSubtitle =>
      'Combien de temps Garfin peut rester en arrière-plan avant de redemander.';

  @override
  String get unlockTimeoutImmediate => 'Immédiatement';

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
  String get kidsTitle => 'Enfants';

  @override
  String get kidsNoShortlistHeading => 'Pas encore de sélection';

  @override
  String get kidsNoShortlistExplanation =>
      'Créez d\'abord leur sélection dans Jellyfin, puis revenez ici.';

  @override
  String kidsVisibleOfTotal(int visible, int total) {
    return '$visible sur $total titres visibles';
  }

  @override
  String get kidsModeAllowList => 'Sélection';

  @override
  String get kidsModeBlockList => 'Liste d\'exclusion';

  @override
  String get kidsModeConflicting => 'Les deux listes sont définies';

  @override
  String get kidsModeConflictingDetail =>
      'Ce compte a une sélection et une liste d\'exclusion en même temps. Corrigez cela dans Jellyfin — Garfin ne peut pas deviner laquelle s\'applique.';

  @override
  String kidsAgeYears(int years) {
    return '$years ans';
  }

  @override
  String get kidsAgeUnknown => 'Ajouter une année de naissance';

  @override
  String kidsRatingCap(String rating) {
    return 'Jusqu\'à $rating';
  }

  @override
  String kidsRatingCapValue(int value) {
    return 'Limite d\'âge $value';
  }

  @override
  String get kidsRatingCapNone => 'Aucune limite d\'âge';

  @override
  String get kidsBirthYearTitle => 'Année de naissance';

  @override
  String get kidsBirthYearHelp =>
      'Jellyfin ne l\'enregistre pas, Garfin la garde donc sur ce téléphone. L\'année suffit.';

  @override
  String kidsBirthYearInvalid(int min, int max) {
    return 'Saisissez une année entre $min et $max.';
  }

  @override
  String get kidsBirthYearClear => 'Supprimer';

  @override
  String get kidsEmpty => 'Aucun compte sur ce serveur pour le moment.';

  @override
  String get kidsRetry => 'Réessayer';

  @override
  String get saveAction => 'Enregistrer';

  @override
  String get cancelAction => 'Annuler';

  @override
  String get libraryTitle => 'Médiathèque';

  @override
  String get libraryPickingFor => 'Choix pour';

  @override
  String get libraryEveryone => 'Tout le monde';

  @override
  String libraryNotYetGiven(int count, String name) {
    return '$count titres que $name n\'a pas encore';
  }

  @override
  String libraryItemCount(int count) {
    return '$count titres';
  }

  @override
  String get libraryShowShared => 'Afficher les partagés';

  @override
  String get libraryHideShared => 'Masquer les partagés';

  @override
  String get libraryEmpty => 'Rien ici pour le moment.';

  @override
  String libraryNothingLeft(String name) {
    return '$name a déjà tout.';
  }

  @override
  String get libraryBadgeGiven => 'Donné';

  @override
  String get libraryBadgeBlocked => 'Bloqué';

  @override
  String get libraryBadgeHeldBack => 'Retenu';

  @override
  String libraryHeldBackExplanation(String name) {
    return '$name a ce titre, mais le serveur ne le lui montre pas. La limite d\'âge en est la raison habituelle.';
  }

  @override
  String libraryCollectionCount(int count) {
    return '$count titres';
  }

  @override
  String get libraryRetry => 'Réessayer';

  @override
  String libraryHintAboveAge(String name) {
    return 'Au-dessus de l\'âge de $name';
  }

  @override
  String get libraryHintUnknownAge => 'Pas de classification';

  @override
  String get assignTitle => 'Pour qui ?';

  @override
  String assignSees(String name, int visible, int total) {
    return '$name voit $visible sur $total';
  }

  @override
  String get assignChangesHeading => 'Modifications à venir';

  @override
  String assignWillGive(String name) {
    return 'Donner à $name';
  }

  @override
  String assignWillTake(String name) {
    return 'Retirer à $name';
  }

  @override
  String get assignApply => 'Appliquer';

  @override
  String assignLastItemTitle(String name) {
    return '$name ne verrait plus rien';
  }

  @override
  String assignLastItemBody(Object name) {
    return 'C\'est le dernier titre étiqueté pour $name. Si vous le retirez, sa liste ne correspond à rien : sa médiathèque sera vide, et non complète.';
  }

  @override
  String get assignLastItemConfirm => 'Retirer quand même';

  @override
  String assignResult(String name, int visible, int total) {
    return '$name voit maintenant $visible sur $total';
  }

  @override
  String get assignUndo => 'Annuler';

  @override
  String get assignUndone => 'Rétabli';

  @override
  String get assignNoChildren =>
      'Aucun enfant n\'a encore de sélection configurée.';

  @override
  String assignCollectionNote(int count) {
    return 'Les étiquettes sont posées sur les $count titres de la collection, et sur la collection elle-même.';
  }

  @override
  String assignPartOfSet(String name, int count) {
    return 'Fait partie de $name — $count titres dans l\'ensemble.';
  }

  @override
  String get assignSetTogetherTitle => 'Garder l\'ensemble complet ?';

  @override
  String assignSetTogetherBody(String title, String name) {
    return '$title fait partie de $name. Le reste de l\'ensemble peut suivre en même temps.';
  }

  @override
  String get assignSetTogetherJustThis => 'Seulement celui-ci';

  @override
  String assignSetTogetherAll(int count) {
    return 'Les $count';
  }

  @override
  String assignBatchPartial(int done, int total) {
    return '$done titres modifiés sur $total.';
  }

  @override
  String assignBatchSetIncomplete(int count) {
    return 'Les $count titres ont été modifiés, mais pas la collection elle-même.';
  }

  @override
  String assignBatchSetIncompleteAdded(int count) {
    return 'Les $count titres sont étiquetés, mais pas la collection elle-même. Les films sont là ; l\'ensemble ne l\'est pas.';
  }

  @override
  String assignBatchSetIncompleteRemoved(int count) {
    return 'Les étiquettes ont été retirées des $count titres, mais pas de la collection. Les films ne sont plus là ; l\'ensemble y est encore, et il paraîtra vide.';
  }

  @override
  String get assignBatchPutBack => 'Tout remettre';

  @override
  String get assignBatchFinish => 'Terminer le reste';

  @override
  String get assignBatchRemoveAll => 'Tout retirer';

  @override
  String assignBatchPreflightFailed(int count) {
    return 'Rien n\'a été modifié. $count titres de cet ensemble n\'ont pas pu être lus : Garfin a laissé l\'ensemble intact.';
  }

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsSectionServer => 'Serveur';

  @override
  String get settingsSectionLabels => 'Étiquettes';

  @override
  String get settingsSectionPicking => 'Choix';

  @override
  String get settingsSectionLooks => 'Apparence';

  @override
  String get settingsSectionAbout => 'À propos';

  @override
  String get settingsRefreshCache => 'Actualiser ce que Garfin a en mémoire';

  @override
  String get settingsRefreshCacheDone => 'Nouvelle interrogation du serveur';

  @override
  String get settingsCollectionPrompt =>
      'Quand un titre fait partie d\'une collection';

  @override
  String get settingsCollectionPromptAsk => 'Demander à chaque fois';

  @override
  String get settingsCollectionPromptAlways => 'Donner tout l\'ensemble';

  @override
  String get settingsCollectionPromptNever => 'Seulement le titre choisi';

  @override
  String get settingsRefreshAfterWrite =>
      'Actualiser le titre après l\'avoir étiqueté';

  @override
  String get settingsRefreshAfterWriteSubtitle =>
      'Plus lent. La modification apparaît tout de suite dans Jellyfin.';

  @override
  String get settingsStartingChild => 'Ouvrir la médiathèque sur';

  @override
  String get settingsStartingChildEveryone => 'Tout le monde';

  @override
  String get settingsHideShared => 'Masquer ce qu\'un enfant a déjà';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get settingsThemeSystem => 'Suivre le téléphone';

  @override
  String get settingsThemeLight => 'Clair';

  @override
  String get settingsThemeDark => 'Sombre';

  @override
  String get settingsDynamicColour => 'Utiliser les couleurs du téléphone';

  @override
  String get settingsPosterSize => 'Taille des affiches';

  @override
  String get settingsPosterLarge => 'Grandes';

  @override
  String get settingsPosterRegular => 'Normales';

  @override
  String get settingsPosterSmall => 'Petites';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsLicence =>
      'GPL-3.0-or-later. Garfin est un logiciel libre, fourni sans aucune garantie.';

  @override
  String get settingsNotAffiliated =>
      'Sans affiliation avec le projet Jellyfin. Jellyfin est une marque de Jellyfin, Inc.';

  @override
  String get settingsSource => 'Code source';

  @override
  String get settingsLicences => 'Licences des logiciels libres utilisés';

  @override
  String get assignSeriesNote =>
      'Tout ce que contient la série suit — saisons et épisodes compris.';

  @override
  String get filterAll => 'Filtres';

  @override
  String get filterReset => 'Réinitialiser';

  @override
  String get filterAny => 'Tous';

  @override
  String get filterType => 'Type';

  @override
  String get filterTypeMovie => 'Films';

  @override
  String get filterTypeSeries => 'Séries';

  @override
  String get filterTypeCollection => 'Collections';

  @override
  String get filterGenre => 'Genre';

  @override
  String get filterDecade => 'Décennie';

  @override
  String filterDecadeValue(int decade) {
    final intl.NumberFormat decadeNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String decadeString = decadeNumberFormat.format(decade);

    return 'Années $decadeString';
  }

  @override
  String filterWithinCap(String name) {
    return 'Dans la limite de $name';
  }

  @override
  String filterActiveCount(int count) {
    return '$count';
  }

  @override
  String get activityTitle => 'Activité';

  @override
  String get activityEmpty => 'Rien n\'a encore été donné.';

  @override
  String get activityScope =>
      'Voici ce que Garfin a fait depuis ce téléphone. Les modifications faites dans Jellyfin, ou depuis un autre téléphone, n\'y figurent pas.';

  @override
  String activityHandedTo(String name) {
    return 'Donné à $name';
  }

  @override
  String activityTakenFrom(String name) {
    return 'Retiré à $name';
  }

  @override
  String get activityJustNow => 'À l\'instant';

  @override
  String activityMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count minutes',
      one: 'il y a 1 minute',
    );
    return '$_temp0';
  }

  @override
  String activityHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count heures',
      one: 'il y a 1 heure',
    );
    return '$_temp0';
  }

  @override
  String activityDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count jours',
      one: 'Hier',
    );
    return '$_temp0';
  }

  @override
  String activityWhenCollection(String when, int count) {
    return '$when · $count titres';
  }

  @override
  String get activityUndoUnknown =>
      'Ce compte n\'a plus de sélection : Garfin ne peut pas savoir ce que défaire signifierait.';

  @override
  String get deviceSignInAction => 'Connecter un appareil';

  @override
  String deviceSignInTitle(String name) {
    return 'Connecter un appareil pour $name';
  }

  @override
  String get deviceSignInHow =>
      'Sur son appareil, ouvrez Jellyfin et choisissez Quick Connect. Saisissez ici les six chiffres affichés.';

  @override
  String get deviceSignInCodeLabel => 'Code à six chiffres';

  @override
  String get deviceSignInApprove => 'Approuver';

  @override
  String deviceSignInConfirmTitle(String name) {
    return 'Connecter $name ?';
  }

  @override
  String deviceSignInConfirmCode(String code) {
    return 'Code $code';
  }

  @override
  String deviceSignInUnverified(String name) {
    return 'Garfin ne peut pas vérifier de quel appareil vient ce code. N\'approuvez qu\'un code que vous venez de voir sur l\'écran de $name.';
  }

  @override
  String deviceSignInDone(Object name) {
    return '$name est connecté sur cet appareil.';
  }

  @override
  String get errorQuickConnectRefused =>
      'Le serveur a refusé ce code. S\'il a déjà servi, demandez-en un nouveau sur son appareil.';

  @override
  String get errorUnusableUserId =>
      'Garfin n\'a pas d\'identifiant utilisable pour cet enfant : rien n\'a été approuvé. Actualisez ce que Garfin a en mémoire, dans les Réglages, puis réessayez.';
}
