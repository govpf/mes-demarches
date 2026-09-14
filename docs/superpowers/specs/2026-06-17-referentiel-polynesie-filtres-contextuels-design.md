# Filtres contextuels (cascade) pour le champ ReferentielDePolynesie

Date : 2026-06-17, révisée le 2026-09-14
Statut : conception validée (lot A du devis), prête pour plan d'implémentation

> **Ce qui a changé le 2026-09-14.** Le Socle et le lot B du devis
> (`2026-07-21-devis-referentiel-dlnuf-cascade-prefill.md`) ont été livrés par la
> PR #530. Cette révision retire de la spec ce que le Socle a déjà posé, acte les
> écarts d'implémentation, et tranche trois points restés ouverts :
> état vide **jamais masqué** pour la cascade, pilote **hors bloc ou dans la même
> ligne** d'un bloc répétable, cas de référence **permis d'importation
> (Semences / Plants)**. Le cas « email » de la version initiale est devenu le mode
> « Dites-le-nous une fois » (DLNUF), intrinsèque à la table Baserow : il n'est plus
> traité ici.

## Problème

Le champ `referentiel_de_polynesie` propose à l'usager des lignes d'une table Baserow,
cherchées en `contains` sur la colonne « Champ de recherche » de la table méta. On veut
**restreindre l'ensemble des lignes accessibles** selon la valeur d'un **autre champ du
dossier** : l'usager choisit un type de produit « Semences » dans une liste déroulante,
et le champ « Produit » ne lui propose que des semences, pas des plants ni des fleurs.

C'est une **contrainte de sécurité**, pas seulement un confort : l'usager ne doit ni
*sélectionner* ni *déposer* une ligne hors de son périmètre.

## Décisions de cadrage

- **Réutiliser l'abstraction `Column`** (colonnes des tableaux de dossiers) plutôt que
  le champ formule pour désigner le champ pilote : catalogue déjà prêt pour une liste
  déroulante, valeur extraite côté serveur par `Column#value`, valeurs dérivées
  couvertes par `Columns::JSONPathColumn` (ex. l'île d'une commune). Le champ formule
  reste la soupape pour les cas résiduels (dériver une valeur côté dossier et une
  colonne équivalente côté Baserow).
- **Le filtrage n'est pas la norme.** Un champ sans filtre garde exactement le
  comportement actuel, sans surcoût à l'affichage. La configuration est cachée
  derrière une case à cocher décochée par défaut.
- **Jamais masquer le champ filtré.** Une erreur de mapping Baserow doit rester
  visible. Le masquage à périmètre vide reste réservé au mode DLNUF, où la clé vient
  de la session et non d'un choix explicite de l'usager.
- **Suppression du pilote : même régime que les conditions et les formules.** La
  suppression, le déplacement ou le changement de type du pilote sont autorisés ; un
  validateur de procédure signale l'erreur dans l'éditeur et bloque la publication
  jusqu'à correction. On ne refuse pas la suppression comme le fait le routage.

## Périmètre v1 (YAGNI)

- **Une seule règle de filtre par champ.**
- **Pilotes de type texte ou choix** : `Column#type ∈ {:text, :enum, :enums}`. Pas de
  date ni de nombre.
- **Emplacement du pilote** : champ de niveau racine placé avant le référentiel, ou
  champ frère placé avant lui dans la **même ligne** du bloc répétable. Un pilote situé
  dans un autre bloc est exclu (sémantique ambiguë : quelle ligne ?).
- **Pas de réinitialisation destructive** (voir « Validation non-destructive »).
- **Pas de diagnostic admin** « N valeurs renvoient 0 ligne » : il compensait le masquage
  silencieux, écarté.
- **Mode `exact_match`** (saisie libre + job asynchrone) : hors périmètre, aucun cas
  identifié. La v1 cible l'autocomplete inline.

## Architecture

### 1. Configuration (sur le type de champ)

`TypeDeChamp`, via `store_accessor :options`, clé réservée au type
`referentiel_de_polynesie` :

```ruby
referentiel_filter: {
  'baserow_field_id'   => 123,          # id stable de la colonne Baserow (survit au renommage)
  'baserow_field_name' => 'Catégorie',  # nom en cache : affichage + lecture de row_data à la validation
  'pilot_column_id'    => 'type_de_champ/456'   # Column#column_id ; la procédure est celle du TDC
}
```

