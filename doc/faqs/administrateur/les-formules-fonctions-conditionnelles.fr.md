---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-fonctions-conditionnelles"
locale: "fr"
keywords: "fonctions, conditionnelles, si, if, et, ou, non, logique"
title: "Fonctions conditionnelles"
order: 5
---

# Fonctions conditionnelles

Les **fonctions conditionnelles** permettent de créer des formules qui s'adaptent selon les valeurs des champs. Vous pouvez ainsi afficher différents résultats ou effectuer différents calculs selon des conditions.

## Fonction SI / IF

La fonction `SI` (ou `IF` en anglais) est la fonction conditionnelle de base.

### Syntaxe

```
SI(condition, valeur_si_vrai, valeur_si_faux)
```

**Paramètres** :
- `condition` : Expression à évaluer (vrai ou faux)
- `valeur_si_vrai` : Valeur retournée si la condition est vraie
- `valeur_si_faux` : Valeur retournée si la condition est fausse

### Exemples simples

**Vérifier un montant** :
```
SI({Montant} > 1000, "Éligible", "Non éligible")
```
- Si Montant = 1500 → **"Éligible"**
- Si Montant = 500 → **"Non éligible"**

**Appliquer une remise conditionnelle** :
```
SI({Montant} > 5000, {Montant} * 0.9, {Montant})
```
- Si Montant = 6000 → **5400** (remise de 10%)
- Si Montant = 4000 → **4000** (pas de remise)

**Vérifier un champ Oui/Non** :
```
SI({Accepté}, "Demande acceptée", "Demande refusée")
```
- Si Accepté = Oui → **"Demande acceptée"**
- Si Accepté = Non → **"Demande refusée"**

---

## Opérateurs de comparaison

Les conditions utilisent des **opérateurs de comparaison** :

| Opérateur | Signification | Exemple |
|-----------|---------------|---------|
| `=` | Égal à | `{Montant} = 1000` |
| `<>` ou `!=` | Différent de | `{Montant} <> 0` |
| `<` | Inférieur à | `{Montant} < 1000` |
| `<=` | Inférieur ou égal | `{Montant} <= 1000` |
| `>` | Supérieur à | `{Montant} > 1000` |
| `>=` | Supérieur ou égal | `{Montant} >= 1000` |

**Exemples** :
```
SI({Quantité} >= 10, "Commande en gros", "Commande au détail")
SI({Prix} <> 0, {Total} / {Prix}, 0)
SI({Score} = 100, "Parfait !", "À améliorer")
```

---

## Fonctions logiques

### ET

Vérifie que **toutes** les conditions sont vraies.

**Syntaxe** :
```
ET(condition1, condition2, ...)
```

**Paramètres** :
- Accepte 2 ou plusieurs conditions
- Retourne vrai si **toutes** les conditions sont vraies

**Exemples** :
```
SI(ET({Montant} > 1000, {Montant} <= 5000), "Tranche 1", "Autre")
```
- Si Montant = 3000 → **"Tranche 1"** (1000 < 3000 ≤ 5000)
- Si Montant = 6000 → **"Autre"**

```
SI(ET({Age} >= 18, {Accepté}), "Éligible et accepté", "Non éligible")
```
- Si Age = 25 ET Accepté = Oui → **"Éligible et accepté"**
- Si Age = 16 OU Accepté = Non → **"Non éligible"**

**Avec plusieurs conditions** :
```
ET({Age} >= 18, {Montant} <= 50000, {Accepté})
```
→ Vrai seulement si les 3 conditions sont vraies

---

### OU

Vérifie qu'**au moins une** des conditions est vraie.

**Syntaxe** :
```
OU(condition1, condition2, ...)
```

**Paramètres** :
- Accepte 2 ou plusieurs conditions
- Retourne vrai si **au moins une** condition est vraie

**Exemples** :
```
SI(OU({Montant} < 100, {Montant} > 10000), "Hors critères", "OK")
```
- Si Montant = 50 → **"Hors critères"** (< 100)
- Si Montant = 15000 → **"Hors critères"** (> 10000)
- Si Montant = 5000 → **"OK"**

```
SI(OU({Prioritaire}, {Urgent}), "Traitement rapide", "Traitement normal")
```
- Si Prioritaire = Oui OU Urgent = Oui → **"Traitement rapide"**

**Avec plusieurs conditions** :
```
OU({Score} < 5, {Score} > 18, {Dispensé})
```
→ Vrai si au moins une condition est vraie

---

### NON

Inverse une condition.

**Syntaxe** :
```
NON(condition)
```

**Paramètres** :
- Une seule condition
- Retourne l'inverse : vrai devient faux, faux devient vrai

**Exemples** :
```
SI(NON({Accepté}), "Refusé", "Accepté")
```
- Si Accepté = Non → **"Refusé"**
- Si Accepté = Oui → **"Accepté"**

```
SI(NON({Montant} > 1000), "Montant faible", "Montant élevé")
```
- Si Montant = 500 → **"Montant faible"** (NON(500 > 1000) → vrai)

