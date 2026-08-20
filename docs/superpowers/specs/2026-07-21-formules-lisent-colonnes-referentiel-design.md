# Design — Les formules lisent les colonnes d'un référentiel

- **Date** : 2026-07-21
- **Branche** : `feature/formules-lisent-colonnes-referentiel`
- **Statut** : design validé (sections 1→4), en attente de relecture avant plan d'implémentation

## Contexte & problème

Cas d'usage déclencheur (« Barème CATANAT ») : un formulaire avec des **blocs répétables**
où, dans chaque ligne, l'usager choisit une catégorie (nature de culture / type d'animal /
type d'équipement) via un champ `referentiel_de_polynesie` pointant sur une table Baserow.
La sélection doit rendre disponibles des valeurs de barème (`taux_unité`, `taux_bio`,
`plafond_catégorie`) **non modifiables par l'usager**, qu'une **formule de ligne** combine :
`quantité × taux × facteur_bio`, capée au plafond.

État actuel du code :

1. Un TDC `referentiel` / `referentiel_de_polynesie` n'expose qu'**une seule colonne scalaire**
   (`Columns::ChampColumn` = la valeur sélectionnée / `external_id`), via `TypeDeChampBase#columns`
   (`app/models/types_de_champ/type_de_champ_base.rb:110`). Aucune colonne par colonne de
   référentiel n'est exposée → le resolver de formule ne peut rien indexer.
2. Le commentaire dans `Champs::ReferentielChamp#update_external_data!`
   (`app/models/champs/referentiel_champ.rb`) confirme : *« À ce jour les formules ne lisent
   pas encore les colonnes des référentiels mais on prépare le terrain pour les évolutions
   futures. »*
3. Le seul moyen actuel d'alimenter une formule depuis un référentiel est le **prefill** : le
   mapping recopie une colonne dans un **champ sibling** éditable (`propagate_prefill` →
   `update_prefillable_champ`, `referentiel_champ.rb:236`). Deux défauts pour ce besoin :
   - le champ sibling est **éditable** par l'usager (contraire à l'exigence « non modifiable ») ;
   - le prefill fait un `update` ActiveRecord direct qui **ne déclenche aucune cascade de
     formule** ; seul `refresh_formulas_after(rdp_champ)` (amorcé sur le `stable_id` du RDP)
     tourne, si bien qu'une formule dépendant du **sibling prérempli** n'est pas dans
     l'ensemble recalculé → l'estimation ne se met pas à jour en temps réel.

**Décision** : permettre à une formule de lire directement une colonne du référentiel. Cela
supprime le champ sibling (donc l'éditabilité indue) et, comme la formule dépend alors du
`stable_id` du RDP, **la cascade temps réel existante suffit** (voir §2).

## Périmètre

**Inclus** :
- Une **formule-ligne** (dans un bloc répétable) lit une colonne d'un RDP situé dans la
  **même ligne** de ce bloc.
- Une **formule root** (hors répétition) lit une colonne d'un RDP **root**.
- Les colonnes du référentiel deviennent de **vraies `Columns::`** consommées **partout** :
  moteur de formule (objectif principal), **filtres**, **exports v2**, **colonnes de tableau
  instructeur** — comme le font déjà DN / commune / SIRET via `Columns::JSONPathColumn`.
  Objectif : rendre le référentiel « comme les autres champs à sous-colonnes », pas un cas
  spécial cantonné à la formule.

**Ordre d'implémentation (dé-risquage)** : livrer d'abord la lecture en **formule** (besoin
réel, surface restreinte), puis brancher **filtres / exports / tableau instructeur** dans un
second temps, avec leurs propres tests de non-régression d'affichage instructeur.

**Exclus (parqués, spec séparée)** :
- Les **agrégats** sur une colonne de référentiel de toutes les lignes d'un bloc (ex. SOMME
  des plafonds). Réutiliserait `RepetitionSubChampRef` mais rouvre le terrain « formule-ligne
  matérialisée » identifié comme fragile (cf. `project_formule_ligne_repetition_materialization`,
  refonte « passe accumulante » `docs/superpowers/specs/2026-05-28-formule-passe-accumultante-design.md`).
