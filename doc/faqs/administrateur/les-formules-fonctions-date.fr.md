---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-fonctions-date"
locale: "fr"
keywords: "date, annee, mois, jour, aujourdhui, limitation, non disponible"
title: "Fonctions de date (non disponibles)"
order: 7
---

# Fonctions de date (non disponibles)

⚠️ **Important** : Les fonctions de manipulation de dates ne sont **pas encore implémentées** dans le système de formules.

## Fonctions manquantes

Les fonctions suivantes, courantes dans Excel ou LibreOffice Calc, ne sont **pas disponibles** pour le moment :

### Extraction de composantes de date

| Fonction | Description | Exemple souhaité |
|----------|-------------|------------------|
| `ANNEE(date)` | Extraire l'année d'une date | `ANNEE({Date de naissance})` → 1990 |
| `MOIS(date)` | Extraire le mois d'une date | `MOIS({Date de naissance})` → 5 |
| `JOUR(date)` | Extraire le jour d'une date | `JOUR({Date de naissance})` → 15 |

### Date actuelle

| Fonction | Description | Exemple souhaité |
|----------|-------------|------------------|
| `AUJOURDHUI()` | Date du jour (sans heure) | `AUJOURDHUI()` → 2025-01-04 |
| `MAINTENANT()` | Date et heure actuelles | `MAINTENANT()` → 2025-01-04 14:30:00 |

### Calculs entre dates

| Fonction | Description | Exemple souhaité |
|----------|-------------|------------------|
| `DATEDIF(date1, date2, unité)` | Différence entre deux dates | `DATEDIF({Date début}, {Date fin}, "d")` → nombre de jours |
| `JOURSEM(date)` | Jour de la semaine | `JOURSEM({Date})` → 1 (lundi) |

## Limitation actuelle

Les champs de type **Date** et **Date et heure** sont convertis en **nombres** (timestamp Unix) lors de leur utilisation dans les formules.

Cela signifie :
- ✅ Vous pouvez comparer deux dates numériquement : `{Date 1} > {Date 2}`
- ❌ Vous ne pouvez PAS extraire l'année, le mois ou le jour

**Exemple** :
```
{Date de naissance}
```
Retourne un nombre comme `641865600` (timestamp), pas une date lisible.

## Cas d'usage bloqués

Sans les fonctions de date, les cas d'usage suivants sont **impossibles** :

### ❌ Calcul d'âge

**Formule souhaitée** (non fonctionnelle) :
```
ANNEE(AUJOURDHUI()) - ANNEE({Date de naissance})
```

**Solution de contournement** : Ajouter un champ "Âge" (nombre entier) que l'usager remplit manuellement.

---

### ❌ Calcul d'ancienneté

**Formule souhaitée** (non fonctionnelle) :
```
DATEDIF({Date d'embauche}, AUJOURDHUI(), "y")
```

**Solution de contournement** : Demander directement "Nombre d'années d'ancienneté" (nombre entier).

---

### ❌ Vérification de majorité

**Formule souhaitée** (non fonctionnelle) :
```
SI(ANNEE(AUJOURDHUI()) - ANNEE({Date de naissance}) >= 18, "Majeur", "Mineur")
```

**Solution de contournement** : Ajouter un champ "Âge" (nombre entier) et utiliser :
```
SI({Âge} >= 18, "Majeur", "Mineur")
```

---

### ❌ Calcul de délai

**Formule souhaitée** (non fonctionnelle) :
```
DATEDIF({Date de début}, {Date de fin}, "d")
```

**Solution de contournement** : Demander "Nombre de jours" (nombre entier).

---

### ❌ Vérification de date limite

**Formule souhaitée** (non fonctionnelle) :
```
SI({Date de dépôt} <= {Date limite}, "Dans les temps", "Hors délai")
```

**Solution partielle** : Comparer les timestamps (peu lisible) :
```
SI({Date de dépôt} <= {Date limite}, "Dans les temps", "Hors délai")
```

> **Note** : Cette formule fonctionne, mais les dates sont comparées en tant que nombres, ce qui est peu intuitif pour l'administrateur.

## Solutions de contournement

En attendant l'implémentation des fonctions de date, voici les solutions recommandées :

### 1. Champs de saisie manuelle

Demandez directement les valeurs calculées aux usagers :
- "Âge" (nombre entier) au lieu de calculer depuis la date de naissance
- "Nombre d'années d'ancienneté" au lieu de calculer depuis la date d'embauche
- "Nombre de jours" au lieu de calculer entre deux dates

### 2. Utiliser les sous-propriétés Polynésie

Pour le **Numéro DN**, vous pouvez accéder à la date de naissance :
```
{Numéro DN/date_de_naissance}
```

Mais vous ne pouvez toujours pas extraire l'année, le mois ou le jour.

### 3. Comparaisons de timestamps

Les dates peuvent être comparées numériquement (timestamps) :
```
{Date 1} > {Date 2}
{Date de dépôt} <= {Date limite}
```

## Feuille de route

L'ajout de fonctions de date est **prévu dans une version future**. Les fonctions suivantes devraient être implémentées :

**Priorité haute** :
- `ANNEE()`, `MOIS()`, `JOUR()` : extraction de composantes
- `AUJOURDHUI()` : date du jour

**Priorité moyenne** :
- `DATEDIF()` : calcul de différence entre dates
- `DATE(année, mois, jour)` : construction de date

**Priorité basse** :
- `JOURSEM()`, `NUMSEMAINE()` : informations calendaires

> **💡 Astuce** : En attendant, privilégiez les champs de saisie manuelle pour les informations dérivées de dates.

## Pages associées

- [Introduction aux formules](/faq/administrateur/les-formules-introduction)
- [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques)
- [Fonctions conditionnelles](/faq/administrateur/les-formules-fonctions-conditionnelles)
