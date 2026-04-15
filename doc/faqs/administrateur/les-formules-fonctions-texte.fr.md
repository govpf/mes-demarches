---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-fonctions-texte"
locale: "fr"
keywords: "fonctions, texte, concat, left, right, len, mid, chaîne"
title: "Fonctions texte"
order: 6
---

# Fonctions texte

Les **fonctions texte** permettent de manipuler des chaînes de caractères : concaténer, extraire des sous-chaînes, mesurer la longueur, etc.

Les fonctions texte sont disponibles en **français** et en **anglais**.

## CONCATENER / CONCAT

Concatène (assemble) plusieurs chaînes de caractères.

**Syntaxe** :
```
CONCATENER(texte1, texte2, ...)
CONCAT(texte1, texte2, ...)
```

**Exemples** :

**Assembler prénom et nom** :
```
CONCAT({Prénom}, " ", {Nom})
```
- Si Prénom = "Jean" et Nom = "Dupont"
- Résultat : **"Jean Dupont"**

**Message personnalisé** :
```
CONCAT("Demande de ", {Prénom}, " ", {Nom}, " depuis ", {Code postal/commune})
```
- Résultat : **"Demande de Jean Dupont depuis Papeete"**

**Note** : Vous pouvez concaténer autant de valeurs que nécessaire (2 ou plus).

---

## GAUCHE / LEFT

Extrait les **N premiers caractères** d'une chaîne.

**Syntaxe** :
```
GAUCHE(texte, nombre)
LEFT(texte, nombre)
```

**Paramètres** :
- `texte` : La chaîne source
- `nombre` : Nombre de caractères à extraire

**Exemples** :

**Extraire les 2 premiers caractères** :
```
LEFT({Code postal}, 2)
```
- Si Code postal = "98713"
- Résultat : **"98"**

**Initiale du prénom** :
```
LEFT({Prénom}, 1)
```
- Si Prénom = "Marie"
- Résultat : **"M"**

**Préfixe de référence** :
```
CONCAT(LEFT({Code}, 3), "-", {Numéro})
```
- Si Code = "ABC123" et Numéro = 456
- Résultat : **"ABC-456"**

---

## DROITE / RIGHT

Extrait les **N derniers caractères** d'une chaîne.

**Syntaxe** :
```
DROITE(texte, nombre)
RIGHT(texte, nombre)
```

**Paramètres** :
- `texte` : La chaîne source
- `nombre` : Nombre de caractères à extraire

**Exemples** :

**Extraire les 4 derniers chiffres** :
```
RIGHT({SIRET}, 4)
```
- Si SIRET = "12345678901234"
- Résultat : **"1234"**

**Suffixe d'un code** :
```
RIGHT({Code postal}, 3)
```
- Si Code postal = "98713"
- Résultat : **"713"**

---

## STXT / MID

Extrait une **sous-chaîne** à partir d'une position donnée.

**Syntaxe** :
```
STXT(texte, départ, longueur)
MID(texte, départ, longueur)
```

**Paramètres** :
- `texte` : La chaîne source
- `départ` : Position du premier caractère (commence à 1)
- `longueur` : Nombre de caractères à extraire

**Exemples** :

**Extraire le milieu d'un code** :
```
MID({Code}, 3, 2)
```
- Si Code = "ABCDE"
- Résultat : **"CD"** (caractères 3 et 4)

**Extraire une partie d'un SIRET** :
```
MID({SIRET}, 1, 9)
```
- Si SIRET = "12345678901234"
- Résultat : **"123456789"** (SIREN)

**Note** : La position commence à **1** (pas 0 comme dans certains langages de programmation).

---

## NBCAR / LEN

Retourne la **longueur** (nombre de caractères) d'une chaîne.

**Syntaxe** :
```
NBCAR(texte)
LEN(texte)
```

**Exemples** :

**Compter le nombre de caractères** :
```
LEN({Nom})
```
- Si Nom = "Dupont"
- Résultat : **6**

**Vérifier qu'un champ n'est pas vide** :
```
SI(LEN({Commentaire}) > 0, "Rempli", "Vide")
```
- Si Commentaire = "Bonjour"
- Résultat : **"Rempli"**

**Vérifier la longueur d'un code** :
```
SI(LEN({Code postal}) = 5, "OK", "Erreur")
```
- Si Code postal = "98713"
- Résultat : **"OK"**

---

## Exemples combinés

### Initiales

Afficher les initiales d'une personne :
```
CONCAT(LEFT({Prénom}, 1), ".", LEFT({Nom}, 1), ".")
```
- Si Prénom = "Jean" et Nom = "Dupont"
- Résultat : **"J.D."**

