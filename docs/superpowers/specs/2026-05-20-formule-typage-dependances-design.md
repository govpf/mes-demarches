# Design doc — Formule : typage d'affichage + durées N2 + graphe de dépendances unifié

_Date : 2026-05-20 | Auteur : architecture review_

---

## 1. Contexte et motivation

### Chantier 2 — Typage de retour et fonctions durée niveau 2

`FormulaValueDisplayComponent` (`app/components/formula_value_display_component.rb`) effectue un type-sniffing par regex sur la string de sortie (lignes 28–44). La règle `value.match?(/\A\d{4}-\d{2}-\d{2}/)` attrape toute valeur commençant par quatre chiffres-tiret-deux chiffres-tiret-deux chiffres, y compris des concaténations comme `"2026-06-08CAP-19297/288"`, et la fait passer dans `Date.parse` + rendu `<time>`. Le bug est reproduit en prod. Le correctif consiste à passer `formule_output_type` au composant et à dispatcher sur ce type stocké plutôt que sur la forme de la valeur. Parallèlement, le DSL manque de fonctions permettant de calculer des intervalles entre deux dates (JOURS_ENTRE, MOIS_ENTRE, etc.) et d'alias explicites pour DUREE_SEMAINES qui n'existe pas encore (DUREE_ANNEES, DUREE_MOIS, DUREE_JOURS sont présents depuis `app/services/formula_calculation_service.rb`).

### Chantier 4 — Graphe de dépendances unifié

Le système stocke aujourd'hui trois propriétés orthogonales sur `TypeDeChamp.options` : `dependent_stable_ids` (Array d'entiers), `clock_dependent` (booléen), `state_dependent` (booléen). Ces trois champs sont détectés séparément dans `FormuleTypeDeChamp#validate_expression` et consommés dans au moins cinq endroits distincts. Les dépendances sur l'identité individu/entreprise ne sont pas modélisées, ce qui empêche les formules référençant `{individual_nom}` ou `{entreprise_siret}` de se recalculer quand l'identité change. Le remplacement par un tableau de strings `dependents` unifié permet d'encoder toutes les catégories de dépendances dans un seul champ JSON extensible et simplifie la logique de recalcul.

---

## 2. Décisions architecturales

1. **Pas de nouveau type `:duration`** pour `formule_output_type` — les fonctions `*_ENTRE` retournent `:numeric` (entier de jours/mois/années), les `DUREE_*` retournent un offset additionnable à une date (compatible Dentaku existant). Aucune modification du système de types inféré.

2. **`formule_output_type` transmis au composant via paramètre explicite** — le composant passe de `initialize(value:)` à `initialize(value:, output_type: nil)`. Un `output_type: nil` conserve le comportement actuel (fallback sniffing) pour assurer la rétrocompatibilité pendant la migration des call-sites.

3. **Tableau `dependents: Array<String>`** remplace les trois clés. Convention de nommage figée : `"tdc<N>"`, `"tdc<N>/<path>"`, `"self"`, `"identite"`, `"clock"`. Les clés anciennes sont supprimées à la migration ; les méthodes publiques qui les exposaient sont remplacées par des dérivations sur `dependents`.

4. **Migration data one-shot** via migration Rails (pas de maintenance task séparée) : le volume de `TypeDeChamp` formule est faible, un `UPDATE` inline dans `up` est acceptable. La migration est irréversible (`down` est un no-op documenté).

5. **Triggers `identite`** ajoutés dans `Individual` et `Etablissement` via `after_commit` ; la méthode cible `Dossier#refresh_formulas_with_dependent("identite")` est ajoutée dans `DossierFormulaRefreshConcern`.

---

## 3. Plan d'exécution

### Étape A — Corriger `FormulaValueDisplayComponent`

**Quoi.** Changer la signature du composant pour accepter `output_type:`, supprimer le sniffing regex pour les cas couverts par le type stocké, conserver `format_as_number` avec conversion propre des Rational (remplacer `value.to_f` par `Rational(value).to_f rescue value.to_f` pour éviter `"195/1"`).