- Le support de ce mapping via le **configurateur MCP** (`Mcp::ReferentielMappingService` refuse
  déjà un RDP imbriqué en répétition — reste à configurer dans l'éditeur web).

## Design

### 1. Mécanisme cœur — exposer les colonnes du référentiel

**Constat d'architecture (hiérarchie de classes)** :

- **Niveau champ** (lecture des valeurs) : `Champs::ReferentielDePolynesieChamp <
  Champs::ReferentielChamp < Champ`. Le RDP hérite donc **par construction** de la machinerie
  `value_json` / mapping / `cast_displayable_values`. Toute lecture basée sur `champ.value_json`
  fonctionne pour les **deux** champs sans effort.
- **Niveau type de champ** (exposition des colonnes) : `TypesDeChamp::ReferentielTypeDeChamp` et
  `TypesDeChamp::ReferentielDePolynesieTypeDeChamp` héritent aujourd'hui **tous deux directement**
  de `TypeDeChampBase` → ce sont des **frères**, pas parent/enfant. Asymétrie avec le niveau champ
  (dette historique : le RDP est né du `table_row_selector` PF, antérieur au référentiel upstream ;
  la logique `paths` dérivée du mapping ne vit d'ailleurs que dans la classe PF).

**Décision** — **corriger l'héritage** : `ReferentielDePolynesieTypeDeChamp <
ReferentielTypeDeChamp` (miroir du niveau champ), **et** placer la dérivation `columns` dans un
**concern PF `TypesDeChamp::ReferentielColumnsConcern` inclus par le parent
`ReferentielTypeDeChamp`** (le RDP en hérite gratuitement).

Rationale du changement d'héritage (vérifié) :
- **Aucun dispatch sur la classe** dans `app/`/`lib/` (`is_a?`/`instance_of?`/`class ==`) → aucune
  casse.
- La résolution du `dynamic_type` est **par nom** (`"TypesDeChamp::#{type_champ.classify}TypeDeChamp"`,
  `type_de_champ.rb:970`) → chaque `type_champ` résout toujours vers sa propre classe.
- `ReferentielTypeDeChamp` est un **stub vide** → hériter aujourd'hui est à comportement constant.

Pourquoi le concern (et pas la logique directement dans le parent) : `ReferentielTypeDeChamp` est
un fichier **détenu par l'upstream**. Y déposer du code PF crée de la friction de merge. Le concern
vit dans un fichier PF ; le fichier upstream ne reçoit qu'une ligne `include` marquée `# pf:`.

**Nouvelle classe `Columns::ReferentielColumn`** (sœur de `Columns::JSONPathColumn`,
`app/models/columns/json_path_column.rb`).

Motivation : `value_json` d'un RDP est un **hash plat `{ jsonpath_string => valeur castée }`**
(construit par `ReferentielChamp#cast_displayable_values`, `referentiel_champ.rb:154`), et non un
JSON imbriqué. `JSONPathColumn` **ne convient pas** :
- en **lecture**, `typed_value` fait `JsonPath.on(champ.value_json, jsonpath)` → renvoie `nil`
  sur un hash dont la clé est littéralement `"$.taux_unité"` ;
- en **filtrage**, `filtered_ids` interroge Postgres avec l'opérateur jsonpath `@?` (JSON
  imbriqué) → ne matche pas non plus la clé plate.

La nouvelle classe lit et filtre par **accès direct à la clé** :

```ruby
class Columns::ReferentielColumn < Columns::ChampColumn
  attr_reader :jsonpath

  # type: issu de mapping[:type] (decimal_number → :decimal_number, etc.)
  def initialize(..., jsonpath:, type:, ...)
    @jsonpath = jsonpath
    super(...)
  end

  # Filtrage : la clé value_json est littéralement le jsonpath ("$.taux_unité")
  # → match de clé exacte via ->>, PAS l'opérateur jsonpath @? de JSONPathColumn.
  def filtered_ids(dossiers, filter)
    dossiers.with_type_de_champ(stable_id)
      .where("champs.value_json ->> ? ILIKE ?", jsonpath, "%#{filter[:value]}%")
      .ids
  end

  private

  def typed_value(champ) = champ.value_json&.fetch(jsonpath, nil)

  def column_id = "type_de_champ/#{stable_id}-referentiel-#{jsonpath}"
end
```

**Le concern `ReferentielColumnsConcern#columns(procedure:, displayable:, prefix:)`** : en plus de
la colonne scalaire héritée, émet **une `ReferentielColumn` par entrée de
`referentiel_mapping_displayable`** (colonnes mappées pour affichage, `prefill != "1"`, donc
présentes dans `value_json`). Chaque colonne porte son `type` (issu du mapping) et un **`label` =
`mapping[:libelle]`** (libellé d'affichage, comme `paths`). La référence en formule est donc
`{Barème CATANAT/<libellé d'affichage>}`.
**N'émet aucune `ReferentielColumn` si `referentiel_mapping` est absent** (dossiers legacy
`table_row_selector` : on garde uniquement la colonne scalaire, cf. §3).

> **Contrepartie assumée** : référencer par libellé d'affichage **n'est pas tolérant au renommage**
> d'une colonne — le mapping et les formules qui la référencent devront être repris si le libellé
> change. Choix retenu pour la lisibilité des formules côté admin, cohérent avec `paths`.

**Indexation & résolution (aucune modification du resolver attendue)** :
`FormulaColumnResolver#build_columns_index` (`app/services/formula_column_resolver.rb:69`) itère
`tdc.columns(procedure:)` et encode chaque colonne. `encode_column_id`
(`formula_column_resolver.rb:147`) doit reconnaître `Columns::ReferentielColumn` et produire la
clé composite `tdc<stable_id>/<libellé d'affichage>` (le même `label` que celui exposé par la
colonne — cohérent avec la syntaxe `{Barème CATANAT/<libellé>}`).
`resolve_with_path` teste déjà la clé composite complète en premier
(`formula_column_resolver.rb:50`) → la colonne est résolue directement.

**Syntaxe de formule** (générée depuis les colonnes disponibles, pas saisie à la main) :

```
SI({Barème CATANAT/type_bio} = "oui";
   MIN({quantité} × {Barème CATANAT/taux_unité} × {Barème CATANAT/taux_bio}; {Barème CATANAT/plafond});
   MIN({quantité} × {Barème CATANAT/taux_unité}; {Barème CATANAT/plafond}))
```

**Extraction row-scoped (chemin existant)** : `FormulaCalculationService` résout la colonne
contre le champ trouvé par `find_champ_by_stable_id_and_row` (`formula_calculation_service.rb:697`)
— même ligne si formule + RDP dans le même bloc, fallback parent sinon —, puis
`column.typed_value(champ)` lit le `value_json` **de la bonne ligne**.

### 2. Cascade / recalcul temps réel

La formule référence le `stable_id` du **RDP**. Il faut donc que la détection de dépendances
reconnaisse `{tdc<rdp>/col}` comme une dépendance vers le `stable_id` du RDP :
`Champ#dependent_formula_stable_ids` / la construction du graphe (`app/models/champ.rb:355`) doit
mapper la référence composite « colonne de référentiel » vers le `stable_id` du RDP (et non vers
un TDC inexistant).

Une fois cela fait, **aucun nouveau déclencheur de cascade n'est nécessaire** :
`refresh_formulas_after(rdp_champ)` est déjà appelé quand le RDP change de valeur
(`ReferentielChamp#data=` → `refresh_formulas_after` du controller ; `update_external_data!:62`
en flux exact_match). Il amorce le graphe depuis le `stable_id` du RDP, en propageant
`row_id: rdp.row_id` → la formule de la **même ligne** se recalcule. C'est le gain central de
l'approche « lire les colonnes » vs « prefill dans un sibling ».

**Validation à l'édition** : `available_columns_for_formula`
(`app/models/procedure_revision_type_de_champ.rb:183`) doit inclure les colonnes du RDP comme
sources valides — pour une formule-ligne, le RDP sibling antérieur ; pour une formule root, un RDP
root antérieur. `FormuleTypeDeChamp#forward_reference?` / `circular_reference?` doivent les
accepter sans faux positif.

### 3. Cas limites & robustesse

- **RDP non encore sélectionné** : `value_json` est `nil` → `typed_value` retourne `nil`. La
  formule se comporte comme avec un champ vide (contrat existant du `FormulaCalculationService`).
- **Colonne retirée de la config** : la `ReferentielColumn` disparaît de l'index → référence non
  résolue. Traitée comme une référence cassée existante : alerte à l'édition via
  `available_columns_for_formula` ; au runtime → `nil`.
- **Typage** : on fait confiance à `mapping[:type]`. La valeur dans `value_json` est **déjà
  castée** par `call_caster` au stockage (ex. `decimal_number` → `Float`) ; pas de re-cast dans
  la formule.
- **Prefill vs lecture** : une colonne sert soit au prefill (→ champ sibling éditable) soit à
  l'affichage/formule (displayable). Pour CATANAT : taux/plafond en displayable, pas de prefill.
  On documente : displayable = « affichable ET lisible en formule/filtre/export » ; prefill =
  « valeur éditable copiée dans un champ ».
- **Dossiers legacy (`table_row_selector`)** : pas de `referentiel_mapping`, `value_json`
  souvent absent (mode config Baserow, cf. `referentiel_de_polynesie_champ.rb:110`). Le concern
  n'émet alors **aucune** `ReferentielColumn` → aucune régression sur ces dossiers, ni en
  formule, ni en filtre/export/tableau instructeur.
- **Régression affichage instructeur (choix « exposer partout »)** : de nouvelles colonnes
  apparaissent dans le sélecteur de colonnes du tableau instructeur, les filtres et les exports
  v2 des procédures utilisant un référentiel mappé. C'est le comportement voulu (aligné sur
  DN/commune/SIRET) mais il faut le tester explicitement (cf. §4) et le mentionner dans les notes
  de release. L'ordre d'implémentation isole ce risque du cœur « formule ».