Écart par rapport à la version initiale : on stocke le `column_id` seul, pas le `h_id`
complet (`procedure_id` redondant, et les options sont copiées d'une révision à
l'autre au sein de la même procédure). La `Column` se retrouve par
`procedure.find_column(h_id: { procedure_id:, column_id: })`.

**Éditeur de formulaire** (`TypesDeChampEditor::ChampComponent`, bloc du référentiel de
Polynésie, sous la case « option autre ») :

- Case à cocher **« Restreindre les lignes proposées selon un autre champ du
  formulaire »**, décochée par défaut. Bascule Stimulus : les deux listes ci-dessous
  n'apparaissent que cochée. Décocher puis enregistrer **efface** `referentiel_filter`.
- **Liste A — colonne Baserow** : alimentée par `BaserowAPI.fields(config)`, limitée aux
  types `text`, `long_text`, `email`, `formula`, `single_select`, `multiple_select`
  (pas de `link_row` en v1). Stockée par id, nom en cache. Si Baserow est injoignable, la liste affiche
  la valeur en cache et un message « Colonnes indisponibles pour le moment ».
- **Liste B — champ pilote** : les `Column` de la procédure de type `text`, `enum` ou
  `enums`, restreintes aux coordonnées **supérieures** admissibles : coordonnées racine
  précédant le référentiel (ou précédant son bloc), et frères précédents dans la même
  répétition. Même logique que `coordinate.upper_coordinates` utilisée par les
  conditions, filtrée sur le type et l'emplacement.

Le contrôleur `Administrateurs::TypesDeChampController#type_de_champ_update_params`
autorise `referentiel_filter: [:enabled, :baserow_field_id, :pilot_column_id]` ; le
nom Baserow est résolu et mis en cache côté serveur à l'enregistrement.

### 2. Validation de la configuration (éditeur et publication)

Nouveau validateur `TypesDeChamp::ReferentielFilterValidator`, enregistré sur
`draft_types_de_champ_public` et `draft_types_de_champ_private` avec les contextes
`types_de_champ_*_editor` et `publication`, sur le modèle exact de
`TypesDeChamp::ConditionValidator`. Pour chaque TDC porteur d'un `referentiel_filter`,
il vérifie que le pilote :

- existe encore dans la révision brouillon ;
- est **avant** le référentiel, à la racine ou dans la même ligne du même bloc ;
- est toujours d'un type filtrable (`text`, `enum`, `enums`).

Sinon : `procedure.errors.add(collection, …, type_de_champ: tdc)` avec le message
« Le filtre de « Produit » référence un champ supprimé, déplacé ou d'un type
incompatible ». L'erreur apparaît dans `Procedure::ErrorsSummary` en tête de l'éditeur et
sur le champ, et **bloque la publication**. La colonne Baserow n'est pas vérifiée à la
publication (dépendance réseau) : elle est vérifiée à l'enregistrement de la config et
gérée en fail-closed à l'exécution (§3).

Les dossiers en cours ne sont jamais affectés : ils restent sur la révision publiée,
figée.

### 3. Résolution et sécurité (cœur)

Endpoint `DataSources::ReferentielDePolynesieController#search`. Le Socle transmet déjà
`dossier_id` et applique l'autorisation `policy_scope(Dossier)` + garde preview (403). On
ajoute deux paramètres :

- **`stable_id`** du champ référentiel en cours de saisie ;
- **`row_id`** de sa ligne quand il est dans un bloc répétable (absent sinon).

Flux serveur, après `authorized_dossier` :

1. Retrouver le TDC par `stable_id` dans `dossier.revision` ; il doit être un
   `referentiel_de_polynesie` **et** porter la `table` demandée, sinon 400. Sans
   `referentiel_filter` → comportement actuel inchangé.
2. Retrouver la `Column` pilote (`procedure.find_column`). Si elle n'existe plus ou si
   son TDC n'est pas dans la révision du dossier → **liste vide + `Sentry.capture_message`**
   (« ReferentielDePolynesie: filtre contextuel invalide »). Jamais la table entière.
3. Résoudre la valeur du pilote **côté serveur** : `column.value(dossier)` pour une
   colonne dossier, `column.value(dossier.project_champ(pilot_tdc, row_id: pilot_row_id))`
   pour un champ, où `pilot_row_id` vaut `row_id` si le pilote est dans le même bloc,
   `nil` sinon. Le dossier est relu persisté : l'autosave a déjà enregistré le pilote.
4. **Fail-closed** : valeur vide → liste vide.
5. Sinon, ajouter un filtre à la liste des filtres de `BaserowAPI.search_with_data`. Le
   paramètre `scope:` du Socle devient **`scopes:`**, une liste, pour cumuler cascade et
   DLNUF sur un même champ. Opérateur selon le type Baserow de la colonne :
   - `text`, `long_text`, `email`, `formula` → `equal` sur la valeur ;
   - `single_select` → `single_select_equal` sur l'**id de l'option** dont le libellé
     égale la valeur (options lues dans les métadonnées `fields`, `select_options`) ;
     aucune option ne correspond → liste vide ;
   - `multiple_select` → `multiple_select_has` sur l'id de l'option, même résolution.
   On n'utilise pas `contains` : « Plants » attraperait « Plants aromatiques ».
6. Le filtre est **toujours** appliqué ; `q` ne fait que réduire à l'intérieur du
   périmètre. Comme un périmètre de cascade est petit, `q` vide est accepté quand un
   filtre est configuré (le composant passe `minimumInputLength: 0`, liste au focus,
   même ergonomie que le DLNUF).

### 4. État vide et rafraîchissement (composant)

`EditableChamp::ReferentielDePolynesieComponent`, quand le TDC porte un
`referentiel_filter` :

- `loader` reçoit `stable_id` et `row_id` ; `minimumInputLength: 0`.
- **Jamais `hideWhenEmpty`**, quel que soit le flag obligatoire.
- `emptyLabel` calculé **au rendu** côté serveur, deux cas :
  - pilote vide → « Renseignez d'abord « Type de produit » » ;
  - pilote renseigné → « Aucun résultat pour « Plants » ».
  Le libellé du pilote vient de la `Column`, sa valeur de `Column#value` sur le dossier
  courant (même résolution que §3, factorisée dans un service
  `ReferentielDePolynesie::ContextualFilter` utilisé par le contrôleur, le composant et
  la validation).
- **Rafraîchissement quand le pilote change** : `TurboChampsConcern#champs_to_turbo_update`
  ajoute aux champs re-rendus les référentiels dont le pilote vient d'être modifié
  (`Champ#dependent_referentiel_filter_champs`, symétrique de
  `all_dependent_formula_champs` ; dans un bloc, seuls les référentiels de la même ligne).
  Le composant se re-rend donc avec le bon `emptyLabel`, et la liste au focus repart du
  nouveau périmètre.

### 5. Validation non-destructive au dépôt (anti-stale)

Si l'usager change le pilote **après** avoir sélectionné une ligne (« Semences » →
« Plants »), on **ne réinitialise pas** : un clic accidentel ne doit pas vider dix blocs
répétables. À la place, `Champs::ReferentielDePolynesieChamp` valide, sur le modèle de
`dlnuf_owner_integrity` existant :

