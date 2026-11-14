# Lot C — Préremplissage de pièces justificatives depuis un référentiel DLNUF (références MD)

**Date :** 2026-11-06
**Statut :** spec de conception validée dans ses principes, avant plan d'implémentation
**Remplace :** `2026-06-05-prefill-piece-justificative-referentiel-design.md` (mécanisme par
téléchargement de fichiers Baserow, abandonné — cf. §10)
**Contrat de référence :** `2026-11-06-contrat-referentiel-dlnuf.md` (marqueurs de table et de
colonne, format des références, responsabilités du robot)
**Devis :** `2026-07-21-devis-referentiel-dlnuf-cascade-prefill.md`, lot C

## 1. Objectif

Quand un usager sélectionne sa ligne dans un champ « Référentiel de Polynésie » branché sur un
référentiel **DLNUF**, les champs **pièce justificative** configurés dans le mapping sont
préremplis avec les pièces qu'il a déjà déposées dans un dossier précédent (statuts, PV d'AG,
RIB de l'association…), **sans re-téléversement**.

Principe retenu à l'atelier du 2026-06-22 : on mutualise la **saisie**, pas la **décision**. Une
pièce préremplie est une pièce ordinaire du nouveau dossier, instruite par le service destinataire
comme si l'usager l'avait téléversée ; elle ne transporte aucun visa ni statut de recevabilité.

## 2. Décisions verrouillées

1. **DLNUF seulement.** Préremplissage de PJ refusé pour un référentiel archive (catalogue), par
   défaut et sans option ; ouverture ultérieure seulement sur un cas d'usage prouvé (contrat §7).
2. **Référence, pas copie.** La cellule Baserow contient une référence `md:<numero>:<stable_id>[:<row_id>]`
   écrite par le robot ; MD **rattache le blob existant** du dossier source (même mécanisme que
   `ClonePiecesJustificativesService`).
3. **Synchrone.** Pas de job, pas de téléchargement, pas d'état d'attente : le rattachement se
   fait dans le flux de préremplissage existant.
4. **Pas de nouveau scan antivirus.** Le blob a déjà été analysé dans MD ; son
   `virus_scan_result` est conservé. Un blob infecté ou en erreur d'intégrité n'est jamais rattaché.
5. **Même titulaire.** MD vérifie que le dossier source appartient au titulaire du dossier cible,
   en plus du périmètre DLNUF (double contrôle, le second interne à MD).
6. **Idempotence.** Une nouvelle sélection remplace les pièces **préremplies** ; elle ne touche
   jamais une pièce ajoutée par l'usager.
7. **Échec silencieux et sûr.** Référence absente, morte, d'un autre titulaire, ou champ source
   non conforme ⇒ la pièce n'est pas préremplie, le reste du préremplissage continue, l'usager
   téléverse normalement.
8. **Pas d'affichage de PJ** depuis le référentiel (décision de juin, inchangée) : une colonne de
   référence n'est jamais *displayable* usager/instructeur.

## 3. Prérequis — PR 0 : détection DLNUF par marqueur

À livrer avant le lot C, en PR séparée (le DLNUF de la PR #530 lit aujourd'hui la colonne méta
« Champ propriétaire »).

### 3.1 Lecture du marqueur

- `ReferentielDePolynesie::BaserowAPI.dlnuf_config(domain_id)` lit d'abord le **marqueur de
  table** : description de la colonne `primary: true` dans `fields(config)` (déjà appelé, il faut
  seulement conserver `description` et `primary` dans le hash retourné).
- Analyse selon le contrat §3.2, dans un petit objet dédié et testé isolément
  (`ReferentielDePolynesie::Marqueur`, analyse des lignes `mes-demarches:`), réutilisé pour le
  marqueur de colonne (§4).
- Résultat inchangé pour les appelants : `nil` (catalogue), `:invalid` (refus), ou
  `{ field_id:, field_name:, field_type: }`. **Aucun appelant existant ne change.**
- Le hash gagne une clé `source: :marqueur | :table_meta` (diagnostic, logs).

### 3.2 Deux clés (contrat §3.3, §3.4)

Le marqueur **et** la colonne méta « Champ propriétaire » restent tous deux lus : une table est
DLNUF si l'un **ou** l'autre le déclare, catalogue seulement si aucun. La colonne méta n'est donc
pas un repli à retirer, c'est la seconde clé. Marqueur DLNUF et colonne méta renseignés avec des
identifiants différents ⇒ `:invalid` + log. Table méta indisponible (hors 404) ou colonnes
illisibles ⇒ `:invalid`.

