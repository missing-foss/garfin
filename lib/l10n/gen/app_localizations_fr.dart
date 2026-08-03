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
}