- comparaison **locale** de `normalized_data[baserow_field_name]` avec la valeur du
  pilote résolue (insensible à la casse ; pour `multiple_select`, appartenance à la
  liste) ; **aucun appel Baserow** au dépôt ;
- divergence → erreur bloquante sur ce champ, message
  « « Plants » ne correspond pas à « Semences ». Modifiez ce champ ou « Type de
  produit ». » ;
- colonne absente de `normalized_data` (ligne choisie avant la config) → on
  n'invalide pas, fail-open assumé pour l'antériorité ;
- pilote vide au dépôt → erreur « Renseignez d'abord « Type de produit » » si le
  référentiel est renseigné.

Dans une répétition, seuls les blocs fautifs sont signalés.

### Deux remparts indépendants

1. **À la sélection** : `#search` filtré côté serveur, fail-closed.
2. **Au dépôt** : validation locale, couvre le pilote modifié après coup et toute
   soumission forgée.

## Plan de test

Cas de référence : **permis d'importation**, pilote « Type de produit » (liste
déroulante Semences / Plants), référentiel « Produit » sur une table Baserow avec une
colonne « Catégorie » de type `single_select`.

- **Système (Playwright headless, `spec/system/users/referentiel_cascade_spec.rb`)** :
  1. Choisir « Semences » → le champ « Produit » liste au focus uniquement des semences ;
     passer à « Plants » ne vide pas la sélection, le message d'état vide se met à jour,
     et le dépôt est bloqué avec le message de divergence ; corriger débloque.
  2. Pilote vide → champ visible, « Renseignez d'abord « Type de produit » », liste vide.
  3. Référentiel dans un bloc répétable piloté par un frère de la même ligne : deux
     lignes avec deux catégories différentes obtiennent deux périmètres différents.
