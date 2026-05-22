# Design doc — Formule : agrégation sur blocs répétables

_Date : 2026-05-21 | Auteur : architecture review_

Spec complémentaire à `2026-05-20-formule-typage-dependances-design.md`. Indépendante en lecture, exécutable en PR distincte.

---

## 1. Contexte et motivation

Le champ formule supporte déjà les **formules-ligne** : une formule placée à l'intérieur d'un bloc répétable s'exécute par ligne et accède aux champs de sa ligne courante (cf. `formule_champ.row_id` consommé dans `FormulaCalculationService`). Ce qui manque, et que demandent 6 cas sur 15 du catalogue d'usage (FIPTH, médico-social, transports, pension de famille, accidents environnementaux, perliculture) :

> Une formule **hors** du bloc qui **agrège** un sous-champ de toutes les lignes du bloc.

Exemples concrets :
- `SOMME({Lignes de facture/Prix HT})` — somme des prix de toutes les lignes
- `COUNT({Investisseurs personne physique})` — nombre de lignes
- `SOMME({Lignes de facture/Prix HT}) - SOMME({Paiements/Montant})` — reste à payer

Aucune fonction custom à inventer : Dentaku 3.5.4 supporte nativement `SUM`, `COUNT`, `MAX`, `MIN`, `AVG` sur des arrays passés en binding. Le travail se limite à **étendre la résolution de référence** pour reconnaître deux nouvelles formes et construire les bindings adaptés.

---

## 2. Décisions architecturales

