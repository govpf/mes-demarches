# Spec : Formule d'initialisation (valeur par défaut dynamique)

## Contexte

Inspiré de Grist, une formule d'initialisation permet de pré-remplir un champ avec une valeur calculée tout en laissant l'usager ou l'instructeur la modifier. C'est un pont entre les formules (read-only, recalculées) et les valeurs par défaut (statiques).

## Cas d'usage

- **Nom du demandeur** : `CONCATENER({Prénom}, " ", {Nom})` sur un champ texte → l'instructeur peut corriger
- **Première tranche** : `{Montant total} * 0.3` sur un champ nombre → modifiable par la commission
- **Date limite** : date de dépôt + 30 jours sur un champ date → ajustable par l'instructeur
- **Montant accordé** : `{Montant demandé} * 0.8` en annotation → la commission décide du montant final

## Principe

Ce n'est **pas** un nouveau type de champ. C'est une **option** sur les types existants (`text`, `integer_number`, `decimal_number`, `date`, `textarea`, etc.). Un champ avec une formule d'initialisation reste éditable — il a juste une valeur par défaut dynamique.

## Modèle de données

### TypeDeChamp (options JSON)

```ruby
store_accessor :options, :init_formula_expression
```

Tout TDC compatible qui a `init_formula_expression` rempli bénéficie du mécanisme. Pas de nouveau type, pas de migration.

### Champ (value_json JSONB existant)

```ruby
store_accessor :value_json, :formula_overridden
```

- `formula_overridden` nil ou absent → la valeur est recalculée quand les sources changent
- `formula_overridden` truthy → la valeur est figée, l'usager/instructeur a pris la main

Aucune migration nécessaire. `value_json` est un JSONB existant sur `champs`. Seuls les champs avec un override stockent cette clé (99.9% des champs n'ont rien).

### Types de champ compatibles

Les types qui acceptent une formule d'initialisation :
- `text`, `textarea` (résultat texte)
- `integer_number`, `decimal_number` (résultat numérique)
- `date` (résultat date)

Les types incompatibles (pièces jointes, cartes, répétitions, etc.) n'affichent pas l'option.

## Cycle de vie

### Phase 1 : Initialisation

```
Usager ouvre le formulaire
  → champ B a une init_formula_expression
  → B.value est vide ET formula_overridden est nil
  → store_computed_value calcule la formule et pré-remplit B
  → UI affiche la valeur dans un input éditable + badge "Valeur calculée"
```

### Phase 2 : Recalcul automatique (tant que non overridé)

```
Usager modifie champ A (source de la formule de B)
  → refresh_dependent_formulas détecte B comme dépendant
  → B.formula_overridden est nil → recalcul autorisé
  → B.value est mis à jour avec la nouvelle valeur calculée
  → Turbo Stream re-render B avec la nouvelle valeur
```

### Phase 3 : Override par l'usager/instructeur

```
Usager modifie manuellement B (change "1200" en "1500")
  → Le controller détecte que la valeur soumise ≠ valeur calculée
  → B.formula_overridden = true
  → B.value = "1500"
```

### Phase 4 : Gel après override

```
Usager modifie A → refresh_dependent_formulas détecte B
  → B.formula_overridden est true → skip
  → B garde sa valeur "1500"
```

### Phase 5 : Reset (retour au calcul automatique)

```
Usager clique sur "Réinitialiser la valeur calculée"
  → B.formula_overridden = nil
  → B.value recalculé depuis la formule
  → Badge "Valeur calculée" réapparaît
```

## Implémentation

### Détection de l'override (controller)

Dans `update_dossier_and_compute_errors`, après le save du champ :

```ruby
if champ.type_de_champ.init_formula_expression.present?
  # Si l'usager a modifié la valeur ET qu'elle diffère du calcul
  if champ.saved_change_to_value? && !champ.formula_overridden
    calculated = FormulaCalculationService.new(dossier).compute_init_value(champ)
    champ.formula_overridden = true if champ.value != calculated
  end
end
```

### Intégration avec refresh_dependent_formulas

`all_dependent_formula_champs` doit aussi retourner les champs avec `init_formula_expression` qui dépendent du champ source :

```ruby
# Dans le graphe de dépendances, inclure les TDCs avec init_formula_expression
formula_tdcs = dossier.revision.types_de_champ.filter { _1.formule? || _1.init_formula_expression.present? }
```

Et dans la boucle de recalcul, skipper les overridés :

```ruby
all_dependent_formula_champs.each do |champ|
  # Skip les champs d'init overridés
  next if champ.type_de_champ.init_formula_expression.present? && champ.formula_overridden
  
  # ... recalcul normal
end
```

### FormulaCalculationService

Pas de changement majeur. Le service calcule indifféremment `formule_expression` (champ formule) ou `init_formula_expression` (champ avec init). Le dispatcher choisit la bonne expression :

```ruby
def expression_for(champ)
  if champ.type_de_champ.formule?
    champ.type_de_champ.formule_expression
  else
    champ.type_de_champ.init_formula_expression
  end
end
```

### UI éditeur (admin)

Dans les options du TDC (pour les types compatibles), un champ optionnel :

```
Formule d'initialisation (optionnel)
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

Le bouton réinitialiser :
- Remet `formula_overridden = nil`
- Recalcule la valeur depuis la formule
- Requête Turbo (PATCH) vers le controller

### Validation (FormulaValidator)

Les mêmes règles que pour `formule_expression` :
- Contraintes d'ordre (ne référencer que les champs précédents)
- Validation syntaxique Dentaku
- Détection de cycles (un champ avec init_formula ne peut pas se référencer lui-même via une chaîne)

## Différences avec le champ formule

| | Champ formule | Formule d'initialisation |
|---|---|---|
| Type de champ | `formule` (dédié) | Tout type compatible |
| Éditable | Non (read-only) | Oui |
| Expression | `formule_expression` | `init_formula_expression` |
| Recalcul | Toujours | Tant que `formula_overridden` est nil |
| Rendu | Valeur affichée | Input pré-rempli |
| Override | Impossible | Possible + réinitialisable |
| Stockage override | N/A | `value_json.formula_overridden` |

## Scénarios de test

### Tests unitaires
- [ ] Champ avec init_formula : valeur calculée au premier accès
- [ ] Modification du source → champ init recalculé (non overridé)
- [ ] Override manuel → formula_overridden = true
- [ ] Modification du source après override → valeur inchangée
- [ ] Reset → formula_overridden = nil → recalcul
- [ ] Transitivité : A → init(B) → formule(C)

### Tests système
- [ ] Usager voit la valeur pré-calculée dans un input éditable
- [ ] Usager modifie → la valeur est conservée même si la source change
- [ ] Bouton réinitialiser → retour au calcul automatique
- [ ] Instructeur sur annotation avec init_formula

## Points ouverts

1. **Conflit init + valeur par défaut statique** : si un TDC a à la fois une `default_value` et une `init_formula_expression`, laquelle prime ? → La formule d'init prime.
2. **Blocs répétables** : une formule d'init dans une répétition fonctionne-t-elle ligne par ligne ? → Oui, même mécanique que les formules classiques avec `row_id`.
3. **Export** : exporter la valeur effective (qu'elle soit calculée ou overridée) → c'est déjà le cas puisque `value` contient la valeur.
4. **Historique** : tracer les overrides ? → Non pour le MVP, le champ a juste une valeur comme les autres.
5. **API GraphQL** : exposer `formula_overridden` ? → Pas dans le MVP, la valeur suffit.
