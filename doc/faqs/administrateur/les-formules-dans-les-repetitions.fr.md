---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-dans-les-repetitions"
locale: "fr"
keywords: "formules, répétitions, blocs répétables, lignes, tableau"
title: "Utiliser les formules dans les blocs répétables"
order: 3
---

# Utiliser les formules dans les blocs répétables

Les formules peuvent être placées dans les **blocs répétables** pour calculer automatiquement des valeurs sur chaque ligne. C'est particulièrement utile pour les factures, les listes de produits, ou tout formulaire nécessitant des calculs sur plusieurs éléments.

## Principe de fonctionnement

Une formule dans un bloc répétable peut référencer :
- ✅ **Les champs de la même ligne** (qui la précèdent dans l'ordre)
- ✅ **Les champs globaux** (situés hors du bloc répétable)

**Important** : Chaque ligne calcule **indépendamment** son résultat. Une formule ne peut pas accéder aux valeurs d'autres lignes.

## Exemple 1 : Facture de produits

### Structure du formulaire

**Bloc répétable "Produits"** :
1. `Quantité` (nombre entier)
2. `Prix unitaire HT` (nombre décimal)
3. `Sous-total TTC` (formule)

### Formule

```
{Quantité} * {Prix unitaire HT} * 1.16
```

### Résultat

| Quantité | Prix unitaire HT | Sous-total TTC |
|----------|------------------|----------------|
| 10 | 50 | 580 |
| 5 | 100 | 580 |
| 2 | 250 | 580 |

Chaque ligne calcule son propre sous-total avec la TVA de 16%.

## Exemple 2 : Référencer un champ global

### Structure du formulaire

**Champ global** (hors du bloc) :
- `Taux de remise global` (nombre entier) : 10

**Bloc répétable "Articles"** :
1. `Quantité` (nombre entier)
2. `Prix unitaire` (nombre décimal)
3. `Prix après remise` (formule)

### Formule

```
{Quantité} * {Prix unitaire} * (1 - {Taux de remise global} / 100)
```

### Résultat

Le `{Taux de remise global}` sera **le même pour toutes les lignes** du bloc répétable.

| Quantité | Prix unitaire | Prix après remise |
|----------|---------------|-------------------|
| 10 | 50 | 450 (remise de 10%) |
| 5 | 100 | 450 (remise de 10%) |

## Exemple 3 : Éligibilité conditionnelle

### Structure du formulaire

**Bloc répétable "Demandes"** :
1. `Montant demandé` (nombre décimal)
2. `Éligibilité` (formule)

### Formule

```
SI({Montant demandé} <= 5000, "OK", "Trop élevé")
```

### Résultat

| Montant demandé | Éligibilité |
|-----------------|-------------|
| 3000 | OK |
| 7000 | Trop élevé |
| 4500 | OK |

Chaque ligne affiche son propre statut d'éligibilité.

## ⚠️ Éviter les collisions de noms

**Problème** : Si un champ porte le **même nom** dans la ligne ET au niveau global, la formule utilisera la **valeur de la ligne** en priorité.

### Exemple de collision

**Champ global** :
- `Prix` (nombre décimal) : 100

**Bloc répétable "Produits"** :
- `Prix` (nombre décimal)
- `Total` (formule) : `{Prix} * 2`

→ La formule utilisera le `Prix` **de la ligne**, pas le prix global !

### Bonne pratique ✅

Nommer différemment les champs :
- `Prix de référence` (global)
- `Prix du produit` (dans la ligne)

Ainsi, vous pouvez référencer les deux sans ambiguïté :
```
{Prix du produit} * {Prix de référence}
```

## Limitations

### ❌ Ce qui n'est PAS possible

- **Référencer d'autres lignes** : Une formule ne peut pas accéder aux valeurs d'une autre ligne.
  - Exemple impossible : `{Quantité de la ligne 1} + {Quantité de la ligne 2}`

- **Agréger toutes les lignes** : Les fonctions d'agrégation (SOMME, MOYENNE, etc.) seront bientôt disponibles.
  - Pour l'instant, demandez à l'usager de saisir manuellement le total (voir ci-dessous).

- **Référencer des champs suivants** : Une formule ne peut référencer que les champs qui la **précèdent** dans l'ordre de la ligne.

### ✅ Ce qui EST possible

- **Référencer les champs précédents de la ligne**
- **Référencer tous les champs globaux** (hors du bloc)
- **Utiliser des fonctions** : `SI()`, `SOMME()`, `MIN()`, `MAX()`, etc.

## Total général hors du bloc

> **📌 À venir** : Des fonctions d'agrégation seront bientôt disponibles pour calculer automatiquement le total de toutes les lignes (SOMME, MOYENNE, etc.).

**Solution de contournement actuelle** :
Demander à l'usager de saisir manuellement le total général dans un champ séparé (hors du bloc).

**Exemple** :

Structure :
1. Bloc répétable "Produits" (avec sous-totaux calculés)
2. **Champ hors du bloc** : `Total général` (nombre décimal, saisi manuellement)

L'usager devra additionner les sous-totaux et saisir le résultat dans "Total général".

## Cas d'usage courants

### Factures
- Calculer le sous-total de chaque ligne (quantité × prix)
- Appliquer une remise globale sur chaque ligne
- Calculer la TVA par ligne

### Listes de bénéficiaires
- Vérifier l'éligibilité de chaque personne selon des critères
- Calculer le montant d'aide individuel

### Inventaires
- Calculer la valeur de chaque article (quantité × valeur unitaire)
- Appliquer un coefficient de dépréciation

### Demandes de remboursement
- Calculer le montant remboursable par ligne (avec plafond)
- Vérifier les montants par rapport à des seuils

## Bonnes pratiques

### ✅ À faire
- **Nommer clairement** vos champs globaux (ex: "Taux de TVA global")
- **Éviter les noms identiques** entre champs globaux et champs de ligne
- **Placer les formules en dernier** dans l'ordre des champs de la ligne
- **Tester** avec plusieurs lignes pour vérifier le comportement

### ❌ À éviter
- Utiliser le même nom pour un champ global et un champ de ligne
- Essayer de référencer d'autres lignes du bloc
- Placer une formule avant les champs dont elle dépend

## Pages associées

- [Introduction aux formules](/faq/administrateur/les-formules-introduction)
- [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques)
- [Fonctions mathématiques](/faq/administrateur/les-formules-fonctions-mathematiques)
- [Fonctions conditionnelles](/faq/administrateur/les-formules-fonctions-conditionnelles)
- [Les blocs répétables](/faq/administrateur/les-blocs-repetables)