- **Requête (`spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`)** :
  - `stable_id` d'un champ dont le dossier n'est pas accessible → 403 (garde existante) ;
  - `stable_id` ne portant pas la `table` demandée → 400 ;
  - pilote vide → `[]` ;
  - pilote renseigné → le filtre `single_select_equal` avec l'id d'option est présent
    dans la requête Baserow (WebMock), quel que soit `q` ;
  - config invalide (pilote disparu) → `[]` + Sentry.
- **Éditeur (`spec/validators/types_de_champ/referentiel_filter_validator_spec.rb`,
  `spec/controllers/administrateurs/types_de_champ_controller_spec.rb`)** :
  - pilote supprimé, déplacé après, sorti du bloc, changé de type → erreur de
    publication avec le libellé du référentiel ;
  - décocher la case efface la config ; cocher sans choisir les deux listes ne sauve rien.
- **Unitaires** :
  - catalogue des pilotes admissibles (racine avant, même ligne avant ; exclus : après,
    autre bloc, type date) ;
  - opérateur et valeur par type Baserow (`equal`, `single_select_equal` avec résolution
    d'option, option introuvable → vide) ;
  - `scopes:` cumulant DLNUF et cascade ;
  - validation locale (égal, différent, colonne absente, multiple_select) ;
  - `dependent_referentiel_filter_champs` (racine, même ligne, pas l'autre ligne).

## Fichiers concernés (indicatif)

- `app/models/type_de_champ.rb` — `store_accessor :referentiel_filter`, ajout à
  `OPTS_BY_TYPE[:referentiel_de_polynesie]`.
- `app/models/types_de_champ/referentiel_de_polynesie_type_de_champ.rb` — accès typé à la
  config, catalogue des pilotes admissibles.
- `app/lib/referentiel_de_polynesie/contextual_filter.rb` — **nouveau** : résolution du
  pilote (Column, champ projeté par ligne), libellé et valeur, construction du filtre
  Baserow (opérateur + résolution d'option).
- `app/lib/referentiel_de_polynesie/baserow_api.rb` — `scopes:` (liste),
  `select_options` dans `fields`, nouveaux types de filtre.
- `app/controllers/data_sources/referentiel_de_polynesie_controller.rb` — `stable_id`,
  `row_id`, garde table/TDC, fail-closed + Sentry.
- `app/models/champs/referentiel_de_polynesie_champ.rb` — validation anti-stale.
- `app/models/champ.rb` — `dependent_referentiel_filter_champs`.
- `app/controllers/concerns/turbo_champs_concern.rb` — re-rendu des dépendants.
- `app/components/editable_champ/referentiel_de_polynesie_component.rb` — `stable_id`,
  `row_id`, `minimumInputLength: 0`, `emptyLabel` à deux cas, pas de `hideWhenEmpty`.
- `app/validators/types_de_champ/referentiel_filter_validator.rb` — **nouveau** ;
  enregistrement dans `app/models/procedure.rb`.
- `app/components/types_de_champ_editor/champ_component/champ_component.html.haml` et
  `champ_component.rb` — case à cocher, listes A et B ; contrôleur Stimulus de bascule.
- `app/controllers/administrateurs/types_de_champ_controller.rb` — paramètres autorisés,
  résolution du nom Baserow.
- `config/locales/…` — messages usager (fr/en), message de validation, libellés admin.

## Points hors périmètre (notés pour plus tard)

- Multi-règles de filtre (résolu par formule en v1).
- Pilotes non-texte (date, nombre) ; pilote dans un autre bloc répétable.
- Colonnes Baserow `link_row` comme colonne filtrée (résolution par table liée).
- Mode `exact_match`.
- Diagnostic admin des périmètres vides.
- Appliquer la même cascade au champ `referentiel` upstream (API génériques).