### 4. Tests

**Unitaires**
- `Columns::ReferentielColumn#typed_value` : valeur présente ; `value_json` nil ; jsonpath absent.
- `Columns::ReferentielColumn#filtered_ids` : match via `->>` sur la clé plate.
- `ReferentielColumnsConcern#columns` testé **sur les deux TDC** (`ReferentielTypeDeChamp` ET
  `ReferentielDePolynesieTypeDeChamp`) : émet une `ReferentielColumn` par colonne displayable avec
  le bon `type` ; **aucune** colonne si `referentiel_mapping` absent (legacy).
- `FormulaColumnResolver` : `{tdc<rdp>/col}` → `ReferentielColumn` (clé composite indexée).
- Détection de dépendance : `dependent_formula_stable_ids` d'un RDP inclut la formule qui lit une
  de ses colonnes.

**Filtres / exports / tableau instructeur (choix « exposer partout »)**
- Filtre instructeur sur une colonne de référentiel (résultats corrects, insensible à la casse).
- Export v2 : la colonne apparaît et contient la valeur castée.
- Sélecteur de colonnes du tableau instructeur : la colonne est proposée et s'affiche.
- Procédure legacy `table_row_selector` : **aucune** nouvelle colonne (non-régression).

**Intégration cascade** (`spec/models/champs/formule_cascade_audit_spec.rb`) — cœur du risque :
- Sélection d'une ligne de référentiel dans un bloc → la formule de la **même ligne** se
  recalcule via `refresh_formulas_after(rdp)`.
