# Référentiel de Polynésie : abandon des colonnes méta « Champs usager » / « Champs instructeur »

**Date :** 2026-09-17 · **Branche :** `feature/referentiel-meta-legacy` (depuis devpf bb08470493)

## Contexte

Depuis le sous-classage de `Referentiels::BaserowReferentiel` sur le référentiel upstream, l'affichage
des colonnes à l'usager et à l'instructeur est porté par `TypeDeChamp#referentiel_mapping`
(`display_usager` / `display_instructeur`). Les colonnes « Champs usager » et « Champs instructeur »
de la table méta Baserow sont documentées comme legacy (spec MCP du 2026-06-03) mais restent lues
par deux sites :

1. `TypesDeChamp::ReferentielDePolynesieTypeDeChamp#paths` (tags d'attestation/courrier, colonnes
   d'export) : branche legacy quand `referentiel_mapping_displayable_for_instructeur` est vide.
   Site du 500 corrigé par la PR #557 (colonne périmée → `nil.to_sym`).
2. `Referentiels::BaserowReferentiel#headers` (sélecteur de sous-colonnes de l'éditeur, via
   `TypesDeChampEditor::ChampComponent#extract_sub_paths`) : union des deux colonnes méta.

Mesure en production du 2026-09-16 (script lecture seule) : 13 champs référentiel dans 8 démarches
publiées ; 4 sans mapping et 3 avec mapping sans affichage instructeur, dont 6 avec une table méta
renseignée → 6 champs dépendent encore de la branche legacy pour leurs tags instructeur.

**Décision utilisateur :** reprise côté instructeur uniquement. « Champs usager » n'est pas repris :
l'affichage usager passait déjà exclusivement par le mapping, et cocher l'usager ferait apparaître
des colonnes d'un coup sur des démarches publiées (3111 « Rubriques », 27 dossiers actifs).

## Tâches

1. **Maintenance task** `T20260917migrateBaserowMetaColumnsToMappingTask` (`run_on_first_deploy`,
   idempotente) : pour chaque `TypeDeChamp` `referentiel_de_polynesie` (toutes révisions) dont
   `referentiel_mapping_displayable_for_instructeur` est vide et dont la table méta a
   « Champs instructeur » renseigné : pour chaque colonne encore existante, crée l'entrée de mapping
   manquante (`type` déduit du type Baserow, `libelle` = nom de colonne, `prefill` 0,
   `display_usager` 0) ou complète l'entrée existante, avec `display_instructeur` 1. Colonne périmée
   ignorée ; Baserow injoignable → champ laissé intact (la task est relançable). Écriture par
   `update_column(:options)`, sans callbacks.
2. **`#paths`** : suppression de la branche legacy et de `fetch_instructeur_fields*`. Correction
   embarquée : le sous-chemin du tag devient la colonne (`jsonpath` sans `$.`), le libellé
   personnalisé ne sert qu'à l'affichage — auparavant un libellé différent du nom de colonne
   produisait un tag qui lisait `value_json["$.<libelle>"]`, toujours vide.
3. **`#headers`** : toutes les colonnes de la table via `ReferentielDePolynesie::API.table_fields`
   (cache 5 min). **`#extract_sub_paths`** : colonnes du mapping affichables (celles présentes dans
   `value_json`), sans appel Baserow.
4. Specs alignées (`baserow_referentiel_spec`, `referentiel_de_polynesie_type_de_champ_spec`,
   `tags_substitution_concern_spec`, `dossier_export_referentiel_de_polynesie_spec`), doc
   `french_polynesia.md`.

## Hors périmètre

Suppression physique des deux colonnes dans Baserow (à faire à la main après déploiement) ;
« Champ de recherche », « Champ propriétaire », « Table », « Token » restent lus.
