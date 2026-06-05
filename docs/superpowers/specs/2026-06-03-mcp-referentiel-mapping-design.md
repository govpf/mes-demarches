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
**Décision sur la réutilisation (point bloquant résolu) :** l'éligibilité des cibles vit dans `ReferentielPrefillComponent` (component de vue, volatile vis-à-vis des bumps upstream). On **ne fait PAS de `send`** sur ses méthodes d'instance privées. Elle se **décompose** en deux morceaux de natures différentes :

- **Compat de type** = `ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP` — **constante publique** → on la **réutilise** (même pattern que `ChampComponent::ACCEPTED_TYPES`, accepté précédemment), backée par un **spec canari** qui échoue en CI si upstream la renomme/supprime/modifie (blast radius = 1 spec + 1 ligne).
- **Ordre + scope** (« cible située APRÈS le référentiel, même visibilité public/privé ») = uniquement des **primitifs de coordonnée stables** (`coordinate.siblings`, `coordinate.position`, `coordinate.child?`) — on **réécrit ces ~5 lignes en code PF isolé** (ce sont des primitifs Rails stables, déjà utilisés par `demarcheDeplacerChamp`), donc aucun couplage au component volatile.

Validations restantes :
- **Cible existe** : `prefill_stable_id` ∈ champs de la révision.
- **Cible éligible** : après le référentiel + scope cohérent (logique ci-dessus) + type compatible (constante réutilisée).

En MVP, validation au write + message d'erreur clair. Bonus possible : l'outil `lire_referentiel_champ` indique par colonne les cibles éligibles.

## 5. Approche backend (isolée, sans refactor)

- **Query PF** `referentielChampConfig(demarche, stableId)` → un type `McpReferentielChamp` (tableId, colonnes Baserow, mapping actuel). Réutilise `BaserowAPI.fields` + `safe_referentiel_mapping`.
- **Mutation PF** `demarcheConfigurerReferentielMapping(demarche, stableId, colonnes)` → fusionne dans `referentiel_mapping`, valide (cf. §4), save. Réutilise les constantes/méthodes existantes (`MAPPING_TYPE_TO_TYPE_DE_CHAMP`, méthodes `referentiel_mapping_*`).
- Aucun fichier upstream modifié hors enregistrement (`# pf:` dans `query_type`/`mutation_type`).
- **MCP** : 2 outils (`lire_referentiel_champ`, `configurer_referentiel_mapping`).

## 6. Faisabilité

🟢 **Faisable** pour le câblage du mapping. C'est du JSONB structuré + des validations déjà factorisées. La source étant pré-existante, on évite tout le flux gnarly (création de `Referentiel`, auth, test).

**Dépendances / limites (décidées) :**
- **Baserow injoignable → on BLOQUE** : les outils (lecture ET écriture) renvoient une erreur claire, pas de config « à l'aveugle ». Rien n'est possible sans la liste réelle des colonnes.
- **Colonne disparue de Baserow → on NETTOIE** : à la (re)configuration, les entrées de `referentiel_mapping` dont la colonne n'existe plus dans Baserow sont supprimées (et signalées dans le retour).
- `table_id` doit déjà être posé sur le champ (hors scope : le poser).
- Pas de gestion des sous-chemins complexes / agrégats de colonnes Baserow imbriquées (MVP = colonnes plates).

## 7. Hors périmètre (assumé)

- **Création/config de la SOURCE** (`Referentiel`, `table_id`, URL API, auth, autocomplete_configuration, appel de test) → reste dans l'UI.
- **Référentiels API génériques** (`Referentiels::APIReferentiel`, JSONPath arbitraires, datasource/template) → non couverts ici (ce plan cible Baserow/PF).
- Config Baserow legacy (champs usager/instructeur côté Baserow) → ignorée, non gérée.

## 8. Points résolus / à confirmer

- **Éligibilité des cibles (résolu) :** réutiliser la constante publique `ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP` (+ **spec canari** qui casse si upstream la renomme/modifie) ; réécrire l'ordre/scope en **code PF isolé** via les primitifs stables `coordinate.siblings`/`position`/`child?`. **Pas de `send`** sur une méthode d'instance volatile.
- **Colonne disparue (résolu) :** nettoyage des entrées orphelines à la (re)config, signalé dans le retour.
- **Baserow injoignable (résolu) :** blocage avec erreur claire (pas de config à l'aveugle).
- **Stratégie de test (résolu, allège le point #4) :** (1) tests cœur *cheap* — la mutation écrit le bon `referentiel_mapping` (assert), le read stube `BaserowAPI.fields` ; (2) la propagation prefill (`propagate_prefill`) est **déjà testée upstream** → non re-testée ; (3) test e2e **optionnel** réutilisant le stub existant `allow(ReferentielDePolynesie::API).to receive(:fetch_row)` (pattern présent dans `spec/models/champs/referentiel_de_polynesie_champ_spec.rb`).
- **À confirmer (mineur) :** échappement de la clé `"$.<NomColonne>"` si un nom de colonne Baserow contient des caractères spéciaux.

## 9. Recommandation

Périmètre net et faisable. Si validé, le plan d'implémentation suivra le même découpage que les plans précédents : backend (query + mutation PF, TDD rspec, dump schéma) puis MCP (2 outils typés, tests vitest), avec au moins un test d'intégration prefill de bout en bout.