**Fichiers touchés.**
- `app/components/formula_value_display_component.rb` — refonte de `initialize` et `formatted_value`.
- `app/views/shared/champs/formule/_show.html.haml` — passer `output_type: champ.type_de_champ.formule_output_type`.
- `app/components/editable_champ/formule_component.rb` — idem dans `formatted_value`.

**Test attendu.** Créer `spec/components/formula_value_display_component_spec.rb`. Scenarios : `output_type: 'string'` avec valeur `"2026-06-08CAP-19297/288"` → rendu texte sans balise `<time>` ; `output_type: 'date'` avec valeur `"2026-06-08"` → balise `<time>` ; `output_type: 'number'` avec `"195/1"` → `"195"` ; `output_type: nil` avec `"2026-06-08"` → fallback actuel (rétrocompat).

**Critère de validation.** Les quatre scenarios de spec passent. `bundle exec rspec spec/components/formula_value_display_component_spec.rb`.

---

### Étape B — Ajouter `*_ENTRE` et `DUREE_SEMAINES` au DSL

**Quoi.** Dans `FormulaCalculationService#add_french_date_functions` (ligne 294), enregistrer cinq nouvelles fonctions Dentaku : `JOURS_ENTRE`, `SEMAINES_ENTRE`, `MOIS_ENTRE`, `ANNEES_ENTRE` (toutes `:numeric`), et `DUREE_SEMAINES`. Respecter la convention nil-safe : si l'un des arguments est nil, retourner nil.

Logique de `MOIS_ENTRE(d1, d2)` : `(d2.year - d1.year) * 12 + (d2.month - d1.month)`. Logique de `ANNEES_ENTRE(d1, d2)` : différence d'années révolues (même algorithme que `AGE` inversé, tenir compte si le mois/jour de d2 est avant celui de d1 dans l'année courante). `JOURS_ENTRE(d1, d2)` = `(to_date(d2) - to_date(d1)).to_i`. `SEMAINES_ENTRE` = `JOURS_ENTRE / 7` (division entière).

`DUREE_SEMAINES(n)` = `n.to_i * 7` jours, sur le même modèle que `DUREE_JOURS` existant.

**Fichiers touchés.**
- `app/services/formula_calculation_service.rb` — uniquement `add_french_date_functions`.

**Test attendu.** Dans `spec/services/formula_calculation_service_spec.rb`, ajouter un context `"fonctions durée"` avec au minimum : `JOURS_ENTRE` sur deux dates connues, `SEMAINES_ENTRE` (arrondi vers zéro), `MOIS_ENTRE` bord de mois (31 jan → 28 fév = 1 mois), `ANNEES_ENTRE` bord d'anniversaire (29 fév), entrée nil → nil pour chaque fonction, `DUREE_SEMAINES(2)` additionné à une date.

**Critère de validation.** `bundle exec rspec spec/services/formula_calculation_service_spec.rb`.

---

### Étape C — Exposer les nouvelles fonctions dans `FormulaAiPromptService`

**Quoi.** Dans `functions_section` de `app/services/formula_ai_prompt_service.rb` (ligne 167), ajouter sous la section "Date" les lignes de documentation des cinq nouvelles fonctions avec exemples. Vérifier que `OUTPUT_TYPE_LABELS` (ligne 15) couvre bien tous les `formule_output_type` possibles (`'date'`, `'datetime'`, `'boolean'`, `'string'`, `'number'`).

**Fichiers touchés.**
- `app/services/formula_ai_prompt_service.rb`.

**Test attendu.** Ajouter un test dans `spec/services/formula_ai_prompt_service_spec.rb` (ou créer le fichier s'il n'existe pas) qui vérifie que `generate` inclut `"JOURS_ENTRE"` et `"SEMAINES_ENTRE"` dans sa sortie.

**Critère de validation.** Spec verte. Vérification manuelle du prompt via l'UI de l'éditeur formule.

---

### Étape D — Introduire `dependents` dans `FormuleTypeDeChamp#validate_expression`

