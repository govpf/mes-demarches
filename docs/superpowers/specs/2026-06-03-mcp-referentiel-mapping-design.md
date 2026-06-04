# Plan C — Configuration du mapping d'un champ référentiel (Baserow/PF) via le MCP — Spec de faisabilité

**Date :** 2026-06-03
**Statut :** Spec de faisabilité (pas de plan d'implémentation tant que non validée)
**Scope décidé :** mapping seul (source pré-existante) · type `referentiel_de_polynesie` (Baserow)

## 1. Objectif

Permettre à Claude (via le MCP) de **configurer le mapping** d'un champ `referentiel_de_polynesie` : pour chaque colonne du référentiel Baserow, décider si elle **pré-remplit** un champ du formulaire, et/ou si elle est **rapatriée/affichée** à l'usager et/ou à l'instructeur. La **source** (table Baserow, `table_id`) est supposée déjà configurée.

## 2. Modèle (confirmé dans le code)

**Une seule structure** porte les trois facettes (privé/public, pré-remplir, rapatrier) : `type_de_champ.options[:referentiel_mapping]` (JSONB), une entrée par colonne, **clé = JSONPath** `"$.<NomColonne>"` :

```
"$.RaisonSociale" => {
  type: "string",                 # type de la donnée (auto depuis Baserow)
  libelle: "Raison sociale",      # libellé d'affichage (optionnel)
  prefill: "0" | "1",             # "1" => pré-remplit un champ
  prefill_stable_id: "12345",     # champ cible si prefill="1"
  display_usager: "0" | "1",      # rapatrié/affiché à l'usager
  display_instructeur: "0" | "1", # rapatrié/affiché à l'instructeur
  example_value: "..."            # exemple (issu d'un test)
}
```

- **pré-remplir** = `prefill:"1"` + `prefill_stable_id`
- **rapatrier** = `prefill:"0"` + `display_usager`/`display_instructeur`
- **privé/public** = le champ référentiel lui-même (`prive`) + contraintes (cf. §4)

**Source des colonnes disponibles :** Baserow, via `ReferentielDePolynesie::BaserowAPI.fields(config)` (config résolue depuis `table_id`, caché 1h). Chaque champ Baserow → `{ name, type }`, mappé en type interne via `baserow_type_to_mapping_type`.

> ⚠️ **Correction PF (utilisateur) :** la config « Champs usager / Champs instructeur » **dans Baserow** est **legacy et désormais ignorée**. Toute la config usager/instructeur/prefill est **à fournir dans mes-demarches** (le `referentiel_mapping`). Baserow ne fournit plus que la **liste des colonnes + types**. C'est exactement ce qui rend ce plan pertinent.

**Méthodes de lecture déjà disponibles** (à réutiliser, `app/models/type_de_champ.rb`) : `safe_referentiel_mapping`, `referentiel_mapping_prefillable_with_stable_id`, `referentiel_mapping_displayable_for_usager` / `_for_instructeur`.

## 3. Surface MCP proposée

**Outil de lecture — `lire_referentiel_champ(demarcheNumber, stableId)`** → retourne :
- `tableId`
- `colonnesDisponibles` : `[{ nom, typeBaserow, typeMapping }]` (depuis Baserow `fields`)
- `mappingActuel` : `[{ colonne, type, libelle, prefill, prefillStableId, displayUsager, displayInstructeur }]`

Claude voit ainsi les colonnes réelles + l'état courant avant de configurer.

**Outil d'écriture — `configurer_referentiel_mapping(demarcheNumber, stableId, colonnes: [...])`** où chaque entrée :
- `colonne` (nom de colonne Baserow, requis)
- `prefillStableId?` (→ pré-remplit ce champ ; met `prefill:"1"`)
- `displayUsager?` / `displayInstructeur?` (booléens → rapatrier)
- `libelle?`, `type?` (optionnels ; type par défaut = type Baserow auto)

Le serveur fusionne dans `referentiel_mapping` (merge par clé `"$.<colonne>"`), en réutilisant le casting et les méthodes existantes.

## 4. Validations à réutiliser (pas de réimplémentation)

- **Cible existe** : `prefill_stable_id` ∈ champs de la révision.
- **Ordre** : la cible de pré-remplissage doit être située **après** le champ référentiel (cf. `Referentiels::ReferentielPrefillComponent`, contrainte de position).
- **Scope privé/public** : référentiel public → cible publique ; référentiel privé (annotation) → cible privée (même logique que le component prefill).
- **Compat de type** : `MAPPING_TYPE_TO_TYPE_DE_CHAMP` (dans `ReferentielPrefillComponent`) — le type de la colonne doit être compatible avec le type du champ cible.

Idéalement, exposer ces contraintes en lecture (l'outil `lire_referentiel_champ` pourrait indiquer, par colonne, les champs cibles éligibles) — mais en MVP, validation au write + message d'erreur clair suffit.

## 5. Approche backend (isolée, sans refactor)

- **Query PF** `referentielChampConfig(demarche, stableId)` → un type `McpReferentielChamp` (tableId, colonnes Baserow, mapping actuel). Réutilise `BaserowAPI.fields` + `safe_referentiel_mapping`.
- **Mutation PF** `demarcheConfigurerReferentielMapping(demarche, stableId, colonnes)` → fusionne dans `referentiel_mapping`, valide (cf. §4), save. Réutilise les constantes/méthodes existantes (`MAPPING_TYPE_TO_TYPE_DE_CHAMP`, méthodes `referentiel_mapping_*`).
- Aucun fichier upstream modifié hors enregistrement (`# pf:` dans `query_type`/`mutation_type`).
- **MCP** : 2 outils (`lire_referentiel_champ`, `configurer_referentiel_mapping`).

## 6. Faisabilité

🟢 **Faisable** pour le câblage du mapping. C'est du JSONB structuré + des validations déjà factorisées. La source étant pré-existante, on évite tout le flux gnarly (création de `Referentiel`, auth, test).

**Dépendances / limites :**
- **Baserow doit être joignable** au moment de la config (pour lister les colonnes). En cas d'indispo, l'outil de lecture renvoie une erreur claire (et on peut accepter une config « à l'aveugle » sur des noms de colonnes fournis par l'admin en fallback).
- `table_id` doit déjà être posé sur le champ (hors scope : le poser).
- Pas de gestion des sous-chemins complexes / agrégats de colonnes Baserow imbriquées (MVP = colonnes plates).

## 7. Hors périmètre (assumé)

- **Création/config de la SOURCE** (`Referentiel`, `table_id`, URL API, auth, autocomplete_configuration, appel de test) → reste dans l'UI.
- **Référentiels API génériques** (`Referentiels::APIReferentiel`, JSONPath arbitraires, datasource/template) → non couverts ici (ce plan cible Baserow/PF).
- Config Baserow legacy (champs usager/instructeur côté Baserow) → ignorée, non gérée.

## 8. Points à confirmer à l'implémentation

- Format exact de la clé de mapping pour une colonne Baserow : `"$.<NomColonne>"` (confirmé via `ReferentielDePolynesieTypeDeChamp#paths` qui fait `jsonpath.delete_prefix('$.')`) — vérifier l'échappement si un nom de colonne contient des caractères spéciaux.
- Réutilisation exacte de la logique d'éligibilité des cibles de prefill (extraire/`send` depuis `ReferentielPrefillComponent` sans refactor, ou répliquer la règle d'ordre+scope en code PF isolé — décision selon la volatilité du component).
- Comportement quand une colonne du mapping n'existe plus dans Baserow (nettoyage ? avertissement ?).
- Test système formule-like : un scénario d'intégration « configurer un prefill via le MCP → remplir le champ référentiel → le champ cible est pré-rempli » (conforme à la discipline de tests de cascade du projet).

## 9. Recommandation

Périmètre net et faisable. Si validé, le plan d'implémentation suivra le même découpage que les plans précédents : backend (query + mutation PF, TDD rspec, dump schéma) puis MCP (2 outils typés, tests vitest), avec au moins un test d'intégration prefill de bout en bout.
