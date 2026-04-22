---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-fonctions-date"
locale: "fr"
keywords: "date, annee, mois, jour, aujourdhui, maintenant, age, duree, duration, majorite, anniversaire, delai"
title: "Fonctions de date"
order: 7
---

# Fonctions de date

Les champs de type **Date** et **Date et heure** peuvent être manipulés directement dans les formules comme de véritables dates. Vous disposez de fonctions pour obtenir la date du jour, calculer un âge, vérifier qu'une date est passée ou future, extraire l'année/le mois/le jour, et ajouter ou soustraire une durée.

## Vue d'ensemble

### Date courante

| Fonction | Description | Résultat |
|----------|-------------|----------|
| `AUJOURDHUI()` | Date du jour (sans heure) | `2026-04-19` |
| `MAINTENANT()` | Date et heure courantes | `2026-04-19T15:40:00` |

### Extraction de composantes

| Fonction | Description | Exemple |
|----------|-------------|---------|
| `JOUR(date)` | Jour du mois (1 à 31) | `JOUR({Date de naissance})` → `15` |
| `MOIS(date)` | Mois (1 à 12) | `MOIS({Date de naissance})` → `5` |
| `ANNEE(date)` | Année sur 4 chiffres | `ANNEE({Date de naissance})` → `1990` |
| `JOURSEM(date)` | Jour de la semaine ISO (lundi = 1, dimanche = 7) | `JOURSEM(AUJOURDHUI())` → `1` |

### Comparaison et calcul d'âge