---

## Conditions imbriquées

Vous pouvez **imbriquer** des fonctions `SI` pour gérer plusieurs cas.

### Exemple : Tranches de montant

```
SI({Montant} <= 1000, "Petite", SI({Montant} <= 5000, "Moyenne", "Grande"))
```

**Évaluation** :
1. Si Montant ≤ 1000 → **"Petite"**
2. Sinon, si Montant ≤ 5000 → **"Moyenne"**
3. Sinon → **"Grande"**

| Montant | Résultat |
|---------|----------|
| 500 | Petite |
| 3000 | Moyenne |
| 8000 | Grande |

---

### Exemple : Taux de subvention progressif

```
SI({Coût} <= 10000, {Coût} * 0.6, SI({Coût} <= 20000, {Coût} * 0.5, {Coût} * 0.4))
```

**Taux** :
- Coût ≤ 10000 → 60%
- 10000 < Coût ≤ 20000 → 50%
- Coût > 20000 → 40%

| Coût | Subvention |
|------|------------|
| 8000 | 4800 (60%) |
| 15000 | 7500 (50%) |
| 25000 | 10000 (40%) |

---

## Valeurs considérées comme fausses

En logique booléenne, les valeurs suivantes sont considérées comme **fausses** :

- `0` (zéro)
- `""` (chaîne vide)
- `false` (faux)
- Champ non rempli

Toutes les autres valeurs sont considérées comme **vraies**.

**Exemples** :
```
SI({Montant}, "Montant renseigné", "Montant vide")
```
- Si Montant = 100 → **"Montant renseigné"**
- Si Montant = 0 → **"Montant vide"**
- Si Montant non rempli → **"Montant vide"**

---

## Combiner plusieurs fonctions

### ET et OU ensemble

```
SI(OU(ET({Montant} >= 1000, {Montant} <= 5000), {Prioritaire}), "Accepté", "Refusé")
```

**Interprétation** :
- Accepté si (1000 ≤ Montant ≤ 5000) **OU** Prioritaire = Oui
- Sinon refusé

**Exemples** :
- Montant = 3000, Prioritaire = Non → **"Accepté"** (dans la tranche)
- Montant = 8000, Prioritaire = Oui → **"Accepté"** (prioritaire)
- Montant = 8000, Prioritaire = Non → **"Refusé"**

---

### Conditions complexes

```
SI(ET({Age} >= 18, OU({Montant} > 5000, {Garantie})), "OK", "KO")
```

**Interprétation** :
- OK si : Age ≥ 18 **ET** (Montant > 5000 **OU** Garantie = Oui)

| Age | Montant | Garantie | Résultat |
|-----|---------|----------|----------|
| 25 | 6000 | Non | OK |
| 25 | 3000 | Oui | OK |
| 16 | 6000 | Oui | KO (âge) |
| 25 | 3000 | Non | KO |

---

## Exemples pratiques

### Éligibilité multi-critères

```
SI(ET({Age} >= 18, {Montant} <= 50000, {Accepté}), "ÉLIGIBLE", "NON ÉLIGIBLE")
```

**Conditions** :
- Majeur (≥ 18 ans)
- Montant ≤ 50000
- Acceptation = Oui

---

### Message personnalisé selon tranche

```
SI({Score} >= 18, "Excellent", SI({Score} >= 14, "Bien", SI({Score} >= 10, "Moyen", "Insuffisant")))
```

| Score | Message |
|-------|---------|
| 19 | Excellent |
| 15 | Bien |
| 12 | Moyen |
| 8 | Insuffisant |

---

### Calcul avec condition multiple

```
SI(ET({Type} = "A", {Quantité} > 10), {Prix} * {Quantité} * 0.9, {Prix} * {Quantité})
```

**Interprétation** :
- Remise de 10% si Type = "A" **ET** Quantité > 10
- Sinon prix normal

---

## Bonnes pratiques

### ✅ À faire
- **Utiliser des parenthèses** pour clarifier les conditions complexes
- **Tester** toutes les branches de vos conditions
- **Prévoir un cas par défaut** (valeur si toutes les conditions sont fausses)

### ❌ À éviter
- Imbriquer trop de `SI` (difficile à lire au-delà de 3 niveaux)
- Oublier la valeur si faux : `SI(condition, "Oui")` → ❌ manque le 3ème paramètre
- Confondre `=` (égalité) avec `==` (non supporté, utiliser `=`)
- Mélanger syntaxe fonction `ET(...)` et opérateur `AND` (préférer toujours la fonction)

---

## Pages associées

- [Introduction aux formules](/faq/administrateur/les-formules-introduction)
- [Exemples pratiques de formules](/faq/administrateur/les-formules-exemples-pratiques)
- [Fonctions mathématiques](/faq/administrateur/les-formules-fonctions-mathematiques)
- [Fonctions texte](/faq/administrateur/les-formules-fonctions-texte)
