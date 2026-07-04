# Filtres contextuels pour le champ ReferentielDePolynesie

Date : 2026-06-17
Statut : conception validée, prêt pour plan d'implémentation

## Problème

Le champ `referentiel_de_polynesie` cherche aujourd'hui dans Baserow sur **un seul**
critère : le terme `q` tapé par l'usager, en `contains` sur la colonne configurée
« Champ de recherche ». On veut **restreindre l'ensemble des lignes accessibles** en
fonction du **contexte du dossier**, comme **contrainte de sécurité** (pas seulement
un confort) :

- **Cas email** : ne montrer que les lignes Baserow qui appartiennent à l'usager
  (colonne email Baserow = email de l'usager connecté). Ce cas est en pratique un
  **préremplissage auto-clé** : « voici tes données issues de tes autres dossiers,
  synchronisées dans Baserow ». La clé (l'email) vient de la session, pas d'une saisie.
  Le nombre de lignes (0 / 1 / N) devient donc une variable d'UX (cf. « État vide »).
- **Cas cascade** : ne montrer que les lignes pertinentes par rapport à un autre champ
  du dossier (ex. l'usager a choisi un permis d'importation « Semences » → seules les
  lignes « Semences » sont sélectionnables, pas « Plants » ni « Fleurs »).

Les deux sont des **contraintes de sécurité** : l'usager ne doit ni *voir/sélectionner*,
ni *déposer* une ligne hors de son périmètre.

## Décision de cadrage

On réutilise l'abstraction **`Column`** existante (filtres de tableaux de dossiers)
plutôt que le champ formule :

- `Column` est déjà un **catalogue prêt pour une dropdown** (`form_filterable_columns`,
  `usager_filterable_columns`…), déjà filtré sur `filterable?`.
- Les créateurs de formulaire la connaissent déjà.
- `Column#value(dossier|champ)` **extrait déjà la valeur côté serveur**
  (`Columns::DossierColumn#value`, `Columns::ChampColumn#value`).
- Les valeurs dérivées existent déjà via `Columns::JSONPathColumn` (ex. « l'île d'une
  commune » si le `value_json` du champ commune la contient) — couvre le besoin
  « colonne du dossier » sans formule dans ~80 % des cas.
- Le champ formule reste la **soupape** pour les cas résiduels (multi-colonnes,
  dérivations complexes) : on dérive une valeur via formule côté dossier ET une colonne
  équivalente côté Baserow, puis on filtre sur cette paire.

L'email devient un **cas particulier sans code spécial** : règle
`{ colonne Baserow → Column(user/email) }`.

## Périmètre v1 (YAGNI)

- **Une seule règle de filtre par champ.** Le cas (rare) de plusieurs colonnes se
  résout exceptionnellement par une formule côté dossier + côté Baserow.
- **Colonnes source de type texte uniquement** : la dropdown B n'expose que les
  `Column` dont `type ∈ {:text, :enum, :enums}` (pas de date ni de nombre en v1).
- Pas de réinitialisation destructive (voir « Validation non-destructive »).

## Architecture

### 1. Configuration (sur le type de champ)

`TypesDeChamp::ReferentielDePolynesieTypeDeChamp`, via `store_accessor :options` :

```ruby
referentiel_filter: {
  baserow_column_id:,    # id stable de la colonne Baserow (survit au renommage)
  baserow_column_name:,  # nom en cache, pour affichage et pour lire row_data à la validation
  source_column_h_id:    # h_id d'une Column ({ procedure_id:, column_id: })
}
```

Pas de réglage « masquer si vide » : le comportement en périmètre vide est dérivé du
flag **obligatoire/optionnel** existant du champ (cf. « État vide »). On ne duplique pas
une décision que l'admin prend déjà.

Éditeur de formulaire = **deux dropdowns** :

- **Dropdown A — colonne Baserow** : alimentée par `BaserowAPI.fields(config)`
  (`{ id => { name:, type: } }`). Stockée par **id** (+ nom en cache).
- **Dropdown B — colonne du dossier** : `procedure.form_filterable_columns` +
  `email_column` + colonnes `individual`/`moral`, **filtrées sur
  `type.in?([:text, :enum, :enums])`**.
- **Diagnostic (garde-fou config)** : un aperçu côté éditeur signalant si la config
  produit des périmètres vides (« N valeurs/catégories renvoient 0 ligne »), pour qu'un
  mauvais mapping Baserow ne se traduise pas par un champ optionnel silencieusement
  toujours masqué.

### 2. Résolution & sécurité (cœur)

Endpoint `DataSources::ReferentielDePolynesieController#search`.

Aujourd'hui : reçoit `table` + `q`. On ajoute **`champ_id`** (le champ référentiel en
cours de saisie). Côté composant, on l'ajoute au `loader` :
`data_sources_rdp_search_path(table:, drop_down_other:, champ_id: @champ.id)`
(cf. `referentiel_de_polynesie_component.rb:22`).

Flux serveur :

1. `Champ.find(champ_id)` puis **autorisation** : `champ.dossier` doit appartenir à
   `current_user` (propriétaire ou invité autorisé) → sinon **403**. C'est la pièce de
   sécurité : la valeur source n'est JAMAIS lue depuis le client.
2. Lire la config `referentiel_filter` du type de champ.
3. Résoudre la valeur source :
   `Column.find(source_column_h_id).value(dossier_persisté | champ_source)`.
   Le dossier est relu **persisté** (l'autosave existant a déjà sauvegardé le champ
   source avant la recherche).
4. Injecter le filtre en `AND` dans `build_search_filters`, à côté du `contains` sur `q`.
   Opérateur Baserow selon le **type de la colonne Baserow** (via
   `baserow_type_to_mapping_type`) :
   - texte / `single_select` / email → `equal`
   - `multiple_select` / `link_row` → `has`
5. **Fail-closed** : valeur source vide (champ source non rempli) → **retour vide** +
   message « Renseignez d'abord *<libellé du champ source>* », jamais le référentiel
   complet.
6. Le filtre est **toujours** appliqué côté serveur ; `q` ne fait que réduire à
   l'intérieur du périmètre → la sécurité tient quel que soit le `q`.

Rétro-compatibilité : un champ sans `referentiel_filter` → comportement actuel
inchangé (pas de filtre, `champ_id` ignoré si absent).

### 3. État vide & rendu (non bloquant)

On ne fait **pas** d'appel Baserow bloquant à l'affichage du dossier. Le champ filtré
est résolu en **lazy** :

- rendu via Turbo frame `loading="lazy"` (ou fetch Stimulus au `connect`) : le dossier
  s'affiche immédiatement, le périmètre se résout hors du chemin critique ;
- résultat mis en **cache** par périmètre (`(table, valeur source résolue)`, ex.
  `(table, email)`), TTL court — les données de scoping bougent peu ;
- on distingue deux « vides » :
  - **Prérequis non rempli** (cascade, source encore vide → *pas de périmètre du tout*)
    → champ **visible** avec « Renseignez d'abord *<libellé source>* », quel que soit
    obligatoire/optionnel (fail-closed déjà décrit en §2.5).
  - **Périmètre résolu mais vide** (source = valeur concrète, 0 ligne ; ex. email sans
    données synchronisées, ou permis « Semences » sans semence en base) → comportement
    **dérivé du flag obligatoire** du champ :
    - **optionnel** → **masquer le champ** (« ça ne s'applique pas ici ») ;
    - **obligatoire** → **rester affiché** avec message « Aucun résultat pour *<valeur
      source>* » ; le caractère requis **bloque** naturellement le dépôt, forçant
      l'usager à reconsidérer le champ source.

Le diagnostic admin (voir éditeur) reste le garde-fou contre la mauvaise config : un
champ optionnel masqué silencieusement peut cacher une erreur de mapping Baserow.

Pas d'auto-remplissage quand une seule ligne existe en v1 (voir « hors périmètre »).

### 4. Validation non-destructive (anti-stale)

Problème : si l'usager change le champ source **après** avoir sélectionné des lignes
(ex. « Semences » → « Plants »), les sélections déjà faites deviennent hors périmètre.

**Choix : on ne réinitialise PAS.** Une réinitialisation destructive transformerait un
clic accidentel sur le champ source en perte de données (ex. 10 blocs répétables
contenant un champ référentiel, tous nettoyés). À la place :

- Validation au niveau du champ
  (`Champs::ReferentielDePolynesieChamp#validate` / `valid?`) : comparer **localement**
  `row_data[baserow_column_name]` (déjà stocké dans `champ.data` / `value_json`) à la
  valeur source résolue. Si différent → **erreur bloquante sur ce champ précis**.
  Message : « « Plants » ne correspond pas à « Semences ». Modifiez ce champ ou le type
  de produit. »
- **Aucun appel Baserow** au dépôt : la donnée de la ligne sélectionnée est déjà à plat
  dans le champ → comparaison locale, robuste même si Baserow est indisponible.
- Granularité par champ : dans une répétition, seuls les blocs fautifs sont signalés ;
  l'usager corrige/supprime ou revient changer le champ source.

Cas limite : si `baserow_column_name` n'est pas présent dans `row_data` (ligne legacy
sélectionnée avant l'ajout du filtre), on **n'invalide pas** (faute de donnée pour
comparer) — fail-open assumé uniquement pour les données antérieures à la config.

### Deux remparts de sécurité indépendants

1. **À la sélection** : `#search` filtré côté serveur (fail-closed) → impossible de
   *choisir* une ligne hors périmètre.
2. **Au dépôt** : validation locale → impossible de *déposer* une ligne hors périmètre
   (couvre le cas du champ source modifié après coup).

## Plan de test

Conformément à la préférence « tests système sur les chaînes de déclenchement » :

- **Système (Capybara)** :
  1. Cascade « type de produit → référentiel » : sélection « Semences » → l'autocomplete
     ne propose que des lignes « Semences » ; changer pour « Plants » ne nettoie PAS la
     sélection mais produit une erreur de validation au dépôt.
  2. Filtre email : un usager ne voit que ses propres lignes.
  3. État vide : champ **optionnel** à périmètre vide → masqué ; champ **obligatoire**
     à périmètre vide → affiché + message « Aucun résultat » + dépôt bloqué. Cascade
     source vide → message « Renseignez d'abord X » (champ visible, quel que soit le flag).
- **Sécurité (request/controller)** :
  - Trafiquer `champ_id` vers un dossier d'autrui → **403**.
  - Champ source vide → **retour vide** (fail-closed), pas le référentiel complet.
  - `q` libre ne permet pas d'atteindre une ligne hors périmètre.
- **Unitaires** :
  - Résolution `Column#value` pour `user/email`, un champ dropdown, une JSONPathColumn.
  - Choix de l'opérateur Baserow selon le type de colonne.
  - Validation locale `row_data[col] == source` (match / mismatch / colonne absente).
  - Filtrage du catalogue dropdown B sur `type ∈ {text, enum, enums}`.

## Fichiers concernés (indicatif)

- `app/models/types_de_champ/referentiel_de_polynesie_type_de_champ.rb` — config
  `referentiel_filter`, catalogue colonnes (A via BaserowAPI, B via Column filtrées).
- `app/models/champs/referentiel_de_polynesie_champ.rb` — validation non-destructive.
- `app/controllers/data_sources/referentiel_de_polynesie_controller.rb` — `champ_id`,
  autorisation, résolution source, fail-closed.
- `app/lib/referentiel_de_polynesie/baserow_api.rb` — extension de
  `build_search_filters` pour le filtre contextuel + opérateur par type.
- `app/components/editable_champ/referentiel_de_polynesie_component.rb` — `champ_id`
  dans le `loader` ; rendu lazy (Turbo frame) + état vide / `hide_if_empty`.
- Endpoint de résolution lazy du périmètre (count/présence) — Turbo frame ou action
  dédiée, mis en cache par `(table, valeur source)`.
- Vue/éditeur du type de champ (admin) — les deux dropdowns A et B.
- `config/routes.rb` — la route accepte déjà `:table` ; `champ_id` passe en query param.

## Points hors périmètre (notés pour plus tard)

- Multi-règles de filtre (résolu par formule en v1).
- Colonnes source non-texte (date, nombre).
- Mode `exact_match` (saisie + job asynchrone) : **hors périmètre v1**, aucun use case
  identifié. La v1 cible exclusivement l'autocomplete inline.
- Auto-remplissage quand le périmètre ne contient qu'une seule ligne (v1.1 possible
  pour le cas prefill-email).