- Deux lignes avec des catégories différentes → valeurs de formule **distinctes par ligne** (pas
  de fuite inter-lignes, cf. `value_overrides` keyé par stable_id).

**Système (Capybara)** — 1 à 2 scénarios :
- Usager choisit une catégorie dans un bloc répétable → l'estimation de la ligne se remplit ;
  ajout d'une 2ᵉ ligne avec une autre catégorie → estimations indépendantes.
- (optionnel) Formule root lisant un RDP root.

## Fichiers impactés (prévisionnel)

- `app/models/columns/referentiel_column.rb` — **nouveau** (lecture + filtrage sur clé plate).
- `app/models/types_de_champ/concerns/referentiel_columns_concern.rb` — **nouveau** concern PF
  portant `columns` dérivé de `referentiel_mapping_displayable`.
- `app/models/types_de_champ/referentiel_type_de_champ.rb` — 1 ligne `# pf: include
  ReferentielColumnsConcern` (fichier upstream, édition minimale).
- `app/models/types_de_champ/referentiel_de_polynesie_type_de_champ.rb` — **changement de parent**
  `< TypesDeChamp::ReferentielTypeDeChamp` (au lieu de `TypeDeChampBase`) → hérite du concern.
- `app/services/formula_column_resolver.rb` — `encode_column_id` reconnaît `ReferentielColumn`.
- `app/models/champ.rb` — `dependent_formula_stable_ids` mappe la réf composite → stable_id RDP.
- `app/models/procedure_revision_type_de_champ.rb` — `available_columns_for_formula` inclut les
  colonnes du RDP.
- Specs : `spec/models/columns/`, `spec/models/types_de_champ/` (les deux TDC), `spec/services/`,
  `spec/models/champs/formule_cascade_audit_spec.rb`, `spec/system/` (formule + filtres/exports).

## Risques connus

- **Formules-ligne non matérialisées au rebase** : `formule_champs_for_tdc` fait
  `return [] if tdc.child?(revision)` — une formule-ligne ajoutée par rebase ne crée pas les Champs
  formule des lignes existantes. Ce chantier n'aggrave pas ce comportement ; à documenter dans le
  plan comme limite connue héritée.
- **Fuite `value_overrides` inter-lignes** : le service évite déjà la fuite en relisant les
  siblings frais pour les formules-ligne. La spec de tests couvre explicitement des valeurs
  distinctes par ligne.
- **Héritage silencieux de comportements upstream** (suite au changement `RDP <
  ReferentielTypeDeChamp`) : si l'upstream ajoute une méthode à `ReferentielTypeDeChamp`, le RDP
  l'héritera sans décision explicite. Coût déjà assumé au niveau champ (`ReferentielChamp`), géré
  via overrides `# pf:`. À surveiller lors des intégrations upstream touchant le référentiel.
- **Renommage de colonne Baserow** : la référence par libellé d'affichage casse les formules si le
  libellé change (cf. §1). À documenter côté admin.