---

### Validation de longueur

Vérifier qu'un code a exactement 8 caractères :
```
SI(LEN({Code}) = 8, "Valide", "Invalide")
```
- Si Code = "ABC12345"
- Résultat : **"Valide"**
- Si Code = "ABC"
- Résultat : **"Invalide"**

---

### Masquer une partie d'un SIRET

Afficher seulement les 4 premiers et 4 derniers chiffres :
```
CONCAT(LEFT({SIRET}, 4), "******", RIGHT({SIRET}, 4))
```
- Si SIRET = "12345678901234"
- Résultat : **"1234******1234"**

---

### Extraire le SIREN d'un SIRET

Un SIRET contient 14 chiffres : les 9 premiers sont le SIREN.
```
LEFT({SIRET}, 9)
```
- Si SIRET = "12345678901234"
- Résultat : **"123456789"** (SIREN)

---

## Conversion nombre → texte

Les nombres sont **automatiquement convertis** en texte lors de la concaténation :

```
CONCAT("Montant : ", {Prix}, " €")
```
- Si Prix = 1500
- Résultat : **"Montant : 1500 €"**

---

## Fonctions supplémentaires

### CHERCHE

Recherche la position d'un texte dans un autre (insensible à la casse). Retourne 0 si non trouvé.

**Syntaxe** : `CHERCHE(recherche, texte)` ou `CHERCHE(recherche, texte, position_départ)`

```
CHERCHE("jour", "Bonjour")    → 4
CHERCHE("xyz", "Bonjour")     → 0
```

### SUBSTITUE

Remplace toutes les occurrences d'un texte par un autre.

**Syntaxe** : `SUBSTITUE(texte, ancien, nouveau)`

```
SUBSTITUE("Bonjour monde", "monde", "terre")    → "Bonjour terre"
```

### MAJUSCULE / MINUSCULE

Convertit en majuscules ou minuscules.

```
MAJUSCULE("bonjour")    → "BONJOUR"
MINUSCULE("BONJOUR")    → "bonjour"
```

### SUPPRESPACE

Supprime les espaces en début/fin et réduit les espaces multiples.

```
SUPPRESPACE("  bon   jour  ")    → "bon jour"
```

---

## Récapitulatif des alias français / anglais

| Français | Anglais | Description |
|----------|---------|-------------|
| CONCATENER | CONCAT | Assembler des textes |
| GAUCHE | LEFT | Premiers caractères |
| DROITE | RIGHT | Derniers caractères |
| STXT | MID | Sous-chaîne |
| NBCAR | LEN | Longueur |
| CHERCHE | - | Rechercher position |
| SUBSTITUE | - | Remplacer du texte |
| MAJUSCULE | - | Convertir en majuscules |
| MINUSCULE | - | Convertir en minuscules |
| SUPPRESPACE | - | Nettoyer les espaces |

---

## Cas d'usage courants

### Codes et références
- Créer des références : `CONCAT("REF-", {Numéro})`
- Extraire des parties de codes : `LEFT({Code}, 3)`
- Valider des formats : `SI(LEN({Code}) = 8, "OK", "KO")`

### Identité
- Nom complet : `CONCAT({Prénom}, " ", {Nom})`
- Initiales : `CONCAT(LEFT({Prénom}, 1), ".", LEFT({Nom}, 1), ".")`

### SIRET/SIREN
- Extraire le SIREN : `LEFT({SIRET}, 9)`
- Masquer une partie : `CONCAT(LEFT({SIRET}, 4), "******", RIGHT({SIRET}, 4))`

### Messages personnalisés
- `CONCAT("Demande de ", {Nom}, " validée")`
- `CONCAT("Montant : ", {Prix}, " €")`

---

## Bonnes pratiques

### ✅ À faire
- **Utiliser les noms français ou anglais** selon votre préférence
- **Tester** les extractions avec différentes longueurs de chaînes
- **Combiner** avec des fonctions conditionnelles pour valider les formats

### ❌ À éviter
- Oublier que les positions commencent à **1** (pas 0)
- Supposer que les dates sont des chaînes formatées (ce sont des timestamps)

---

## Pages associées

- [Introduction aux formules](/faq/administrateur/les-formules-introduction)
- [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques)
- [Fonctions mathématiques](/faq/administrateur/les-formules-fonctions-mathematiques)
- [Fonctions conditionnelles](/faq/administrateur/les-formules-fonctions-conditionnelles)
