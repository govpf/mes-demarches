# Ajustements à la spec formule typage/dépendances

_Date : 2026-05-21 | Source : revue critique xhigh du design 2026-05-20_

---

## Contexte

Le design original [`2026-05-20-formule-typage-dependances-design.md`] est en
cours d'exécution. **Étapes A et B déjà réalisées.** Une revue critique a fait
émerger quatre ajustements à appliquer sur les étapes restantes (C → G) +
des corrections factuelles. Ce document est un **patch** sur la spec
d'origine — à lire en complément, pas à la place.

---

## Aj-1 — Format de stockage : Hash structuré au lieu d'`Array<String>`

**Impact : Étape D, Étape E, Étape F.**

La spec d'origine propose `options['dependents']` comme un `Array<String>` avec
conventions de nommage figées (`"tdc<N>"`, `"self"`, `"clock"`, `"identite"`).

**Nouveau format retenu** : `options['formule_deps']` est un **Hash**, avec
convention « clé absente ⇒ false » pour les flags :

```ruby
options['formule_deps'] = {
  'champs'       => [42, 78],          # Array<Integer> (stable_ids, sans path)
  'has_clock'    => true,              # absent ou false ⇒ pas de fonction d'horloge
  'has_state'    => true,              # absent ⇒ pas de ref {dossier_*_at}
  'has_identite' => true               # absent ⇒ pas de ref {individual_*}/{entreprise_*}
}
```

**Justification.**
- Lecture directe O(1), pas de parsing string au runtime côté consommateur.
- Extensibilité préservée : ajouter `'has_external_data' => true` demain ne
  casse pas les TDC existants (lecture d'une clé absente ⇒ `nil` ⇒ falsy).
- Format auto-documenté (les clés portent le nom de la catégorie).

**Notes de format.**
- Le path éventuel d'une référence (`{tdc42/nom}` → la sous-propriété `nom`)
  **n'est pas conservé** dans `champs` : on garde uniquement le stable_id pour
  l'usage actuel (déclenchement de cascade). Le path n'a pas de consommateur
  identifié aujourd'hui (cf. `Champ#dependent_formula_stable_ids` qui ne
  l'utilise pas).
- Hash sérialisé via le `WithIndifferentAccess` déjà en place sur `options`.

**Convention de nommage du store accessor.**
- Clé options : `'formule_deps'` (plutôt que `'dependents'` qui est ambigu).
- `store_accessor :options, :formule_deps` dans `TypeDeChamp` (ligne 149,
  liste `formule:`).

---

## Aj-2 — Calculer `has_clock` via l'AST Dentaku, pas par regex

**Impact : Étape D.**

La spec d'origine propose un scan regex `/AUJOURDHUI|MAINTENANT|AGE|EST_PASSEE|EST_FUTURE/i`
pour `has_clock`. C'est ce que fait déjà
`FormulaCalculationService.clock_dependent?` aujourd'hui.

**Défaut** : la regex match dans les littéraux de chaîne. Exemple :

```
CONCATENER("L'AGE(x) est dans le détail", {Nom})
```

→ matche `AGE(` → `has_clock = true` à tort → recalcul quotidien inutile.

**Correctif** : l'AST Dentaku distingue `Dentaku::AST::Function` (nœud d'appel
de fonction) d'un `Dentaku::AST::Literal` (string). On a déjà l'AST construit
ligne 188 de `validate_expression` (`ast_node = calculator.ast(testable)`).
Le walker est trivial :

```ruby
CLOCK_FUNCTION_NAMES = Set[:AUJOURDHUI, :MAINTENANT, :AGE, :EST_PASSEE, :EST_FUTURE].freeze

def ast_uses_function?(node, function_names)
  return false if node.nil?
  return true if node.respond_to?(:class) && function_names.include?(node.class.name)
  children = node.respond_to?(:args) ? node.args :
             [node.respond_to?(:left) ? node.left : nil,
              node.respond_to?(:right) ? node.right : nil].compact
  children.any? { |c| ast_uses_function?(c, function_names) }
end
```

**Cantonnement strict de l'AST à `has_clock`.**
- `has_state` (refs `{dossier_*_at}`), `has_identite` (refs `{individual_*}` /
  `{entreprise_*}`), `champs` (refs `{tdc<N>}`) restent en **regex** sur
  l'expression brute. Les `{}` sont des délimiteurs syntaxiques Dentaku
  (jamais dans un littéral string), donc la regex est sûre par construction.
- Seules les **fonctions** ont besoin de l'AST (un identifiant nu type `AGE`
  peut apparaître dans un littéral).