**Quoi.** Dans `validate_expression` (`app/models/types_de_champ/formule_type_de_champ.rb`, ligne 126), après le calcul des flags actuels, calculer et stocker `@type_de_champ.options['dependents']` en appelant une nouvelle méthode privée `compute_dependents(expression)`. Cette méthode parse l'expression et produit un Array dédoublonné de strings selon les conventions définies. En parallèle, **conserver** le calcul de `clock_dependent` et `state_dependent` pendant cette étape — ils sont retirés à l'étape F uniquement.

`compute_dependents` :
- scan `/{tdc(\d+)(?:\/([^}]+))?}/` → `"tdc<N>"` ou `"tdc<N>/<path>"`
- scan `/\{(dossier_number|dossier_state|dossier_depose_at|dossier_en_instruction_at|dossier_processed_at)\}/` → `"self"`
- scan `/\{(individual_|entreprise_)/` → `"identite"`
- présence de `AUJOURDHUI|MAINTENANT|AGE|EST_PASSEE|EST_FUTURE` (case-insensitive) → `"clock"`

Ajouter `store_accessor :options, :dependents` dans `TypeDeChamp` (ligne 149).

**Fichiers touchés.**
- `app/models/types_de_champ/formule_type_de_champ.rb`
- `app/models/type_de_champ.rb` (ligne 149 — ajouter `:dependents` à la liste `formule:`)

**Test attendu.** Dans `spec/models/types_de_champ/formule_type_de_champ_spec.rb`, context `"compute_dependents"` : expression avec `{tdc42}` → `["tdc42"]` ; `{tdc42/nom}` → `["tdc42/nom"]` ; `AUJOURDHUI()` → `["clock"]` ; `{dossier_en_instruction_at}` → `["self"]` ; `{individual_nom}` → `["identite"]` ; expression mixte → dédoublonnage correct.

**Critère de validation.** Spec verte + `clock_dependent` et `state_dependent` toujours calculés (pas de régression).

---

### Étape E — Migration data

**Quoi.** Migration Rails one-shot qui, pour chaque `TypeDeChamp` de type `formule`, calcule `dependents` depuis les trois anciennes clés et l'expression stockée, écrit dans `options['dependents']`, supprime `options['dependent_stable_ids']`, `options['state_dependent']`, `options['clock_dependent']`. Voir section 4 pour le script détaillé.

**Fichiers touchés.**
- `db/migrate/YYYYMMDDHHMMSS_migrate_formula_dependents.rb` (nouveau)

**Test attendu.** Spec de migration (optionnel mais recommandé) : créer un `TypeDeChamp` formule avec les anciennes clés, lancer `up`, vérifier `options['dependents']` et l'absence des anciennes clés.

**Critère de validation.** `bundle exec rails db:migrate` sans erreur sur une base fraîche et sur une base avec données.

---

### Étape F — Adapter les consommateurs, supprimer les anciens flags

**Quoi.** Mettre à jour tous les sites qui lisent `clock_dependent` / `state_dependent` / `dependent_stable_ids` :

- `app/models/champ.rb` ligne 353 : `tdc.dependent_stable_ids.each` → `tdc.dependents.filter_map { |d| d.match(/\Atdc(\d+)/)&.[](1)&.to_i }.each`
- `app/models/concerns/dossier_formula_refresh_concern.rb` :
  - `refresh_state_dependent_formulas_if_needed` ligne 206 : `tdc.state_dependent` → `tdc.dependents&.include?("self")`
  - `has_state_dependent_formula?` ligne 212 : idem
  - `refresh_clock_dependent_formulas` ligne 46 : `tdc.clock_dependent` → `tdc.dependents&.include?("clock")`
  - Renommer `refresh_state_dependent_formulas_if_needed` → `refresh_dossier_dependent_formulas_if_needed` (hook `after_commit` ligne 32 aussi)
  - Ajouter méthode `refresh_formulas_with_dependent(dep_string)` pour les triggers `identite`
- `app/jobs/cron/refresh_clock_dependent_formulas_job.rb` ligne 41 : remplacer `options->>'clock_dependent' = 'true'` par `options->'dependents' @> '["clock"]'::jsonb`
- Supprimer `store_accessor` de `:clock_dependent`, `:state_dependent`, `:dependent_stable_ids` dans `TypeDeChamp` ligne 149

