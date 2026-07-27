# Afficher le provider d'identité sur la page profil

**Date** : 2026-07-19
**Périmètre** : page `/profil` usager uniquement

## Problème

Sur la page « Mon profil » (`app/views/users/profil/show.html.haml`), la carte
« Identités » liste les identités externes liées au compte
(`@france_connect_informations`) sous la forme :

```
Jean Dupont (jean@mail.pf)   [Effacer l'accès]
```

Aucune indication du **fournisseur d'identité** (FranceConnect, Tātou, Microsoft,
Google…). L'usager ne sait pas *via quel provider* chaque identité a été liée. En
PF où plusieurs providers coexistent (Tātou = « Polynésie Connect », Microsoft,
Google, FranceConnect quasi inexistant), cette information est utile.

## État des lieux technique

### Le provider n'est pas persisté sur l'identité

`FranceConnectInformation` (FCI) est le modèle générique d'identité externe,
utilisé aussi bien par FranceConnect que par tous les providers OmniAuth
(`OmniAuthService::PROVIDERS = google, microsoft, yahoo, sipf, tatou`).

À la création (`OmniAuthService#retrieve_user_informations` et
`FranceConnectService#retrieve_user_informations`), on ne stocke que :
`france_connect_particulier_id` (le `sub`), `given_name`, `family_name`,
`email_france_connect`, `birthdate`, `birthplace`, `gender`. **Aucun provider.**

### La colonne `data` (jsonb) est libre

`france_connect_informations.data` (jsonb) existe (migration
`20210412092710`) mais **n'est écrite nulle part** dans le code. Elle peut
accueillir le provider sans migration.

### Une colonne provider existe déjà… mais au niveau User, insuffisante ici

`users.loged_in_with_france_connect` est un `enum` string qui stocke le provider
de la **dernière connexion** :

```ruby
enum :loged_in_with_france_connect, {
  particulier: 'particulier', entreprise: 'entreprise', sipf: 'sipf',
  facebook: 'facebook', google: 'google', microsoft: 'microsoft',
  yahoo: 'yahoo', tatou: 'tatou',
}
```

Renseignée au login (`omniauth_controller.rb:244`,
`france_connect_controller.rb:245`), déjà utilisée pour l'affichage côté
instructeur (`dossier_helper.rb:239`, `dossier.rb:1085`, ticket DEM-215).

**Inadaptée à la page profil** pour deux raisons structurelles :
1. C'est un marqueur au niveau `User` (une seule valeur = dernière connexion),
   alors que la carte profil liste *potentiellement plusieurs* identités.
2. Elle est remise à `nil` à la déconnexion et à chaque connexion par mot de
   passe (`sessions_controller.rb:22` et `:65`).

→ Pour étiqueter **chaque identité de façon stable**, la donnée juste est
**par-FCI**.

### Libellés d'affichage déjà présents

`config/locales/fr.yml:1160` `omniauth.provider.*` :
`particulier: FranceConnect`, `facebook`, `google`, `microsoft: Microsoft 365`,
`tatou: Tātou`. Ces libellés couvrent l'intégralité des providers restants une
fois `yahoo`/`sipf` supprimés (voir spec de nettoyage
`2026-07-20-suppression-providers-yahoo-sipf-design.md`, chantier séparé). Aucun
libellé à ajouter pour cette feature.

## Solution retenue

Stocker le provider **par-FCI** dans la colonne `data` (jsonb), sans migration,
et l'afficher sous forme de badge DSFR sur la page profil.

### 1. Modèle — `app/models/france_connect_information.rb`

```ruby
store_accessor :data, :provider
```

Valeurs = celles de l'enum `User.loged_in_with_france_connect` restantes après le
nettoyage yahoo/sipf : `particulier`, `google`, `microsoft`, `tatou`.

### 2. Écriture du provider à la création

- **OmniAuth** — `OmniAuthService#retrieve_user_informations` reçoit déjà
  `provider` : le poser sur la FCI construite (`provider:` dans le `new`, ou
  `fci.provider = provider`).
- **FranceConnect** — `FranceConnectService#retrieve_user_informations` : provider
  toujours `'particulier'`.

### 3. Auto-réparation des identités existantes (à la reconnexion)

Les anciennes lignes n'ont pas de `data.provider`. Dans les chemins de
récupération d'une FCI existante :
- `OmniAuthService.find_or_retrieve_user_informations`
- `FranceConnectService.find_or_retrieve_france_connect_information`

si la FCI retrouvée n'a pas de provider, le renseigner (et persister) au passage.
→ Les comptes se corrigent seuls au fil des reconnexions, sans backfill hasardeux.

### 4. Affichage — `app/views/users/profil/show.html.haml`

Dans la boucle `@france_connect_informations.each do |fci|`, préfixer chaque
identité d'un badge DSFR :

```haml
- if fci.provider.present?
  %span.fr-badge.fr-badge--info.fr-badge--no-icon= t("omniauth.provider.#{fci.provider}")
```

- Libellé via `t("omniauth.provider.#{fci.provider}")` (clés existantes).
- **Fallback** : si `fci.provider` est nil (ancienne ligne pas encore
  reconnectée) → **pas de badge**, affichage actuel inchangé.

### 5. i18n

Rien à ajouter : les libellés `omniauth.provider.{particulier,google,microsoft,tatou}`
existent déjà et couvrent tous les providers restants.

## Sécurité

Le provider stocké est **purement décoratif**. Aucune décision de confiance ou de
fusion ne s'appuie dessus — celles-ci restent fondées sur
`trusted_email_assertion` / `OmniAuthService::STRONG_IDENTITY_PROVIDERS`. Ne pas
introduire de logique d'autorisation basée sur `data.provider`.

## Tests

- **Modèle** : `store_accessor` provider lit/écrit bien dans `data`.
- **Service OmniAuth** : provider persisté à la création ; backfill d'une FCI
  existante sans provider lors de `find_or_retrieve_user_informations`.
- **Service FranceConnect** : provider `'particulier'` à la création ; backfill
  équivalent.
- **Système (profil)** : badge affiché avec le bon libellé pour une identité
  ayant un provider ; badge absent quand `provider` est nil.

## Hors périmètre (YAGNI)

- Emails de confirmation / fusion (prennent déjà un `provider_type`).
- Page de fusion de comptes, logs de connexion.
- Backfill de masse des anciennes lignes (on s'appuie sur l'auto-réparation).
- Toute logique d'autorisation basée sur le provider.