**Note de robustesse** : si l'AST n'est pas construit (échec de parsing — cas
où la formule est invalide), `has_clock` est mis à `false` par défaut. Le
recalcul cron passera à côté, mais une formule invalide n'a de toute façon
pas de valeur à recalculer.

---

## Aj-3 — Trigger `identite` : appel explicite dans le controller, pas d'`after_commit`

**Impact : Étape G (refonte).**

La spec d'origine propose un `after_commit` sur `Individual` et `Etablissement`
qui appelle `dossier.refresh_formulas_with_dependent("identite")`.

**Problème** : viole la convention documentée dans `CLAUDE.md` :

> Convention : la cascade est explicite, pas implicite par callback.
>
> Tout site qui modifie un champ source d'une formule doit appeler
> explicitement `dossier.refresh_formulas_after(champ)`.

**Approche retenue** : appels explicites dans les controllers qui modifient
l'identité, pas de callback AR.

**Sites à instrumenter.**

1. `app/controllers/users/dossiers_controller.rb#update_identite` (ligne 179)
   — après `@dossier.update(dossier_params) && @dossier.individual.valid?`,
   ajouter :

   ```ruby
   @dossier.refresh_formulas_with_identite_dependents
   ```

2. `app/controllers/users/dossiers_controller.rb#update_siret` /
   `create_etablissement_and_redirect` — après création/MAJ de l'établissement
   lié au dossier, même appel.

3. Vérifier `APIEntrepriseService#create_etablissement` (mentionné dans
   CLAUDE.md comme déjà site de cascade via `update_champ_value_json!`) :
   probablement déjà couvert par la cascade champ → ajouter la couverture
   identite seulement si ce site modifie aussi `Etablissement` hors du flux
   champ (vérification à faire par le dév).

**Méthode à ajouter dans `DossierFormulaRefreshConcern`.**

```ruby
def refresh_formulas_with_identite_dependents
  matching = revision.types_de_champ.filter do |tdc|
    tdc.formule? && tdc.formule_deps&.[]('has_identite')
  end
  return if matching.empty?
  compute_formulas_in_order(only: matching.map(&:stable_id).to_set)
end
```

Pas d'`after_commit` ajouté sur `Individual` ni sur `Etablissement`.

---

## Aj-4 — Retirer entièrement le sniffing du composant, pas en fallback

**Impact : Étape A (déjà partiellement faite — point à revérifier).**

La spec d'origine garde le sniffing regex comme fallback quand
`output_type: nil`. C'est inutile :

- `output_type` est inféré dans `validate_expression`
  (ligne 194 de `formule_type_de_champ.rb`) à chaque save d'une formule.
- Tous les TDC formule en base ont donc un `output_type` non-nil dès qu'ils
  ont été validés une fois. Pas de cas légitime de `nil`.
- Garder le sniffing protège contre un défaut imaginaire et masque les vrais
  bugs (cas `"003"` rendu comme `"3"` parce que le sniffing voit un entier).

**Action à demander au dév.**
- Vérifier que `FormulaValueDisplayComponent` n'a plus de chemin
  `output_type.nil?` qui retombe sur sniffing.
- Si la signature est `initialize(value:, output_type: nil)` : changer en
  `initialize(champ:)` ou `initialize(value:, output_type:)` **sans default**
  pour rendre l'oubli détectable.

**Recommandation forte** : passer **le champ** plutôt que `value:` + `output_type:`,
pour garantir une source unique de vérité au call-site et éviter qu'un dev
futur passe l'un sans l'autre :

```ruby
# _show.html.haml
= render FormulaValueDisplayComponent.new(champ: champ)

# Component
def initialize(champ:)
  @value = champ.value&.to_s&.strip
  @output_type = champ.type_de_champ.formule_output_type
end
```

---

## Corrections factuelles

### CF-1 — Étape B déjà entièrement implémentée

Les cinq fonctions de l'Étape B existent déjà dans
`app/services/formula_calculation_service.rb` :

- `DUREE_SEMAINES` (lignes 345–347)
- `JOURS_ENTRE` (lignes 351–354)
- `SEMAINES_ENTRE` (lignes 356–359)
- `MOIS_ENTRE` (lignes 362–367)
- `ANNEES_ENTRE` (lignes 371–380)

→ Le dév peut **sauter l'Étape B** (le code et — selon ce qui a été réalisé —
les tests sont déjà en place). Vérifier juste que les tests existent dans
`spec/services/formula_calculation_service_spec.rb` (sinon les ajouter).

