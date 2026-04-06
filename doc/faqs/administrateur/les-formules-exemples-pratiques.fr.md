---
category: "administrateur"
subcategory: "formulas"
slug: "les-formules-exemples-pratiques"
locale: "fr"
keywords: "exemples, cas d'usage, TVA, éligibilité, subvention, prix, facture"
title: "Exemples pratiques de formules"
order: 2
---

# Exemples pratiques de formules

Cette page présente des **cas d'usage concrets** pour vous aider à créer vos formules rapidement. Chaque exemple peut être copié et adapté à vos besoins.

## Calculs financiers

### Calcul de TVA (taux fixe 16%)

**Contexte** : Calculer le montant TTC à partir d'un montant HT avec une TVA de 16%.

**Champs nécessaires** :
- `Montant HT` (nombre décimal)
- `Montant TTC` (formule)

**Formule** :
```
{Montant HT} * 1.16
```

**Exemple** :
- Si `Montant HT` = 1000
- Alors `Montant TTC` = 1160

---

## Éligibilité et contrôles

### Vérification de montant maximum

**Contexte** : Afficher "OK" si le montant demandé est inférieur au plafond, "Trop élevé" sinon.

**Champs nécessaires** :
- `Montant demandé` (nombre décimal)
- `Éligibilité` (formule)

**Formule** :
```
SI({Montant demandé} <= 50000, "OK", "Trop élevé")
```

**Exemple** :
- Si `Montant demandé` = 30000 → Affiche "OK"
- Si `Montant demandé` = 60000 → Affiche "Trop élevé"

---

### Vérification de montant minimum

**Contexte** : S'assurer qu'un montant est au-dessus d'un seuil.

**Champs nécessaires** :
- `Montant investi` (nombre décimal)
- `Validation` (formule)

**Formule** :
```
SI({Montant investi} >= 5000, "Éligible", "Non éligible")
```

**Exemple** :
- Si `Montant investi` = 7000 → Affiche "Éligible"
- Si `Montant investi` = 3000 → Affiche "Non éligible"

---

### Vérification de tranche de montant

**Contexte** : Vérifier qu'un montant est dans une fourchette donnée.

**Champs nécessaires** :
- `Montant` (nombre décimal)
- `Tranche` (formule)

**Formule** :
```
SI(ET({Montant} >= 10000, {Montant} <= 50000), "Tranche 1", SI({Montant} > 50000, "Tranche 2", "Hors critères"))
```

**Exemple** :
- Si `Montant` = 25000 → Affiche "Tranche 1"
- Si `Montant` = 75000 → Affiche "Tranche 2"
- Si `Montant` = 5000 → Affiche "Hors critères"

---

## Subventions et aides

### Subvention plafonnée

**Contexte** : Calculer une subvention de 50% du montant, plafonnée à 10000 €.

**Champs nécessaires** :
- `Montant du projet` (nombre décimal)
- `Subvention accordée` (formule)

**Formule** :
```
MIN({Montant du projet} * 0.5, 10000)
```

**Exemple** :
- Si `Montant du projet` = 15000 → Subvention = 7500 (50%)
- Si `Montant du projet` = 30000 → Subvention = 10000 (plafond)

---

### Subvention progressive

**Contexte** : Taux de 60% jusqu'à 20000 €, puis 40% au-delà.

**Champs nécessaires** :
- `Coût total` (nombre décimal)
- `Aide` (formule)

**Formule** :
```
SI({Coût total} <= 20000, {Coût total} * 0.6, 20000 * 0.6 + ({Coût total} - 20000) * 0.4)
```

**Exemple** :
- Si `Coût total` = 15000 → Aide = 9000 (60%)
- Si `Coût total` = 30000 → Aide = 16000 (12000 + 4000)

---

### Reste à charge

**Contexte** : Calculer ce qui reste à payer après déduction de la subvention.

**Champs nécessaires** :
- `Coût total` (nombre décimal)
- `Subvention` (nombre décimal)
- `Reste à charge` (formule)

**Formule** :
```
{Coût total} - {Subvention}
```

**Exemple** :
- Si `Coût total` = 20000 et `Subvention` = 8000
- Alors `Reste à charge` = 12000