**Fichiers touchés.**
- `app/models/champ.rb`
- `app/models/concerns/dossier_formula_refresh_concern.rb`
- `app/jobs/cron/refresh_clock_dependent_formulas_job.rb`
- `app/models/type_de_champ.rb`
- `app/models/types_de_champ/formule_type_de_champ.rb` (retirer le calcul des anciens flags)

**Test attendu.** `spec/models/concerns/dossier_formula_refresh_concern_spec.rb` : vérifier que les tests `marks the formula as clock_dependent` et `marks the formula as state_dependent` sont mis à jour pour tester `dependents.include?("clock")` et `dependents.include?("self")`. `spec/jobs/cron/refresh_clock_dependent_formulas_job_spec.rb` : vérifier que le scope SQL cible bien le nouveau format JSONB.

**Critère de validation.** `bundle exec rspec spec/models/concerns/dossier_formula_refresh_concern_spec.rb spec/jobs/cron/` vert.

---

### Étape G — Triggers `identite` sur `Individual` et `Etablissement`

**Quoi.** Ajouter dans `Individual` (`app/models/individual.rb`) un `after_commit` qui appelle `dossier.refresh_formulas_with_dependent("identite")` si `nom_previously_changed? || prenom_previously_changed? || (respond_to?(:date_de_naissance_previously_changed?) && date_de_naissance_previously_changed?)`. Même pattern dans `Etablissement` (`app/models/etablissement.rb`) sur les colonnes qui peuvent être référencées par une formule. Vérifier que `Etablissement#update_champ_value_json!` (couvert dans CLAUDE.md) ne déclenche pas de double recalcul.

**Fichiers touchés.**
- `app/models/individual.rb`
- `app/models/etablissement.rb`
- `app/models/concerns/dossier_formula_refresh_concern.rb` (ajout de `refresh_formulas_with_dependent`)

**Test attendu.** Nouveau context dans `spec/models/concerns/dossier_formula_refresh_concern_spec.rb` : procédure `for_individual`, formule référençant `{individual_nom}`, modification de `individual.nom` → valeur de la formule recalculée. Idem pour `Etablissement`.

**Critère de validation.** Spec verte. Aucune cascade infinie (vérifié par absence de stack overflow ou boucle infinie dans le test).

---

## 4. Migration data

```ruby
# db/migrate/YYYYMMDDHHMMSS_migrate_formula_dependents.rb
class MigrateFormulaDependents < ActiveRecord::Migration[7.0]
  CLOCK_FUNCTIONS = /AUJOURDHUI|MAINTENANT|AGE|EST_PASSEE|EST_FUTURE/i
  DOSSIER_REFS    = /\{(dossier_number|dossier_state|dossier_depose_at|dossier_en_instruction_at|dossier_processed_at)\}/
  IDENTITE_REFS   = /\{(individual_|entreprise_)/
  TDC_REF         = /\{tdc(\d+)(?:\/([^}]+))?\}/

  def up
    TypeDeChamp.where(type_champ: 'formule').find_each do |tdc|
      opts = tdc.options || {}
      expr = opts['formule_expression'].to_s

      deps = []

      expr.scan(TDC_REF) do |id, path|
        deps << (path ? "tdc#{id}/#{path}" : "tdc#{id}")
      end
      deps << "self"     if expr.match?(DOSSIER_REFS)
      deps << "identite" if expr.match?(IDENTITE_REFS)
      deps << "clock"    if expr.match?(CLOCK_FUNCTIONS)
      deps.uniq!

      new_opts = opts
        .merge('dependents' => deps)
        .except('dependent_stable_ids', 'clock_dependent', 'state_dependent')

      # pf: update_column skip les callbacks — pas de cascade parasite
      tdc.update_column(:options, new_opts)
    end
  end

  def down
    # pf: non réversible — les anciens flags ne sont pas recalculés en down
    # car cela nécessiterait de recharger FormulaCalculationService.
    # En cas de rollback, relancer validate_expression sur chaque TDC formule.
  end
end
```

