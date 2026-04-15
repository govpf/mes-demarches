---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-introduction"
locale: "fr"
keywords: "formules, calcul automatique, champs calculés, référence, syntaxe"
title: "Introduction aux formules"
order: 1
---

# Introduction aux formules

Les **formules** permettent de créer des champs calculés automatiquement dans vos démarches. Au lieu de demander à l'usager de calculer manuellement un montant total ou un résultat, la formule effectue le calcul pour vous en se basant sur les valeurs saisies dans d'autres champs.

## Qu'est-ce qu'une formule ?

Une formule est un **champ spécial** qui affiche le résultat d'un calcul basé sur :
- Les valeurs d'autres champs du formulaire
- Des constantes (nombres, textes)
- Des opérations mathématiques ou logiques

**Exemple simple** : Calculer un prix TTC à partir d'un prix HT

```
{Prix HT} * 1.16
```

## Syntaxe de base

### Référencer un champ

Pour référencer la valeur d'un autre champ dans votre formule, utilisez son **libellé** entre accolades :

```
{Nom du champ}
```

**Exemples** :
- `{Montant HT}`
- `{Quantité}`
- `{Prix unitaire}`

## Opérateurs mathématiques

Les formules supportent les opérateurs arithmétiques standards :

| Opérateur | Description | Exemple |
|-----------|-------------|---------|
| `+` | Addition | `{Prix 1} + {Prix 2}` |
| `-` | Soustraction | `{Montant} - {Réduction}` |
| `*` | Multiplication | `{Quantité} * {Prix unitaire}` |
| `/` | Division | `{Total} / {Nombre de parts}` |
| `%` | Modulo (reste) | `{Nombre} % 2` |

### Priorité des opérations

Les règles mathématiques classiques s'appliquent :
1. Parenthèses : `( )`
2. Multiplication, Division, Modulo : `*`, `/`, `%`
3. Addition, Soustraction : `+`, `-`

**Exemple** :
```
({Prix HT} + {Frais de port}) * 1.16
```

## Ordre d'évaluation des champs

**⚠️ Règle importante** : Une formule ne peut référencer **que les champs qui la précèdent** dans le formulaire.

**Structure valide** :
```
1. Montant HT (nombre)
2. Taux TVA (nombre)
3. Prix TTC (formule) → {Montant HT} * (1 + {Taux TVA} / 100)
```

**Structure invalide** :
```
1. Prix TTC (formule) → ❌ Ne peut pas référencer {Montant HT}
2. Montant HT (nombre)
```

> **💡 Conseil** : Placez toujours vos champs de formule **après** les champs dont ils dépendent.

## Métadonnées du dossier

> **📌 À venir** : La possibilité d'utiliser des métadonnées du dossier (numéro, dates, informations usager/entreprise) dans les formules sera documentée prochainement.

## Sous-propriétés spécifiques Polynésie française

Certains champs spécifiques à la Polynésie française offrent des **sous-propriétés** accessibles dans les formules.

### Numéro DN (Date de Naissance)

Le champ **Numéro DN** contient plusieurs informations. Vous pouvez extraire la date de naissance :

```
{Numéro DN/date_de_naissance}
```

**Référence complète** :
- `{Numéro DN}` → Numéro complet (8 chiffres)
- `{Numéro DN/date_de_naissance}` → Date de naissance extraite

### Code postal de Polynésie

Le champ **Code postal de Polynésie** offre :

```
{Code postal/commune}    → Nom de la commune
{Code postal/ile}        → Nom de l'île
{Code postal/archipel}   → Nom de l'archipel
```

**Exemple** : Afficher l'île du demandeur
```
CONCAT("Résidence : ", {Code postal/ile})
```
→ Affiche : "Résidence : Tahiti"

### Référentiels de Polynésie

Les champs **Référentiel de Polynésie** (tables externes TeFeNua) offrent l'accès aux colonnes de la table :

```
{Nom du champ/Nom de la colonne}
```

**Exemple** : Table "Parcelles cadastrales"
```
{Parcelle/Surface}     → Surface de la parcelle sélectionnée
{Parcelle/Section}     → Section cadastrale
```

### SIRET de Polynésie

Le champ **SIRET de Polynésie** offre :