---

## Manipulation de texte

### Concaténation simple

**Contexte** : Assembler le prénom et le nom.

**Champs nécessaires** :
- `Prénom` (texte)
- `Nom` (texte)
- `Nom complet` (formule)

**Formule** :
```
CONCAT({Prénom}, " ", {Nom})
```

**Exemple** :
- Si `Prénom` = "Jean" et `Nom` = "Dupont"
- Alors `Nom complet` = "Jean Dupont"

---

### Affichage conditionnel

**Contexte** : Afficher un message différent selon une condition.

**Champs nécessaires** :
- `Accepté` (Oui/Non)
- `Message` (formule)

**Formule** :
```
SI({Accepté}, "Demande acceptée", "Demande refusée")
```

**Exemple** :
- Si `Accepté` = Oui → Affiche "Demande acceptée"
- Si `Accepté` = Non → Affiche "Demande refusée"

---

## Utilisation des champs spécifiques Polynésie

### Afficher l'île de résidence

**Contexte** : Utiliser le code postal pour afficher l'île.

**Champs nécessaires** :
- `Code postal` (Code postal de Polynésie)
- `Île de résidence` (formule)

**Formule** :
```
{Code postal/ile}
```

**Exemple** :
- Si l'usager sélectionne Papeete → Affiche "Tahiti"
- Si l'usager sélectionne Uturoa → Affiche "Raiatea"

---

### Message personnalisé avec localisation

**Contexte** : Créer un message incluant la commune et l'archipel.

**Champs nécessaires** :
- `Code postal` (Code postal de Polynésie)
- `Message de bienvenue` (formule)

**Formule** :
```
CONCAT("Demande depuis ", {Code postal/commune}, " (", {Code postal/archipel}, ")")
```

**Exemple** :
- Si sélection de Papeete → "Demande depuis Papeete (Îles du Vent)"

---

### ⚠️ Calcul d'âge (NON DISPONIBLE)

**Contexte** : Calculer l'âge à partir d'un numéro DN.

**Formule souhaitée** (non fonctionnelle) :
```
ANNEE(AUJOURDHUI()) - ANNEE({Numéro DN/date_de_naissance})
```

> **❌ Non disponible** : Les fonctions de date (`ANNEE`, `AUJOURDHUI`) ne sont pas encore implémentées. Voir [Fonctions de date](/faq/administrateur/les-formules-fonctions-date) pour plus d'informations.

**Solution de contournement** : Ajouter un champ "Âge" (nombre entier) que l'usager remplit manuellement.

---

## Calculs de surface et quantité

### Surface totale

**Contexte** : Calculer la surface totale à partir de longueur et largeur.

**Champs nécessaires** :
- `Longueur` (nombre décimal)
- `Largeur` (nombre décimal)
- `Surface totale` (formule)

**Formule** :
```
{Longueur} * {Largeur}
```

**Exemple** :
- Si `Longueur` = 12.5 et `Largeur` = 8
- Alors `Surface totale` = 100

---

### Nombre de pièces par carton

**Contexte** : Calculer combien de cartons sont nécessaires.

**Champs nécessaires** :
- `Nombre de pièces` (nombre entier)
- `Pièces par carton` (nombre entier)
- `Nombre de cartons` (formule)

**Formule** :
```
ARRONDI({Nombre de pièces} / {Pièces par carton}, 0)
```

> **💡 Astuce** : Utilisez `ARRONDI(..., 0)` pour obtenir un nombre entier de cartons.

**Exemple** :
- Si `Nombre de pièces` = 250 et `Pièces par carton` = 30
- Alors `Nombre de cartons` = 8

---

## Pour aller plus loin

- [Introduction aux formules](/faq/administrateur/les-formules-introduction)
- [Fonctions mathématiques](/faq/administrateur/les-formules-fonctions-mathematiques)
- [Fonctions conditionnelles](/faq/administrateur/les-formules-fonctions-conditionnelles)
- [Fonctions texte](/faq/administrateur/les-formules-fonctions-texte)
- [Formules dans les blocs répétables](/faq/administrateur/les-formules-dans-les-repetitions)
