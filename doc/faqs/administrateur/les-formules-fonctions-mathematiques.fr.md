---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-fonctions-mathematiques"
locale: "fr"
keywords: "fonctions, mathématiques, calcul, somme, moyenne, arrondi, min, max"
title: "Fonctions mathématiques"
order: 4
---

# Fonctions mathématiques

Les formules supportent un ensemble de **fonctions mathématiques** pour effectuer des calculs avancés. Chaque fonction est disponible en **français** et en **anglais**.

## Fonctions d'agrégation

### SOMME / SUM

Additionne plusieurs valeurs.

**Syntaxe** :
```
SOMME(valeur1, valeur2, ...)
```

**Exemples** :
```
SOMME({Prix 1}, {Prix 2}, {Prix 3})
```
Si Prix 1 = 100, Prix 2 = 200, Prix 3 = 300 → Résultat : **600**

```
SOMME(50, 75, {Montant})
```
Si Montant = 125 → Résultat : **250**

**Note** : Vous pouvez passer autant de valeurs que nécessaire (2 ou plus).

---

### MOYENNE / AVG

Calcule la moyenne de plusieurs valeurs.

**Syntaxe** :
```
MOYENNE(valeur1, valeur2, ...)
```

**Exemples** :
```
MOYENNE({Note 1}, {Note 2}, {Note 3})
```
Si Note 1 = 12, Note 2 = 15, Note 3 = 18 → Résultat : **15**

```
MOYENNE(10, 20, 30, 40)
```
Résultat : **25**

**Note** : La moyenne est la somme divisée par le nombre de valeurs.

---

### MIN

Retourne la plus petite valeur parmi plusieurs.

**Syntaxe** :
```
MIN(valeur1, valeur2, ...)
```

**Exemples** :
```
MIN({Montant 1}, {Montant 2}, {Montant 3})
```
Si Montant 1 = 500, Montant 2 = 300, Montant 3 = 800 → Résultat : **300**

**Cas d'usage** : Plafonner une valeur
```
MIN({Montant demandé}, 10000)
```
Si Montant demandé = 15000 → Résultat : **10000** (plafond appliqué)
Si Montant demandé = 5000 → Résultat : **5000** (pas de plafonnement)

---

### MAX

Retourne la plus grande valeur parmi plusieurs.

**Syntaxe** :
```
MAX(valeur1, valeur2, ...)
```

**Exemples** :
```
MAX({Score 1}, {Score 2}, {Score 3})
```
Si Score 1 = 50, Score 2 = 75, Score 3 = 60 → Résultat : **75**

**Cas d'usage** : Garantir un montant minimum
```
MAX({Montant calculé}, 100)
```
Si Montant calculé = 50 → Résultat : **100** (minimum garanti)
Si Montant calculé = 200 → Résultat : **200**

---

## Fonctions d'arrondi

### ARRONDI / ROUND

Arrondit un nombre à un nombre de décimales spécifié.

**Syntaxe** :
```
ARRONDI(nombre, [précision])
```

**Paramètres** :
- `nombre` : Le nombre à arrondir
- `précision` (optionnel) : Nombre de décimales (par défaut : 0)

**Exemples** :
```
ARRONDI({Prix}, 2)
```
Si Prix = 15.6789 → Résultat : **15.68**

```
ARRONDI({Montant}, 0)
```
Si Montant = 123.456 → Résultat : **123**

```
ARRONDI({Montant})
```
Si Montant = 123.456 → Résultat : **123** (par défaut, 0 décimale)

**Cas d'usage** : Arrondir le nombre de cartons nécessaires
```
ARRONDI({Nombre de pièces} / 30, 0)
```
Si Nombre de pièces = 250 → Résultat : **8** cartons

---

### ARRONDI_INF / FLOOR

Arrondit un nombre vers le bas (vers zéro).

**Syntaxe** :
```
ARRONDI_INF(nombre)
```

**Exemples** :
```
ARRONDI_INF({Prix})
```
Si Prix = 15.9 → Résultat : **15**

```
ARRONDI_INF(8.7)
```
Résultat : **8**

---

### ARRONDI_SUP / CEILING