Mesure en prod (2026-11-13) : une seule table déclarée DLNUF (référentiel 33, « DJS -
Associations/Fédérations Sport », table 861, « Champ propriétaire » 9115), aucune démarche
publiée ne l'utilise. Le marqueur y sera posé à la main.

### 3.3 Pas de mémorisation côté MD

Une mémorisation du mode dans MD (date de première observation en DLNUF, refus si le mode
disparaît) a été codée puis abandonnée au profit des deux clés : elle demandait un stockage dédié
pour être robuste (le jsonb du référentiel est remis à zéro quand l'éditeur change de table, et
elle était indexée sur la ligne méta alors que deux lignes méta peuvent désigner la même table
Baserow) et une tâche de remise à zéro. Les deux clés couvrent l'erreur d'un seul geste ; les
conditions d'exploitation du contrat §3.4 (projets distincts, accès administrateur seul, jetons en
lecture seule sur la table méta) couvrent les jetons et les accès métier.

### 3.4 Tests PR 0

Analyse du marqueur (cas nominaux, casse, espaces, clés inconnues, clé répétée, deux lignes,
variantes de préfixe, version inconnue) ; `dlnuf_config` : marqueur seul, méta seule, les deux
concordants / discordants, marqueur archive + méta renseignée (⇒ DLNUF par la méta), propriétaire
inexistant, table méta indisponible. Specs existantes du DLNUF (#530) vertes.

**Charge : ~0,5–1 j.**

## 4. Mapping : type « pièce justificative »

### 4.1 Détection de la colonne

Une colonne Baserow est une **colonne de référence de PJ** si et seulement si :

- la table est DLNUF (§3), **et**
- la description de la colonne porte `mes-demarches: reference=piece_justificative` (contrat §4.1).

MD ne devine jamais une référence d'après le contenu d'une cellule.

`BaserowAPI.baserow_type_to_mapping_type` reçoit les métadonnées complètes de la colonne
(description comprise) et renvoie le type de mapping **`piece_justificative`** pour une telle
colonne. Hors DLNUF, la même colonne reste `string` et n'est proposée pour aucune cible PJ.

### 4.2 Éditeur de mapping (web)

- `Referentiels::MappingFormComponent::TYPES` : ajout de `:piece_justificative`. Pour une colonne
  de référence, le type est **imposé** (pas de liste déroulante) ; il n'est jamais proposé pour une
  autre colonne.
- `Referentiels::ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP` :
  `piece_justificative => %w[piece_justificative]` (pas `titre_identite`).
- Cases « afficher à l'usager / à l'instructeur » **désactivées** pour ce type (décision 8).
- `Administrateurs::ReferentielsController` : rejet côté serveur d'un mapping `piece_justificative`
  sur un référentiel non DLNUF ou une colonne non marquée, et de toute option d'affichage sur ce
  type (ne pas se fier au seul formulaire).

### 4.3 MCP et GraphQL

- `Mcp::ReferentielMappingService` : la liste des colonnes expose `type_mapping: piece_justificative`
  ; `valider_cible!` n'accepte un champ PJ comme cible que pour ce type, et refuse
  `display_usager` / `display_instructeur`.
- Mutation `demarcheConfigurerReferentielMapping` : mêmes validations (elle délègue au service).
- Régénérer le schéma GraphQL si une description d'argument change.

## 5. Préremplissage

### 5.1 Point d'insertion

`Champs::ReferentielChamp#update_prefillable_champ` (`app/models/champs/referentiel_champ.rb`,
fichier upstream modifié **en place** avec un tag `# pf:`, pour que tout changement upstream de
cette méthode produise un conflit visible) :

```ruby
def update_prefillable_champ(type_de_champ:, raw_value:, row_id: nil)
  prefill_champ = dossier.champ_for_update(type_de_champ, row_id:, updated_by: :api)

  # pf: lot C — une PJ se rattache (référence MD), elle ne s'affecte pas
  if type_de_champ.type_champ == TypeDeChamp.type_champs.fetch(:piece_justificative)
    ReferentielDePolynesie::PrefillPieceJustificative.new(referentiel_champ: self, cible: prefill_champ, reference: raw_value).call
  else
    prefill_champ.update(cast_value_for_type_de_champ(raw_value, type_de_champ))
  end
end
```

Le flux reste celui d'aujourd'hui dans les deux modes :
- **autocomplete** : `data=` → `propagate_prefill` (inline, dans la requête de sélection) ;
- **exact_match** : `update_external_data!` → `propagate_prefill` (dans le job de récupération).

Le champ PJ cible est déjà dans `prefillable_champs`, donc dans `champs_to_turbo_update` : il est
re-rendu avec ses pièces sans mécanisme nouveau.

### 5.2 Service `ReferentielDePolynesie::PrefillPieceJustificative`

Étapes, chacune pouvant arrêter le traitement (retour sans effet + log `info`, sauf mention) :

1. **Garde DLNUF** : `dlnuf_config` du référentiel non nul et différent de `:invalid`, sinon arrêt.
   (Redondant avec l'éditeur — défense en profondeur.)
2. **Lecture de la référence** : `md:<numero>:<stable_id>[:<row_id>]` strict
   (`\Amd:(\d+):(\d+)(?::([A-Za-z0-9_-]+))?\z`). Vide ⇒ traité comme « pas de pièce » (étape 6
   avec liste vide). Illisible ⇒ arrêt.
3. **Dossier source** : `Dossier.visible_by_user.find_by(id: numero)` — exclut les dossiers cachés
   ou supprimés par l'usager. Doit être **déposé** (pas `brouillon`) et ≠ dossier cible.
4. **Même titulaire** : `source.user.email.casecmp?(cible.dossier.user.email)`. Échec ⇒ arrêt +
   `Sentry.capture_message` (signal de sécurité : référence forgée ou ligne mal attribuée).
5. **Champ source** : type de champ de `stable_id` dans la **révision du dossier source**, de type
   `piece_justificative` (pas `titre_identite`) ; champ lu sur le flux principal
   (`source.project_champ(type_de_champ, row_id:)`). Absent ⇒ liste vide.
6. **Idempotence** (§5.3), puis **rattachement** des blobs du champ source, en excluant ceux dont
   `virus_scan_result` est infecté ou en erreur d'intégrité :
   `cible.piece_justificative_file.attach(blob)` pour chacun.
7. `cible.update!(prefilled: true)` si au moins une pièce a été rattachée.

Limites de taille et types autorisés : déjà respectés par le blob source (mêmes validations
`PieceJustificativeChamp`), pas de contrôle supplémentaire.

### 5.3 Idempotence et drapeau `prefilled`

Constat (devpf, identique upstream) : `prefilled` est mis à vrai par les préremplissages et
**n'est jamais remis à faux** quand l'usager modifie le champ (seule exception : la
réinitialisation du SIRET). Pour une PJ, la règle « purger si `prefilled?` » purgerait donc un
fichier ajouté à la main après un préremplissage.

Règles :

- **Cible vide** ⇒ rattachement.
- **Cible `prefilled?`** ⇒ détacher les pièces existantes (`purge_later` : le blob partagé survit
  tant qu'un autre dossier le référence — vérifié, §7) puis rattacher.
- **Cible non vide et non `prefilled?`** ⇒ **ne rien faire**.
- **Ajout de fichier par l'usager** : `Champs::PieceJustificativeController#attach_piece_justificative` remet
  `prefilled` à faux après l'ajout (`# pf:`). Une sélection ultérieure ne touche alors plus le champ.
- **Suppression par l'usager de toutes les pièces** d'un champ prérempli : le champ redevient vide,
  donc préremplissable à la sélection suivante (comportement attendu).

### 5.4 Flux de brouillon et dépôt

- Dossier en `brouillon` : écriture sur le flux principal (cas nominal).
- Dossier en construction modifié par l'usager : `champ_for_update` écrit dans le flux de
  brouillon de l'usager (comportement existant, `with_champ_stream`) ; le rattachement suit ce
  champ, et la fusion au dépôt déplace l'enregistrement (mêmes identifiants).
- Le rattachement étant synchrone, **aucun dépôt ne peut intervenir pendant un préremplissage**
  (le problème de course de la spec de juin disparaît).

## 6. Sécurité

| Menace | Parade |
|---|---|
| Sélectionner la ligne d'un autre titulaire | Périmètre DLNUF existant (#530) : recherche filtrée côté serveur, contrôle au dépôt |
| Forger une référence vers le dossier d'autrui | Étape 4 : même titulaire vérifié dans MD, indépendamment de Baserow |
| Référentiel catalogue utilisé pour exfiltrer des pièces | Étape 1 + éditeur + contrôleur : PJ uniquement en DLNUF |
| Bascule silencieuse DLNUF → catalogue | Mémorisation (PR 0, §3.3) : refus |
| Pièce infectée propagée | Étape 6 : blobs infectés ou en erreur d'intégrité exclus |
| Titre d'identité réutilisé | Type `titre_identite` exclu en source comme en cible |
| Pièce d'un dossier supprimé par l'usager | Étape 3 : `visible_by_user` |

Aucun appel réseau, aucune URL externe manipulée : pas de surface SSRF.

## 7. Tests

**Unitaires (service)** : référence vide / illisible / dossier inexistant / caché par l'usager
(y compris un dossier **terminé**, que l'administration voit encore) / brouillon /
autre titulaire (+ message Sentry) / champ source absent / `titre_identite` / blob infecté exclu ;
rattachement de plusieurs fichiers ; `prefilled` posé ; idempotence (cible vide, préremplie,
remplie à la main).

**Blob partagé** (vérification déjà faite le 2026-11-06, à intégrer comme spec) : le blob survit à
`purge_discarded` du dossier source et au `purge_later` de la PJ source ; il est supprimé au
dernier rattachement.

**Éditeur / contrôleur / MCP** : type imposé sur colonne marquée ; aucune cible PJ hors DLNUF ;
rejet serveur d'un mapping PJ forgé ou d'une option d'affichage sur ce type.

**Contrôleur PJ** : `prefilled` remis à faux après ajout par l'usager.

**Système (Capybara, obligatoire — chaîne de déclenchement)** :
1. Autocomplete DLNUF : sélection de sa ligne → la PJ cible affiche les fichiers du dossier
   source, avec le message « Donnée remplie automatiquement. » ; l'usager peut en ajouter ou en
   retirer.
2. Ajout manuel puis nouvelle sélection → les fichiers ajoutés par l'usager sont conservés.
3. (si budget) exact_match : la PJ apparaît après la récupération asynchrone de la ligne.

Baserow stubbé (fields avec descriptions marquées, ligne contenant une référence).

## 8. Estimation

| Bloc | Charge |
|---|---|
| PR 0 — détection DLNUF par marqueur (deux clés) | ~0,5–1 j |
| Type de mapping `piece_justificative` (éditeur, contrôleur, MCP, GraphQL) | ~1 j |
| Service de préremplissage + branche + `prefilled` du contrôleur PJ | ~0,5–1 j |
| Tests (unitaires, blob partagé, système) | ~1 j |
| **Total côté MD** | **~3–4 j** (dont PR 0) |

À comparer aux ~4–5 j de la spec de juin, qui n'incluaient ni la PR 0 ni la détection par marqueur.

Côté inspecteur (hors de ce dépôt, cf. contrat §5) : choix archive / DLNUF et marqueurs au schema
builder ; références et refus des colonnes `file` dans la synchro ; effacement DLNUF (W2) avec
mémorisation du type.

## 9. Hors périmètre

- Préremplissage de PJ depuis un référentiel archive (source `fichier_baserow`) — contrat §7.
- Affichage de PJ issues du référentiel.
- Bloc répétable alimenté par un tableau de lignes Baserow (seul le cas « référentiel et PJ dans
  la même ligne de répétition » est couvert, via le chemin existant `update_sibling_prefillable_champs`).
- Le message « Donnée remplie automatiquement. » qui reste affiché après correction d'un champ
  simple par l'usager (comportement upstream).
- Sécurisation des fichiers stockés dans les référentiels archive : chantier d'infrastructure séparé.

## 10. Pourquoi la spec de juin est abandonnée

Elle prévoyait de télécharger une **copie** du fichier hébergée dans une colonne `file` Baserow
(job asynchrone, nouveau scan, état d'attente, gestion de 200 Mo). Deux prémisses sont tombées :

1. « La copie Baserow survit à la purge du dossier » : contredit par l'invariant décidé depuis
   (durée de vie d'une ligne DLNUF = durée de vie du dossier MD, effacement W2). La copie n'apporte
   plus de durabilité.
2. Une copie supplémentaire des pièces hors de MD n'est pas souhaitable (minimisation, contrôle
   d'accès) dès lors qu'elle n'est pas nécessaire.

Le mécanisme par référence supprime le téléchargement, le job, l'état d'attente, la course avec le
dépôt et toute surface réseau, pour une charge comparable malgré la PR 0.
