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
  String get assignCollectionNote =>
      'Les collections seront gérées plus tard : ceci étiquette la collection elle-même, pas les titres qu\'elle contient.';
}