Arrondit un nombre vers le haut (s'éloigne de zéro).

**Syntaxe** :
```
ARRONDI_SUP(nombre)
```

**Exemples** :
```
ARRONDI_SUP({Prix})
```
Si Prix = 15.1 → Résultat : **16**

```
ARRONDI_SUP(8.01)
```
Résultat : **9**

**Cas d'usage** : Calculer le nombre de cartons nécessaires (toujours arrondir au supérieur)
```
ARRONDI_SUP({Nombre de pièces} / 30)
```
Si Nombre de pièces = 250 → Résultat : **9** cartons (pas 8.33)

---

## Fonctions de valeur absolue et signe

### ABS

Retourne la valeur absolue d'un nombre (distance à zéro).

**Syntaxe** :
```
ABS(nombre)
```

**Exemples** :
```
ABS({Différence})
```
Si Différence = -50 → Résultat : **50**
Si Différence = 50 → Résultat : **50**

**Cas d'usage** : Calculer un écart sans se soucier du signe
```
ABS({Montant prévu} - {Montant réel})
```
Si Montant prévu = 1000 et Montant réel = 1200 → Résultat : **200**
Si Montant prévu = 1000 et Montant réel = 800 → Résultat : **200**

---

## Fonctions exponentielles et racines

### POW / PUISSANCE

Élève un nombre à une puissance.

**Syntaxe** :
```
POW(base, exposant)
```

**Exemples** :
```
POW(2, 3)
```
Résultat : **8** (2³)

```
POW({Rayon}, 2) * 3.14159
```
Si Rayon = 5 → Résultat : **78.54** (approximation de πr²)

---

### SQRT

Calcule la racine carrée d'un nombre.

**Syntaxe** :
```
SQRT(nombre)
```

**Exemples** :
```
SQRT(16)
```
Résultat : **4**

```
SQRT({Surface})
```
Si Surface = 100 → Résultat : **10**

---

## Opérations avancées

### Modulo (%)

Retourne le reste de la division entière.

**Syntaxe** :
```
nombre1 % nombre2
```

**Exemples** :
```
10 % 3
```
Résultat : **1** (10 ÷ 3 = 3 reste 1)

```
{Nombre} % 2
```
Si Nombre = 7 → Résultat : **1** (impair)
Si Nombre = 8 → Résultat : **0** (pair)

**Cas d'usage** : Vérifier si un nombre est pair ou impair
```
SI({Nombre} % 2 = 0, "Pair", "Impair")
```

---

## Exemples combinés

### Calcul de remise progressive

```
SI({Montant} > 10000, {Montant} * 0.9, SI({Montant} > 5000, {Montant} * 0.95, {Montant}))
```
- Montant > 10000 → 10% de remise
- Montant > 5000 → 5% de remise
- Sinon → pas de remise

### Plafonnement avec minimum garanti

```
MIN(MAX({Montant}, 500), 10000)
```
- Minimum : 500
- Maximum : 10000

### Surface d'un cercle

```
ARRONDI(POW({Rayon}, 2) * 3.14159, 2)
```
Calcule πr² arrondi à 2 décimales.

### Nombre de jours ouvrés (approximation)

```
ARRONDI({Nombre de jours} * 5 / 7, 0)
```
Estime le nombre de jours ouvrés (5 jours sur 7).

---

## Noms français et anglais

Toutes les fonctions mathématiques ont des alias en français et en anglais :

| Français | Anglais |
|----------|---------|
| `SOMME` | `SUM` |
| `MOYENNE` | `AVG` |
| `ARRONDI` | `ROUND` |
| `ARRONDI_INF` | `FLOOR` |
| `ARRONDI_SUP` | `CEILING` |
| `PUISSANCE` | `POW` |

Vous pouvez utiliser indifféremment la version française ou anglaise :
```
SOMME({Prix 1}, {Prix 2})  ← version française
SUM({Prix 1}, {Prix 2})    ← version anglaise (identique)
```

---

## Pages associées

- [Introduction aux formules](/faq/administrateur/les-formules-introduction)
- [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques)
- [Fonctions conditionnelles](/faq/administrateur/les-formules-fonctions-conditionnelles)
- [Fonctions texte](/faq/administrateur/les-formules-fonctions-texte)