**Ordre d'exécution :** lancer avant le déploiement du code de l'étape F (les consommateurs ne lisent plus les anciens flags). La migration peut tourner en parallèle du trafic : `update_column` est atomique par ligne, pas de verrou global.

**Rollback :** si nécessaire avant le déploiement F, les anciens flags sont encore en place dans la base. Si le rollback intervient après le déploiement F, relancer `FormulaTypeDeChamp#validate_expression` sur tous les TDC formule via une rake task.

---

## 5. Risques et mitigations

**(a) Formules existantes en prod.** La migration écrit `dependents` sans supprimer les anciens flags tant que le code de l'étape F n'est pas déployé. Les deux représentations coexistent. Si la migration est accidentellement jouée sans le code F, les consommateurs continuent de lire les anciens flags (pas de régression immédiate).

**(b) Cascade infinie.** Le guard `return if champ.type_de_champ.formule?` (ligne 73 de `dossier_formula_refresh_concern.rb`) empêche qu'une formule déclenchée en cascade re-déclenche une cascade. Le trigger `identite` appelle `refresh_formulas_with_dependent` qui doit appeler `compute_formulas_in_order` (pas `refresh_formulas_after`) pour rester dans le même périmètre sans re-entrer dans les hooks.

**(c) Perf du recalcul transitif.** `dependent_formula_stable_ids` effectue un BFS en mémoire sur les TDC de la révision (pas d'accès BDD par nœud). La complexité est O(N formules). Pour les procédures à très nombreuses formules chaînées (> 50), ajouter un circuit-breaker `MAX_CHAIN_DEPTH = 20` avec log Sentry si dépassé.

**(d) Compatibilité GraphQL.** `formule_output_type` n'est pas exposé dans le schéma GraphQL public actuellement. Aucun impact. Si exposé à l'avenir, les valeurs `'date'` et `'datetime'` sont déjà dans le domaine du champ — pas de breaking change.

---

## 6. Tests d'intégration

### Specs de référence à étendre

**`spec/models/concerns/dossier_formula_refresh_concern_spec.rb`** — ajouter :
- Context `"with identite dependency"` : procédure `for_individual`, formule `SI({individual_nom} == "TEST", 1, 0)`, modification de `individual.nom` → formule recalculée.
- Context `"with state dependency via dependents"` : vérifier que le recalcul est déclenché après `passer_en_instruction!` quand `dependents.include?("self")`.

**`spec/models/champs/formule_cascade_audit_spec.rb`** (existant, à étendre) — spec de non-régression documentée dans CLAUDE.md. Doit couvrir :
- Formule A dépend de champ source X → modification de X recalcule A.
- Formule B dépend de formule A → modification de X recalcule A puis B (transitivité).
- Formule avec `dependents: ["clock"]` → recalculée par `RefreshClockDependentFormulasDossierJob` et non par `refresh_formulas_after`.
- Formule avec `dependents: ["identite"]` → recalculée par le trigger `Individual#after_commit`.

### Nouveaux scenarios

- `JOURS_ENTRE` dans une formule sur dossier → valeur recalculée quand source date change.
- Composant affiche texte `"2026-06-08CAP-19297/288"` sans balise `<time>` quand `output_type: 'string'`.
- `DUREE_SEMAINES(3)` additionné à une date → date + 21 jours.

---

## 7. Out of scope

Les points suivants ne font pas partie de ce chantier :

- Preview temps-réel du résultat dans l'éditeur formule (avant sauvegarde du TDC).
- Badge "calculé automatiquement" visible par l'usager sur le champ formule.
- Autocomplete des nouvelles fonctions dans `formula_autocomplete_controller.ts`.
- Type `:duration` comme `formule_output_type` exposable.
- Agrégation sur blocs répétables (`SOMME.SI`, `NBLIGNES`).
- Exposition de `dependents` dans l'API GraphQL publique.
- Nettoyage du format legacy `{123}` (entier nu sans préfixe `tdc`) dans `dependent_stable_ids` — la migration lit les deux formats mais le stockage en `dependents` ne perpétue que le format `tdc<N>`.
