# Spec : Formule d'initialisation (valeur par défaut dynamique)

## Contexte

Inspiré de Grist, une formule d'initialisation permet de pré-remplir un champ avec une valeur calculée tout en laissant l'usager ou l'instructeur la modifier. C'est un pont entre les formules (read-only, recalculées) et les valeurs par défaut (statiques).

## Cas d'usage

- **Nom du demandeur** : `CONCATENER({Prénom}, " ", {Nom})` sur un champ texte → l'instructeur peut corriger
- **Première tranche** : `{Montant total} * 0.3` sur un champ nombre → modifiable par la commission
- **Date limite** : date de dépôt + 30 jours sur un champ date → ajustable par l'instructeur
- **Montant accordé** : `{Montant demandé} * 0.8` en annotation → la commission décide du montant final
- **Préqualification** : `SI({Âge} >= 18, 1, 0)` sur un champ `yes_no` "Majeur"

## Principe

Ce n'est **pas** un nouveau type de champ. C'est une **option** sur les types existants compatibles. Un champ avec une formule d'initialisation reste éditable — il a juste une valeur par défaut dynamique.

## Types de champ compatibles

La compatibilité est définie par un prédicat OO sur `TypesDeChamp::TypeDeChampBase`, pas par une liste en dur.

```ruby
# TypesDeChamp::TypeDeChampBase
def supports_init_formula?
  false
end

# Override dans chaque sous-classe compatible
# TypesDeChamp::TextTypeDeChamp, IntegerNumberTypeDeChamp, etc.
def supports_init_formula?
  true
end
```

### Phase 1 (MVP)
- `text`, `textarea` (résultat texte)
- `integer_number`, `decimal_number` (résultat numérique)
- `date` (résultat date)

### Phase 2 (extension rapide)
- `datetime` (analogue `date`)
- `yes_no`, `checkbox` (le typage booléen est déjà géré par `formule_output_type`)

### Phase 3 (à arbitrer)
- `drop_down_list` simple — puissant mais nécessite une stratégie de validation runtime (la valeur calculée doit matcher une option)
- `formatted` — nécessite que le résultat respecte `expression_reguliere`