```
{SIRET/raison_sociale}     → Raison sociale
{SIRET/forme_juridique}    → Forme juridique
{SIRET/adresse}            → Adresse
```

## Types de champs supportés

Les formules peuvent utiliser différents types de champs comme source :

| Type de champ | Valeur dans la formule | Exemple |
|---------------|------------------------|---------|
| Nombre entier | Nombre | `{Quantité}` → 10 |
| Nombre décimal | Nombre | `{Prix}` → 15.50 |
| Texte | Chaîne | `{Nom}` → "Dupont" |
| Oui/Non | Booléen (0 ou 1) | `{Accepté}` → 1 |
| Date | Timestamp | `{Date de naissance}` → nombre |

> **⚠️ Limitation** : Les fonctions de manipulation de dates (ANNEE, MOIS, JOUR) ne sont **pas encore disponibles**. Voir [Fonctions de date](#).

## Exemples rapides

Besoin d'un exemple concret tout de suite ? Consultez la page [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques) qui présente des cas d'usage courants :

- Calcul de TVA
- Prix TTC
- Éligibilité conditionnelle
- Total plafonné
- Concaténation de textes
- Et bien plus...

## Fonctions avancées

Les formules supportent de nombreuses **fonctions** pour effectuer des calculs complexes :

### Fonctions mathématiques
- `SOMME()`, `MOYENNE()`, `MIN()`, `MAX()` : opérations sur plusieurs valeurs
- `ARRONDI()`, `ABS()` : arrondi et valeur absolue
- [En savoir plus →](/faq/administrateur/les-formules-fonctions-mathematiques)

### Fonctions conditionnelles
- `SI(condition, vrai, faux)` : logique conditionnelle
- `ET()`, `OU()`, `NON()` : fonctions logiques
- [En savoir plus →](/faq/administrateur/les-formules-fonctions-conditionnelles)

### Fonctions texte
- `CONCAT()`, `LEFT()`, `RIGHT()` : manipulation de chaînes
- `LEN()` : longueur d'une chaîne
- [En savoir plus →](/faq/administrateur/les-formules-fonctions-texte)

### Fonctions de date
⚠️ **Non disponibles** pour le moment.
- [En savoir plus →](/faq/administrateur/les-formules-fonctions-date)

## Formules dans les blocs répétables

Les formules peuvent être utilisées dans des **blocs répétables** pour calculer des valeurs sur chaque ligne indépendamment.

**Exemple** : Calculer le sous-total de chaque produit dans une facture
```
Bloc "Produits" :
- Quantité (nombre)
- Prix unitaire (nombre)
- Sous-total (formule) → {Quantité} * {Prix unitaire}
```

Chaque ligne calculera son propre sous-total.

[En savoir plus sur les formules dans les répétitions →](/faq/administrateur/les-formules-dans-les-repetitions)

## Bonnes pratiques

### ✅ À faire
- **Nommer clairement** vos champs : "Prix HT", "Montant TTC", etc.
- **Placer les formules après** les champs dont elles dépendent
- **Tester** vos formules avec des valeurs réalistes
- **Utiliser les libellés** plutôt que les identifiants techniques

### ❌ À éviter
- Créer des **dépendances circulaires** (A dépend de B qui dépend de A)
- Utiliser des champs qui **suivent** la formule dans l'ordre du formulaire
- Oublier les **parenthèses** dans les calculs complexes
- Référencer des champs **non remplis** (vérifier avec `SI()`)

## Aide supplémentaire

- **Erreur dans votre formule ?** L'éditeur affiche un message d'erreur avec la syntaxe attendue.
- **Résultat inattendu ?** Vérifiez l'ordre de vos champs et les parenthèses dans vos calculs.
- **Champ non disponible ?** Assurez-vous qu'il précède la formule dans le formulaire.

## Pages associées

- [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques)
- [Fonctions mathématiques](/faq/administrateur/les-formules-fonctions-mathematiques)
- [Fonctions conditionnelles](/faq/administrateur/les-formules-fonctions-conditionnelles)
- [Fonctions texte](/faq/administrateur/les-formules-fonctions-texte)
- [Fonctions de date (non disponibles)](/faq/administrateur/les-formules-fonctions-date)
- [Formules dans les blocs répétables](/faq/administrateur/les-formules-dans-les-repetitions)