### CF-2 — Scénario S3 : corriger les noms de variables

La spec utilise `{individual_nom}` et `{individual_prenom}` qui **n'existent
pas** dans le résolveur. Cf. `app/services/formula_column_resolver.rb` lignes
63–66 :

```ruby
index['individual_gender'] = ...
index['individual_first_name'] = ... # mapping vers la colonne `prenom`
index['individual_last_name'] = ...  # mapping vers la colonne `nom`
```

→ Remplacer dans S3 :
- `{individual_nom}` → `{individual_last_name}`
- `{individual_prenom}` → `{individual_first_name}`

Idem pour la doc IA (Étape C) si elle référence ces variables : utiliser les
noms exposés par le résolveur, sinon les formules suggérées par l'IA seront
invalides.

### CF-3 — `dependent_stable_ids` n'était pas stocké à l'origine

La spec d'origine présente trois propriétés orthogonales stockées
(`dependent_stable_ids`, `clock_dependent`, `state_dependent`). En réalité,
**seuls les deux booléens étaient écrits dans `options`**.
`TypeDeChamp#dependent_stable_ids` (ligne 466) re-parsait l'expression à
chaque appel.

→ Conséquence pratique pour la **migration data** (Étape E) : on n'a rien à
nettoyer côté `options['dependent_stable_ids']` (clé absente partout). À
nettoyer en base : `clock_dependent`, `state_dependent`. À écrire :
`formule_deps`. Adapter le script en conséquence.

---

## Récap des actions par étape du plan

| Étape | Statut | Action |
|---|---|---|
| A | partiellement faite | Appliquer Aj-4 (retirer le sniffing fallback). Préférer signature `champ:` |
| B | **faite** | Vérifier que les specs des cinq fonctions existent (CF-1) |
| C | à faire | Documenter les fonctions ajoutées dans `formula_ai_prompt_service.rb` |
| D | à faire | Appliquer Aj-1 (format Hash) + Aj-2 (AST pour `has_clock`). Renommer `dependents` → `formule_deps`. Toujours conserver `clock_dependent` / `state_dependent` tant que les consommateurs (Étape F) n'ont pas migré |
| E | à faire | Adapter la migration au format Hash + CF-3 (pas de `dependent_stable_ids` à supprimer) |
| F | à faire | Adapter les 5 consommateurs au format Hash (cf. table ci-dessous) |
| G | **refonte** | Appliquer Aj-3 (appels explicites controllers, pas d'`after_commit`) |

### Détail consommateurs Étape F (adaptation au format Hash)

| Fichier | Avant | Après |
|---|---|---|
| `app/models/champ.rb` ligne 353 | `tdc.dependent_stable_ids.each` | `(tdc.formule_deps&.[]('champs') \|\| []).each` |
| `app/models/concerns/dossier_formula_refresh_concern.rb` ligne 206 | `tdc.state_dependent` | `tdc.formule_deps&.[]('has_state')` |
| `app/models/concerns/dossier_formula_refresh_concern.rb` ligne 47 | `tdc.clock_dependent` | `tdc.formule_deps&.[]('has_clock')` |
| `app/jobs/cron/refresh_clock_dependent_formulas_job.rb` ligne 41 | `options->>'clock_dependent' = 'true'` | `options->'formule_deps'->>'has_clock' = 'true'` |
| `app/models/procedure_revision.rb` ligne 229 | `other_tdc.dependent_stable_ids.include?(stable_id)` | `(other_tdc.formule_deps&.[]('champs') \|\| []).include?(stable_id)` |

### Détail spécifique Aj-3 (Étape G refondue)

- **Ne pas créer** : aucun `after_commit` sur `Individual` ni sur `Etablissement`.
- **Ajouter dans `DossierFormulaRefreshConcern`** : méthode
  `refresh_formulas_with_identite_dependents` (snippet ci-dessus).
- **Modifier** : `Users::DossiersController#update_identite` et
  `update_siret` / `create_etablissement_and_redirect` pour appeler la
  méthode après modification réussie.
- **Spec** : ajouter dans
  `spec/controllers/users/dossiers_controller_spec.rb` (pas dans le concern
  spec) un test qui vérifie qu'un `update_identite` recalcule les formules
  `has_identite` du dossier.

---

## Hors scope (inchangé)

Les points "out of scope" de la spec d'origine restent valides : pas de
preview temps-réel, pas de badge, pas d'autocomplete des nouvelles fonctions,
pas de type `:duration` exposable, pas d'agrégation en répétition, pas
d'exposition `formule_deps` en GraphQL.