### Définitivement exclus
- Pièces jointes (`piece_justificative`, `titre_identite`)
- Référentiels externes (`siret`, `iban`, `rna`, `rnf`, `annuaire_education`, `cnaf`, `dgfip`, `pole_emploi`, `mesri`, `cojo`, `referentiel`)
- Sélections contraintes multi-valeurs (`multiple_drop_down_list`, `linked_drop_down_list`, `pays`, `communes`, `departements`, `regions`, `epci`, `civilite`)
- Géographique structuré (`address`, `carte`)
- Structurels (`header_section`, `explication`, `repetition`, `dossier_link`, `engagement_juridique`)
- Visa (logique d'interaction humaine spécifique)
- Champs PF à lookup (`numero_dn`, `te_fenua`, `lexpol`, `referentiel_de_polynesie`, `commune_de_polynesie`, `code_postal_de_polynesie`, `nationalites`)

## Modèle de données

### TypeDeChamp (options JSON)

```ruby
store_accessor :options, :init_formula_expression
```

Tout TDC dont le type répond `supports_init_formula? == true` et qui a `init_formula_expression` rempli bénéficie du mécanisme. Pas de nouveau type, pas de migration.

### Champ (value_json JSONB existant)

```ruby
store_accessor :value_json, :formula_overridden
```

- `formula_overridden` nil ou absent → la valeur est recalculée quand les sources changent
- `formula_overridden` truthy → la valeur est figée, l'usager/instructeur a pris la main

Aucune migration nécessaire. `value_json` est un JSONB existant sur `champs`. Seuls les champs avec un override stockent cette clé (99,9 % des champs n'ont rien).

## Cycle de vie

### Phase 1 : Initialisation (à la création du champ)

Le calcul est déclenché par un callback `before_validation :initialize_from_formula, on: :create` sur la classe `Champ` (mutualisé pour tous les types compatibles).

```
Champ B est créé (avec init_formula_expression)
  → before_validation :initialize_from_formula tourne
  → skip si formula_overridden? (cas rare : recréation après flag persisté)
  → FormulaCalculationService calcule la valeur via project_champs
  → write_attribute(:value, valeur_calculée)
  → persist avec la valeur initiale
```

**Conséquence** : ce mécanisme couvre gratuitement :
- La création initiale d'un dossier (tous les champs créés → chacun calcule sa valeur)
- L'ajout d'une ligne dans une répétition (les nouveaux champs enfants calculent à la création)
- Les dossiers anciens en mode streaming (création lazy des champs → callback déclenché à la demande)
- Les annotations privées (même callback, aucune différence de traitement)

### Phase 2 : Recalcul automatique (tant que non overridé)

```
Usager modifie champ A (source de la formule de B)
  → refresh_dependent_formulas détecte B comme dépendant
  → B.formula_overridden est nil → recalcul autorisé
  → B.value est mis à jour avec la nouvelle valeur calculée (via update_column)
  → Turbo Stream re-render B
```

### Phase 3 : Override par l'usager/instructeur

Détection par **égalité stricte** `value_soumise == value_calculée`.

```
Usager modifie manuellement B (change "1200" en "1500")
  → Le controller détecte que la valeur soumise ≠ valeur calculée
  → B.formula_overridden = true
  → B.value = "1500"
```

Les faux positifs (trim, espaces, formatage) sont compensés par le bouton Reset.

### Phase 4 : Gel après override

```
Usager modifie A → refresh_dependent_formulas détecte B
  → B.formula_overridden est true → skip
  → B garde sa valeur "1500"
```

### Phase 5 : Reset (retour au calcul automatique)

Endpoint dédié pour isoler le code PF et limiter les conflits lors des merges upstream.

```
PATCH /champs/:id/reset_formula
  → B.formula_overridden = nil
  → B.value recalculé depuis la formule
  → Badge "Valeur calculée" réapparaît
  → Turbo Stream re-render
```

## Robustesse face aux sources non résolues

Au moment où le callback tourne, certaines sources peuvent ne pas être encore persistées (création en cascade d'un dossier). Le service utilise `@dossier.project_champs_public_all + @dossier.project_champs_private_all` qui construit des champs vides en mémoire pour les TDC sans champ existant.

| Situation | Comportement |
|-----------|--------------|
| Champ source déjà persisté | Récupéré avec sa vraie value ✅ |
| Champ source en mémoire, pas encore persisté | Idem — cache du dossier ✅ |
| Champ source pas encore créé | Champ vide construit → formule évalue sur du vide → résultat neutre |

Propriété **self-correcting** : même si le calcul initial est "neutre", `refresh_dependent_formulas` corrige dès que l'usager remplit une source. L'`init_formula` ne prétend pas être parfaite au premier tour, elle donne une valeur initiale crédible.

**À vérifier** : si la création d'un dossier utilise `insert_all` (batch SQL), les callbacks ActiveRecord ne tournent pas. Dans ce cas, prévoir une passe `after_commit` sur `Dossier` qui force le calcul des champs avec `init_formula`.

## Implémentation

### Callback de création (Champ)

```ruby
class Champ < ApplicationRecord
  before_validation :initialize_from_formula, on: :create

  def formula_overridden?
    value_json&.dig('formula_overridden') == true
  end

  private

  def initialize_from_formula
    return unless type_de_champ&.init_formula_expression.present?
    return if formula_overridden?

    computed = FormulaCalculationService.new(dossier).compute_init_value(self)
    write_attribute(:value, computed)
  end
end
```

### Détection de l'override (controller)

Dans `update_dossier_and_compute_errors`, après le save du champ :

```ruby
if champ.type_de_champ.init_formula_expression.present? && !champ.formula_overridden?
  calculated = FormulaCalculationService.new(dossier).compute_init_value(champ)
  if champ.saved_change_to_value? && champ.value != calculated
    champ.formula_overridden = true
    champ.save!
  end
end
```

### Intégration avec refresh_dependent_formulas

Le graphe de dépendances doit inclure les TDC avec `init_formula_expression`, et la boucle de recalcul doit skipper les overridés :

```ruby
formula_tdcs = dossier.revision.types_de_champ.filter do |tdc|
  tdc.formule? || tdc.init_formula_expression.present?
end

all_dependent_formula_champs.each do |champ|
  next if champ.type_de_champ.init_formula_expression.present? && champ.formula_overridden?
  # ... recalcul normal
end
```

### FormulaCalculationService

Ajouter une méthode `compute_init_value(champ)` qui dispatche sur `init_formula_expression` au lieu de `formule_expression`. Le reste de la mécanique (résolution de colonnes, fonctions FR, détection de cycles) est mutualisé.

```ruby
def compute_init_value(champ)
  expression = champ.type_de_champ.init_formula_expression
  return '' if expression.blank?
  # même flow que compute_value mais avec cette expression
end
```

### Endpoint reset

Controller dédié pour isolation upstream :

```ruby
# config/routes.rb (côté PF, clairement marqué)
resources :champs, only: [] do
  member do
    patch :reset_formula  # pf: reset d'une init_formula
  end
end

# app/controllers/champs_controller.rb (ou dédié)
def reset_formula
  @champ = current_user.dossier.champs.find(params[:id])
  @champ.formula_overridden = nil
  computed = FormulaCalculationService.new(@champ.dossier).compute_init_value(@champ)
  @champ.update!(value: computed)
  respond_to { |f| f.turbo_stream { render :reset_formula } }
end
```

### UI éditeur (admin)

Pour tout TDC dont le type répond `supports_init_formula? == true`, afficher un **accordéon discret** dans les options du TDC :

```
▸ Formule d'initialisation (avancé)
  [                                    ]
  Pré-remplit le champ avec une valeur calculée. L'usager pourra la modifier.
```

Réutilise le même éditeur d'autocomplétion que le champ formule (`FormulaAutocompleteController`).

### UI dossier (usager/instructeur)

Le champ reste un input normal. Ajouts visuels :

**Quand non overridé** (valeur calculée) :
```
Montant accordé
┌──────────────────────────────────┐
│ 8 000 €                    🔄   │  ← badge "Valeur calculée"
└──────────────────────────────────┘
```

**Quand overridé** (valeur manuelle) :
```
Montant accordé
┌──────────────────────────────────┐
│ 7 000 €                    ↩️   │  ← bouton "Réinitialiser"
└──────────────────────────────────┘
```

Le bouton réinitialiser déclenche un PATCH Turbo vers `/champs/:id/reset_formula`.

### Validation (FormulaValidator)

Les mêmes règles que pour `formule_expression` :
- Contraintes d'ordre (ne référencer que les champs précédents)
- Validation syntaxique Dentaku
- Détection de cycles (un champ avec init_formula ne peut pas se référencer lui-même via une chaîne)

## Différences avec le champ formule

| | Champ formule | Formule d'initialisation |
|---|---|---|
| Type de champ | `formule` (dédié) | Tout type dont `supports_init_formula? == true` |
| Éditable | Non (read-only) | Oui |
| Expression | `formule_expression` | `init_formula_expression` |
| Recalcul | Toujours | Tant que `formula_overridden` est nil |
| Rendu | Valeur affichée | Input pré-rempli |
| Override | Impossible | Possible + réinitialisable |
| Stockage override | N/A | `value_json.formula_overridden` |
| Reset | N/A | Endpoint dédié `PATCH /champs/:id/reset_formula` |

## Scénarios de test

### Tests unitaires
- [ ] Champ avec init_formula : valeur calculée au callback `before_validation :create`
- [ ] Modification du source → champ init recalculé (non overridé)
- [ ] Override manuel → formula_overridden = true (détection par égalité stricte)
- [ ] Modification du source après override → valeur inchangée
- [ ] Reset via endpoint dédié → formula_overridden = nil → recalcul
- [ ] Transitivité : A → init(B) → formule(C)
- [ ] `supports_init_formula?` false sur types non compatibles
- [ ] Source non persistée au moment du callback → valeur neutre calculée, puis auto-corrigée par refresh

### Tests système
- [ ] Usager voit la valeur pré-calculée dans un input éditable
- [ ] Usager modifie → la valeur est conservée même si la source change
- [ ] Bouton réinitialiser → retour au calcul automatique
- [ ] Instructeur sur annotation avec init_formula (recalcul auto pendant construction, override possible en instruction)
- [ ] Ajout de ligne dans une répétition : champs init calculés à la création
- [ ] Accordéon admin affiché uniquement pour les TDC compatibles

### Cas de répétition (MVP simple)

Calcul à la création de chaque champ enfant d'une nouvelle ligne :
- Siblings précédents (même ligne) : s'ils existent déjà en cache, leur valeur est utilisée ; sinon vides (calcul neutre)
- Parents (hors répétition) : toujours disponibles
- L'optimisation "pré-calculer uniquement si dépendance hors du bloc" est remise à plus tard

Ordre topologique au sein d'une ligne : garanti par l'ordre de création des champs (qui suit l'ordre de la révision) + BFS du `FormulaCalculationService`.

## Points tranchés

1. **Détection override** : égalité stricte, faux positifs compensés par le bouton reset.
2. **Répétitions** : calcul systématique à la création du bloc (MVP simple).
3. **Annotations privées** : aucun traitement spécifique, le mécanisme standard `refresh_dependent_formulas` gère.
4. **Backfill lignes/dossiers existants** : non requis, la création lazy via streaming + callback suffit.
5. **UI admin** : accordéon discret dans les options du TDC.
6. **GraphQL** : pas exposé au MVP (aucun cas d'usage identifié).
7. **Endpoint reset** : route dédiée pour isoler du code upstream.
8. **Nommage du flag** : `formula_overridden` (explicite, lie le flag à la nature du mécanisme).
9. **Compatibilité par type** : prédicat OO `supports_init_formula?` sur `TypeDeChampBase`.

## Comportement GraphQL

### Modification d'un champ source via mutation

La cascade de recalcul est **automatique** et symétrique entre l'UI et GraphQL, grâce au callback `after_save :refresh_dependent_formulas` sur `Champ` (champ.rb:112).

Exemple : `DossierModifierAnnotation` met à jour une annotation privée utilisée comme source d'une formule (publique ou privée).

```
Mutation → annotation.save → after_save :refresh_dependent_formulas
  → graphe de dépendances sur revision.types_de_champ (public + private)
  → BFS topologique
  → FormulaCalculationService pour chaque formule / init_formula dépendante
  → update_column (bypass callbacks, évite cascade infinie)
```

Conséquence : aucune logique spécifique GraphQL à écrire pour l'intégration avec `init_formula`. Il suffit d'étendre `formula_tdcs` (champ.rb:341) pour inclure les TDC avec `init_formula_expression` non overridés, comme prévu dans la section "Intégration avec refresh_dependent_formulas".

### Cas subtil : mutation directe sur un champ avec init_formula

Hors MVP, si une future mutation GraphQL permet de modifier directement un champ avec `init_formula_expression`, la **détection d'override** (égalité stricte valeur soumise vs valeur calculée) doit s'appliquer à cet appel aussi — sinon la valeur est écrasée sans poser le flag `formula_overridden`, et la prochaine modif de source l'écrasera.

Recommandation : à terme, déplacer la détection d'override du controller HTML vers un concern ou un callback AR, pour garantir la cohérence UI/GraphQL/API. Au MVP, la logique reste dans le controller HTML (aucune mutation GraphQL ne cible les types compatibles `init_formula` à date).

## Points ouverts

1. **Création atomique via `insert_all`** : à vérifier avant implémentation. Si utilisée, prévoir un `after_commit` sur `Dossier` en complément du callback `before_validation :create`.
2. **Historique** : tracer les overrides ? → Non pour le MVP, le champ a juste une valeur comme les autres.
3. **Duplication de ligne** (si existe) : le flag `formula_overridden` est-il dupliqué avec la valeur ? → Proposition : oui, on duplique la valeur effective et son état.
4. **Unification détection override** : déplacer à terme du controller HTML vers un callback AR pour couvrir GraphQL et API v2 de façon uniforme.