1. **Notation `{Libellé du bloc}` et `{Libellé du bloc/Libellé sous-champ}`** — extension de la convention `/` déjà utilisée pour les sous-propriétés JSON (`{tdc456/date_de_naissance}`). Disambiguïté par dispatch sur le type du TDC parent : `repetition` → résolution sous-champ ; sinon → JSON path existant. Aucune collision possible (un bloc répétable n'a pas de sous-propriété JSON).

2. **Binding `{bloc}` = Array de row_ids opaques** (`[42, 43, 44]`). Coût quasi nul (`champs.map(&:row_id).uniq`), suffisant pour `COUNT`, extensible plus tard vers array de hashes si MAP exposé un jour. **Pas de hash de contenu en v1** — YAGNI.

3. **Binding `{bloc/sous_champ}` = Array de scalaires type-aware**, identique à la conversion appliquée pour les références scalaires (Date native, Integer, etc. — via `format_value_for_dentaku`).

4. **Pas de MAP exposé à l'admin en v1**. Les cas de transformation par ligne (`prix_ht * 1.2 si <1000 sinon * 1.1`) passent par une **formule-ligne intermédiaire** dans le bloc, puis agrégation extérieure. Cohérent avec ce qui fonctionne déjà, sans nouveau scoping de variable à inventer.

5. **Placement obligatoire en dessous du bloc** — validation explicite à l'enregistrement du TDC formule. Convention de dépendance descendante alignée sur `compute_formulas_in_order` (ordre de position).

6. **Granularité de dépendance = niveau bloc**. Une formule-agrégat enregistre `"tdc<stable_id_du_bloc>"` dans `dependents` (cf. chantier #4). Toute modification d'un sous-champ d'une ligne, ou ajout/suppression de ligne, déclenche le recalcul. Sur-recalcul léger acceptable.

---

## 3. Plan d'exécution

### Étape A — Étendre `FormulaColumnResolver` pour reconnaître les blocs

**Quoi.** Dans `FormulaColumnResolver#build_columns_index` (`app/services/formula_column_resolver.rb`), ajouter une entrée par TDC `repetition` dans la révision, identifiée par son libellé (à côté des `tdc<N>` existants). Idem pour chaque sous-TDC d'une repetition, accessible via `bloc_label/sub_label`.

**Fichiers touchés.**
- `app/services/formula_column_resolver.rb`

**Test attendu.** `spec/services/formula_column_resolver_spec.rb` — context « blocs répétables » :
- Résoudre `"Lignes de facture"` → renvoie un descripteur pointant le TDC repetition
- Résoudre `"Lignes de facture/Prix HT"` → renvoie un descripteur composite (bloc + sous-tdc)
- Résoudre `"Bloc inconnu"` → `nil` (pas d'erreur fatale)

**Critère de validation.** Spec verte.

---

### Étape B — Résolution dans `FormulaCalculationService`

**Quoi.** Dans `resolve_column_references` (`app/services/formula_calculation_service.rb` ~ ligne 375), ajouter deux cas avant le dispatch existant sur JSON path :

```ruby
def resolve_column_references(expression)
  expression.gsub(/\{([^}]+)\}/) do |_match|
    reference = Regexp.last_match(1).strip
    bloc_label, sub_label = reference.split('/', 2)
    target = @resolver.resolve(bloc_label)

    if target&.is_a?(TypeDeChamp) && target.repetition?
      if sub_label.present?
        register_variable(extract_repetition_values(target, sub_label))
      else
        register_variable(extract_repetition_rows(target))
      end
    else
      # Logique existante (scalaire, JSON path, colonne système)
      resolve_existing(reference)
    end
  end
end

def extract_repetition_rows(bloc_tdc)
  all_champs
    .select { |c| c.parent_id == bloc_tdc.stable_id }
    .map(&:row_id)
    .compact
    .uniq
end

def extract_repetition_values(bloc_tdc, sub_label)
  sub_tdc = bloc_tdc.types_de_champ.find { |t| t.libelle == sub_label }
  return [] unless sub_tdc

  rows = all_champs.select { |c| c.parent_id == bloc_tdc.stable_id }
  rows.group_by(&:row_id).values.map do |row_champs|
    champ = row_champs.find { |c| c.stable_id == sub_tdc.stable_id }
    format_value_for_dentaku(champ&.value, sub_tdc.type_champ.to_sym)
  end
end
```

**Fichiers touchés.**
- `app/services/formula_calculation_service.rb`

**Test attendu.** `spec/services/formula_calculation_service_spec.rb` — context « agrégation sur répétition » :
- `SOMME({Lignes/Prix HT})` sur un bloc à 3 lignes (100, 200, 50) → 350
- `COUNT({Lignes})` sur un bloc à 3 lignes → 3
- `MAX({Lignes/Prix HT})` → 200
- `MOYENNE({Lignes/Prix HT})` → 116.67
- Bloc vide : `SOMME` → 0, `COUNT` → 0, `MAX` → nil (comportement Dentaku natif)
- Ligne avec sous-champ nil : nil ignoré dans l'agrégation
- Combinaison : `SOMME({Lignes/Prix HT}) - SOMME({Paiements/Montant})` → reste à payer

**Critère de validation.** `bundle exec rspec spec/services/formula_calculation_service_spec.rb` vert.

---

### Étape C — Validation : placement obligatoire en dessous du bloc

**Quoi.** Dans `TypesDeChamp::FormuleTypeDeChamp#validate_expression` (`app/models/types_de_champ/formule_type_de_champ.rb`), ajouter une règle de validation `forward_reference?` étendue : pour chaque référence détectée à un TDC repetition, vérifier que ce TDC est positionné **avant** le TDC formule dans l'ordre de la révision. Si non, ajouter une erreur `:invalid_placement` avec un message clair.

L'algorithme existant `forward_reference?` (ligne ~311) qui détecte déjà les références à un TDC postérieur peut être réutilisé tel quel — un bloc répétable est un TDC normal du point de vue de la position.

**Fichiers touchés.**
- `app/models/types_de_champ/formule_type_de_champ.rb`
- `config/locales/models/type_de_champ/fr.yml` (message d'erreur)

**Test attendu.** `spec/models/types_de_champ/formule_type_de_champ_spec.rb` :
- Formule placée AVANT le bloc référencé → invalide avec message « Le bloc 'X' doit être placé avant la formule »
- Formule placée APRÈS le bloc → valide

**Critère de validation.** Spec verte. Vérification manuelle dans l'éditeur.

---

### Étape D — Enregistrement des dépendances

**Quoi.** Dans la méthode `compute_dependents` (ajoutée par le chantier #2+#4), ajouter la détection des références à blocs et sous-champs :

- `{Libellé bloc}` → résoudre vers `stable_id` du bloc → ajouter `"tdc<N>"` à `dependents`
- `{Libellé bloc/Libellé sous-champ}` → résoudre vers le `stable_id` du **bloc parent** (pas du sous-champ) → ajouter `"tdc<N>"` à `dependents`

Granularité bloc : si n'importe quelle ligne ou sous-champ change, la formule-agrégat se recalcule. Simple et suffisant.

**Fichiers touchés.**
- `app/models/types_de_champ/formule_type_de_champ.rb` (dans `compute_dependents`)

**Test attendu.** Dans `formule_type_de_champ_spec.rb`, context `compute_dependents` :
- Expression avec `{Lignes/Prix HT}` → `dependents` inclut `"tdc<id_bloc>"`
- Expression avec `{Lignes}` seul → idem
- Pas de duplication si plusieurs sous-champs du même bloc référencés

**Critère de validation.** Spec verte.

---

### Étape E — Triggers de recalcul sur ligne ajoutée/supprimée/modifiée

**Quoi.** Vérifier que les flux existants déclenchent bien le recalcul des formules-agrégat :

1. **Modification d'un sous-champ d'une ligne** — le sous-champ a son propre `stable_id` (différent du bloc). Pour qu'une formule dépendante de `"tdc<bloc_id>"` se recalcule quand `tdc<sub_id>` change, il faut que `dependent_formula_stable_ids` (`app/models/champ.rb`) reconnaisse que la modification d'un sous-champ doit déclencher les formules qui dépendent du bloc parent.

   **Adaptation** : dans `Champ#dependent_formula_stable_ids`, quand le champ a un `parent_id`, propager la dépendance au TDC parent : `seeds << tdc_parent.stable_id` en plus du `stable_id` du sous-champ lui-même.

2. **Ajout/suppression de ligne** — `Dossier#repetition_add_row` et `Dossier#repetition_remove_row` (cf. CLAUDE.md) appellent déjà `refresh_formulas_after` pour les sous-champs. Vérifier qu'elles appellent aussi le refresh pour le TDC bloc lui-même (le bloc n'a pas de valeur scalaire mais le compteur de lignes change). Adapter si nécessaire.

**Fichiers touchés.**
- `app/models/champ.rb` (propagation de la dépendance parent)
- `app/models/dossier.rb` (méthodes `repetition_add_row` / `repetition_remove_row` si besoin)

**Test attendu.** Dans `spec/models/champs/formule_cascade_audit_spec.rb` (existant, déjà ciblé par #2+#4) :
- Modification d'un sous-champ d'une ligne → formule-agrégat se recalcule
- Ajout d'une ligne → `COUNT({bloc})` augmente de 1
- Suppression d'une ligne → `COUNT({bloc})` diminue de 1

**Critère de validation.** Spec verte. Test manuel sur une procédure pilote (FIPTH ou perliculture).

---

### Étape F — Enrichir `FormulaAiPromptService`

**Quoi.** Dans `app/services/formula_ai_prompt_service.rb`, ajouter dans la documentation générée pour l'IA :
- Section « Agrégation sur blocs répétables »
- Syntaxes `{Libellé bloc}` et `{Libellé bloc/Libellé sous-champ}`
- Exemples : `SOMME`, `COUNT`, `MAX`, `MIN`, `MOYENNE`
- Convention de placement (formule en dessous du bloc)
- Pattern de transformation par ligne via formule-ligne intermédiaire (avec un exemple complet)

**Fichiers touchés.**
- `app/services/formula_ai_prompt_service.rb`

**Test attendu.** `spec/services/formula_ai_prompt_service_spec.rb` :
- Le prompt généré inclut « SOMME({Bloc/Sous-champ}) »
- Le prompt inclut une mention de la limitation placement

**Critère de validation.** Spec verte. Vérification manuelle du prompt copié.

---

### Étape H — Alias français additionnels pour fonctions natives Dentaku

**Quoi.** Ajouter au hash de `config/initializers/dentaku_french_aliases.rb` les alias FR pour les fonctions natives Dentaku utiles qui n'en ont pas encore. Mettre à jour `FormulaAiPromptService#functions_section` (`app/services/formula_ai_prompt_service.rb`) pour les exposer.

**Liste retenue** (validée par observation du catalogue d'usage + tests Dentaku 3.5.4) :

| Native Dentaku | Alias FR | Catégorie prompt IA |
|---|---|---|
| `count` | `NB` (+ alias secondaire `COMPTE`) | Stats / agrégation |
| `rounddown` | `ARRONDI_INF` | Arithmétique |
| `roundup` | `ARRONDI_SUP` | Arithmétique |
| `floor` | `PLANCHER` | Arithmétique |
| `ceil` / `ceiling` | `PLAFOND` | Arithmétique |
| `sqrt` | `RACINE` | Arithmétique |
| `median` | `MEDIANE` | Stats |

**Note tokenisation Dentaku** : les noms Excel-français usuels `ARRONDI.INF` / `ARRONDI.SUP` ne sont **pas** utilisables — le tokenizer Dentaku traite le `.` comme un séparateur d'accès propriété (testé : `ARRONDI.INF(3.7, 0)` est tokenisé comme `identifier:"arrondi.inf"` et lève `Invalid statement` à l'évaluation). On utilise donc l'underscore, conforme aux autres alias Dentaku.

**Note prompt IA** : ne pas changer la formulation « Fonctions autorisées (liste exhaustive) » — la posture FR-first est volontaire. Ajouter optionnellement une phrase de clarification : « Les noms anglais équivalents (`LEFT`, `RIGHT`, `ROUND`, `ROUNDDOWN`, `ROUNDUP`, `FLOOR`, `CEIL`, `SQRT`, `MEDIAN`, `COUNT`) fonctionnent aussi nativement, mais préfère les noms FR par cohérence avec les autres formules. »

**Fichiers touchés.**
- `config/initializers/dentaku_french_aliases.rb` — ajout des entrées
- `app/services/formula_ai_prompt_service.rb` — enrichissement des sections « Arithmétique » et nouvelle ligne `NB(array)` dans la section dédiée aux blocs répétables

**Test attendu.** Dans `spec/services/formula_calculation_service_spec.rb`, ajouter un context « alias FR additionnels » avec un test par alias vérifiant que la formule retourne le même résultat que sa contrepartie anglaise :
- `ARRONDI_INF(3.7, 0)` → 3
- `ARRONDI_SUP(3.2, 0)` → 4
- `PLANCHER(5.8)` → 5
- `PLAFOND(5.2)` → 6
- `RACINE(16)` → 4
- `NB(arr)` avec `arr = [1,2,3]` → 3
- `MEDIANE(arr)` avec `arr = [1,2,3,4,5]` → 3

**Critère de validation.** Spec verte. Probe manuel via l'éditeur formule pour vérifier le rendu du prompt IA.

---

### Étape G — Autocomplete étendu

**Quoi.** Dans `app/javascript/controllers/formula_autocomplete_controller.ts`, étendre la liste des références proposées :
- Ajouter les TDCs de type `repetition` (libellé du bloc)
- Quand l'admin a déjà tapé `{Libellé bloc/`, proposer les sous-champs du bloc à la suite
- Préserver l'insertion par libellé exact (cf. ligne 411 : `{${column.label}}`)

Cette étape est UI-only, isolable du reste, peut partir en PR distincte des étapes A→F si besoin.

**Fichiers touchés.**
- `app/javascript/controllers/formula_autocomplete_controller.ts`
- Side data : la liste des colonnes envoyée au front (probablement via `app/controllers/...` ou data-attribute).

**Test attendu.** Test système (Capybara) : ouvrir l'éditeur formule, taper `{`, vérifier qu'un bloc apparaît dans les suggestions ; taper `{Bloc/`, vérifier qu'un sous-champ apparaît.

**Critère de validation.** Spec système verte. Test manuel.

---

## 4. Migration data

**Aucune migration nécessaire.** Le chantier #3 n'ajoute pas de nouveau champ persistant — `dependents` (existant après #2+#4) accueille naturellement les `"tdc<bloc_stable_id>"`. Les formules existantes ne référencent pas de blocs (la syntaxe ne le permettait pas), donc rien à reconvertir.

---

## 5. Risques et mitigations

**(a) Régression Dentaku sur MAP/PLUCK/SUM/COUNT non documentés.** Le probe a confirmé que ces fonctions marchent en 3.5.4 sur des arrays passés en binding, mais l'absence de doc officielle pose un risque de breaking change à une future upgrade. **Mitigation** : pinning de la version Dentaku dans le `Gemfile` (à vérifier), et **spec sentinelle** `spec/lib/dentaku_array_functions_spec.rb` qui exerce `SUM`, `COUNT`, `MAX`, `MIN`, `AVG` sur arrays bindings — si Dentaku casse ces fonctions, la CI le voit avant la prod.

**(b) Collision de libellé entre bloc et champ scalaire.** Si une procédure a un bloc « X » et un champ scalaire « X » au même niveau, l'autocomplete et le resolver doivent choisir. **Mitigation** : les validations existantes du modèle interdisent déjà les libellés en doublon dans une même section ? À vérifier. Sinon, ajouter une validation explicite côté formule (priorité au bloc, ou erreur de validation).

**(c) Lignes vides ou sous-champ nil.** `SOMME([100, nil, 50])` en Dentaku — comportement à vérifier. **Mitigation** : test explicite dans la spec (étape B) ; si Dentaku jette une erreur sur nil, filter nil au moment de construire le binding (à arbitrer selon le résultat du test).

**(d) Performance sur gros blocs.** Une procédure pourrait avoir un bloc à >500 lignes. La résolution itère sur tous les sous-champs (`all_champs.select { ... }`). **Mitigation** : `all_champs` est déjà chargé une fois par calcul, donc le coût est O(N) sur les sous-champs du bloc, pas de N+1 SQL. Acceptable sur 500 lignes (~quelques ms). Au-delà de 10 000 lignes, à reconsidérer — mais hors scope v1.

**(e) Disambiguïté `bloc/sous_champ` vs JSON path.** Le dispatch sur le type du TDC parent (`repetition` vs autre) tranche sans ambiguïté. **Mitigation** : test explicite dans la spec qui couvre les deux cas dans la même expression.

---

## 6. Tests d'intégration

### Specs à étendre / créer

**`spec/services/formula_calculation_service_spec.rb`** — context « agrégation sur répétition » :
- Cas d'usage complet de la démarche 3311 FIPTH (Repetition budget + cohérence éligible/octroyé)
- Cas d'usage 1611 perliculture (somme des destinations vs collecté)

**`spec/models/champs/formule_cascade_audit_spec.rb`** (existant, étendu par #2+#4) :
- Modification d'un sous-champ → formule-agrégat recalculée
- Ajout/suppression de ligne → `COUNT` et `SOMME` à jour

**`spec/lib/dentaku_array_functions_spec.rb`** (nouveau, sentinelle) :
- `Dentaku::Calculator.new.evaluate!("SUM(arr)", arr: [1,2,3])` → 6
- Idem `COUNT`, `MAX`, `MIN`, `AVG`
- Si une de ces specs casse à une upgrade Dentaku, on sait que la résolution agrégat va régresser

---

## 7. Out of scope

- **MAP, REDUCE, FILTER exposés à l'admin** — pas en v1. Les transformations par ligne passent par formule-ligne intermédiaire.
- **Agrégation filtrée (`COUNT_WHERE`, `SUM_WHERE`)** — pas en v1. Réalisable via formule-ligne `SI(...)` + agrégation, cf. patterns du catalogue.
- **Binding `{bloc}` en array de hashes complets** — option B abandonnée au profit de l'array de row_ids (option A). Si un futur besoin émerge (MAP exposé), on enrichira la résolution sans changer la syntaxe admin.
- **Agrégation cross-bloc ou cross-procédure** — hors périmètre.
- **Sucre syntaxique alternatif** (`{bloc}.SOMME` style méthode) — pas envisagé, Dentaku ne le supporte pas naturellement.
- **Modification de l'éditeur admin pour visualiser le placement (warning visuel quand formule au-dessus d'un bloc référencé)** — relève du chantier UI séparé (cf. audit design `2026-05-20` P0 preview).
- **Alias FR avec point séparateur** (`ARRONDI.INF`, `ARRONDI.SUP`) — bloqué par la tokenisation Dentaku (le `.` est traité comme accès propriété). Substitution par underscore (`ARRONDI_INF`) retenue. Si la limitation Dentaku saute dans une upgrade future, on pourra renommer.