| Fonction | Description | Exemple |
|----------|-------------|---------|
| `AGE(date_de_naissance)` | Âge en années révolues | `AGE({Date de naissance})` → `35` |
| `EST_PASSEE(date)` | `true` si la date est strictement antérieure à aujourd'hui | `EST_PASSEE({Date limite})` |
| `EST_FUTURE(date)` | `true` si la date est strictement postérieure à aujourd'hui | `EST_FUTURE({Date d'échéance})` |

### Durées

Les fonctions de durée se combinent avec une date via les opérateurs `+` et `-` pour produire une nouvelle date.

| Fonction | Description | Exemple |
|----------|-------------|---------|
| `DUREE_ANNEES(n)` | Durée de `n` années | `{Date} + DUREE_ANNEES(18)` → date du 18ᵉ anniversaire |
| `DUREE_MOIS(n)` | Durée de `n` mois | `{Date} + DUREE_MOIS(6)` → date 6 mois plus tard |
| `DUREE_JOURS(n)` | Durée de `n` jours | `{Date} + DUREE_JOURS(30)` → date 30 jours plus tard |

> **Équivalent anglais** : `DURATION(n, years)`, `DURATION(n, months)`, `DURATION(n, days)` donnent le même résultat que leurs équivalents `DUREE_*`. Les deux syntaxes sont interchangeables.

## Arithmétique de dates

Entre deux dates, les opérateurs standards fonctionnent directement :

| Opération | Résultat | Exemple |
|-----------|----------|---------|
| `{Date1} - {Date2}` | Nombre de jours entre les deux dates | `{Date de fin} - {Date de début}` → `42` |
| `{Date1} > {Date2}` | `true` si Date1 est postérieure | `{Date dépôt} > {Date limite}` |
| `{Date} + DUREE_*(n)` | Nouvelle date | `{Date début} + DUREE_JOURS(90)` |
| `{Date} - DUREE_*(n)` | Nouvelle date | `AUJOURDHUI() - DUREE_ANNEES(1)` |

## Cas d'usage

### ✅ Afficher la date du jour

```
AUJOURDHUI()
```

### ✅ Calcul d'âge

```
AGE({Date de naissance})
```

La fonction `AGE` retourne l'âge en **années révolues** : elle tient compte du fait que l'anniversaire a ou non déjà eu lieu cette année. Le résultat est toujours exact (pas d'approximation à 365,25 jours près).

### ✅ Vérification de majorité

```
SI(AGE({Date de naissance}) >= 18, "Majeur", "Mineur")
```

Ou, de manière équivalente, en passant par la date du 18ᵉ anniversaire :

```
SI({Date de naissance} + DUREE_ANNEES(18) <= AUJOURDHUI(), "Majeur", "Mineur")
```

### ✅ Vérification qu'une date est passée

```
EST_PASSEE({Date limite})
```

Équivalent explicite au test `{Date limite} < AUJOURDHUI()` — la version `EST_PASSEE` est plus lisible.

### ✅ Dépôt dans les temps

```
SI({Date de dépôt} <= {Date limite}, "Dans les temps", "Hors délai")
```

### ✅ Calcul de délai (en jours)

```
{Date de fin} - {Date de début}
```

Le résultat est le nombre de jours entre les deux dates. Entier si les deux champs sont des dates simples, nombre décimal si des heures sont impliquées.

### ✅ Date d'échéance à N jours

```
{Date de dépôt} + DUREE_JOURS(90)
```

Utile pour calculer automatiquement une date limite de réponse.

### ✅ Ancienneté en années

```
AGE({Date d'embauche})
```

La fonction `AGE` fonctionne sur n'importe quelle date passée, pas uniquement les dates de naissance.

### ✅ Ajout d'une échéance en mois

```
{Date de début} + DUREE_MOIS(6)
```

### ✅ Anniversaire de la semaine ?

```
SI(JOURSEM({Date anniversaire}) == JOURSEM(AUJOURDHUI()), "Oui", "Non")
```

### ✅ Extraire l'année d'une date

```
ANNEE({Date de dépôt})
```

## Recalcul automatique des formules temporelles

Certaines formules **dépendent du temps qui passe** : `AGE`, `AUJOURDHUI`, `MAINTENANT`, `EST_PASSEE`, `EST_FUTURE`, ou toute formule qui en dérive. Si rien ne les déclenche, leur valeur devient obsolète (un `AGE` calculé l'an dernier vaudra toujours `35` même si la personne est passée à `36` depuis). Le système gère ce cas automatiquement, avec deux règles distinctes selon le type de champ.

### Champs formule visibles par l'usager (publics)

- **Tant que le dossier est en brouillon** : la formule est recalculée automatiquement tous les jours (minuit, heure de Polynésie). Un usager qui revient sur son brouillon quelques mois plus tard voit un âge à jour.
- **Au moment du dépôt** : la valeur est **figée** à ce qu'elle vaut à cet instant.
- **Après le dépôt** : la formule n'est **plus recalculée**, même si un anniversaire passe. C'est l'immutabilité de la demande au dépôt : la condition d'âge (par exemple) est appréciée à la date où le dossier a été soumis.
- **Correction d'une source** : si l'usager corrige un champ source (par exemple la date de naissance) après avoir repassé le dossier en construction, la formule est recalculée. L'immutabilité s'applique au temps qui passe, pas aux corrections de données.

### Annotations privées formule (visibles par l'instructeur)

- Toujours recalculées quotidiennement et à chaque transition d'état du dossier, jusqu'à la décision finale (accepté / refusé / classé sans suite).
- Permettent de suivre des indicateurs vivants type `AUJOURDHUI() - {Date de passage en instruction}` (« nombre de jours en instruction »).

### Transitions d'état

Les formules qui utilisent un timestamp d'état du dossier (`{Date de dépôt}`, `{Date de passage en instruction}`, etc.) sont recalculées **immédiatement** à la transition correspondante — pas besoin d'attendre le lendemain.

## Cas particuliers

### Champs vides

Les fonctions de date sur un **champ vide** ne font pas planter la formule :

- `AGE({Date vide})` → résultat vide (pas d'erreur)
- `EST_PASSEE({Date vide})` → `false`
- `EST_FUTURE({Date vide})` → `false`

Protégez-vous éventuellement avec un `SI` explicite si le comportement par défaut ne vous convient pas.

### Date du jour et fuseau horaire

`AUJOURDHUI()` et `MAINTENANT()` utilisent le fuseau horaire configuré sur mes-demarches.pf (Pacifique/Tahiti). La date est donc celle du calendrier polynésien au moment où la formule est calculée.

### Date et heure vs date seule

`AGE`, `JOUR`, `MOIS`, `ANNEE`, `JOURSEM`, `EST_PASSEE`, `EST_FUTURE` acceptent indifféremment un champ de type **Date** ou **Date et heure** — les champs avec heure sont automatiquement ramenés à leur date (en conservant le jour calendaire local).

## Pages associées

- [Introduction aux formules](/faq/administrateur/les-formules-introduction)
- [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques)
- [Fonctions conditionnelles](/faq/administrateur/les-formules-fonctions-conditionnelles)
- [Fonctions mathématiques](/faq/administrateur/les-formules-fonctions-mathematiques)
