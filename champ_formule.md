# Spécification : Champ Formule

## Descriptif

Le champ formule permet de calculer automatiquement des valeurs **numériques ou textuelles** en fonction des champs précédents dans un formulaire. Cette fonctionnalité est particulièrement utile pour :
- Calculer des montants (TVA, totaux, remises)
- Effectuer des opérations arithmétiques (sommes, produits, pourcentages)
- Appliquer des conditions logiques simples
- **Générer du texte dynamique basé sur d'autres champs**
- **Concaténer des informations provenant de plusieurs champs**
- Valider des données saisies

### Fonctionnement

Un champ formule s'appuie sur les champs précédents pour effectuer ses calculs. Dans le cas d'une annotation privée, la formule peut référencer tous les champs usagers et toutes les annotations qui précèdent le champ formule.

La valeur calculée se met à jour automatiquement dès qu'un champ dépendant est modifié, en utilisant le système de conditions existant (modèle `Logic`).

### Types de formules supportées

- **Formules numériques** : calculs mathématiques, conditions retournant des nombres
- **Formules textuelles** : génération de texte, concaténation, conditions retournant du texte

## Gems à ajouter au projet

### Dentaku
```ruby
gem 'dentaku', '~> 3.5.4'
```

**Pourquoi Dentaku ?**
- Parser et évaluateur sécurisé pour formules mathématiques **et textuelles**
- Support des variables et fonctions personnalisées
- Gestion de la précédence des opérateurs et parenthèses
- Fonctions intégrées numériques (SUM, MIN, MAX, IF, etc.)
- **Fonctions intégrées textuelles (CONCAT, LEFT, RIGHT, MID, LEN, FIND, SUBSTITUTE, CONTAINS)**
- Évaluation sécurisée d'expressions utilisateur sans risques de sécurité
- Cache des AST pour de meilleures performances

## Étapes de développement (User Stories)

(Les étapes 1 à 8 restent inchangées)

...

## Étape 9 : Formules sur les Blocs Répétables

**Objectif :** Étendre le moteur de formules pour permettre des calculs (sommes, comptages, moyennes) et des vérifications logiques (contient, tous les éléments valident...) sur des champs situés à l'intérieur de blocs répétables.

### User Story 1 : Calculs et vérifications sur des listes de données
**En tant qu'administrateur, je veux pouvoir agréger et questionner des données provenant d'un bloc répétable pour répondre à des besoins comme "Quel est le coût total ?" ou "Y a-t-il au moins un passager majeur ?".**

#### **Partie A : Résolution des champs de blocs répétables**

**Tâches (Développeur) :**
1.  **Définir la syntaxe :** La référence à un champ dans un bloc répétable utilisera la syntaxe `{Nom du Bloc.Nom du Champ}`.
2.  **Modifier le résolveur de variables :** Adapter la logique qui remplace les `{...}` par leurs valeurs. Quand la syntaxe `{Bloc.Champ}` est détectée, le résolveur ne doit plus retourner une simple valeur, mais une **liste (Array Ruby)** de toutes les valeurs de ce champ pour chaque instance du bloc.
    - *Exemple :* Si le bloc `Enfants` a 3 entrées avec les âges 10, 22, 15, la référence `{Enfants.Âge}` doit être transformée en `[10, 22, 15]` avant le calcul.
3.  **Gérer les cas vides :** Si un bloc n'a aucune entrée, la référence doit retourner une liste vide `[]`.
4.  **Tests :**
    - Valider qu'une référence à un champ de bloc retourne bien une liste.
    - Valider que le cas d'un bloc vide retourne `[]`.

**Critères d'acceptation :**
- Le moteur de formule peut interpréter `{Bloc.Champ}` comme une liste de valeurs.

---

#### **Partie B : Implémentation de la fonction `FILTER`**

**Contexte :** Pour éviter de créer une multitude de fonctions (`SUM_IF`, `COUNT_IF`...), nous introduisons une fonction `FILTER` universelle qui permet de sélectionner des données. Les fonctions existantes (`SUM`, `COUNT`...) seront ensuite composées avec `FILTER`.

**Tâches (Développeur) :**
1.  **Définir la fonction personnalisée `FILTER` :**
    - Signature : `FILTER(liste_a_retourner, liste_de_condition, condition)`
    - `liste_a_retourner` : La liste de valeurs à retourner (ex: `{Factures.Montant}`).
    - `liste_de_condition` : (Optionnel) La liste sur laquelle la condition est testée (ex: `{Factures.Statut}`). Si omis, la condition est testée sur `liste_a_retourner`.
    - `condition` : L'expression de la condition (ex: `"= 'Payée'"`).
2.  **Implémenter la logique de `FILTER` :**
    - La fonction itère sur `liste_de_condition` (ou `liste_a_retourner`).
    - Pour chaque élément, elle évalue la `condition`.
    - Si la condition est vraie, elle ajoute l'élément de `liste_a_retourner` (au même index) à une nouvelle liste de résultats.
    - La fonction retourne la liste de résultats.
3.  **Tests unitaires pour `FILTER` :**
    - Cas simple : `FILTER({10, 20, 30}, '> 15')` doit retourner `[20, 30]`.
    - Cas avec listes parallèles : `FILTER({'A', 'B', 'C'}, {1, 2, 3}, '> 1')` doit retourner `['B', 'C']`.
    - Cas sans correspondance : doit retourner `[]`.
    - Cas avec listes de tailles différentes : doit gérer l'erreur ou retourner `[]`.

**Critères d'acceptation :**
- La fonction `FILTER` est disponible et permet de filtrer une liste en fonction d'une condition sur elle-même ou sur une liste parallèle.

---

#### **Partie C : Composition et documentation des cas d'usage**

**Tâches (Développeur) :**
1.  **Valider la composition :** S'assurer que les fonctions existantes (`SUM`, `COUNT`, `AVG`, `JOIN`) fonctionnent correctement quand elles reçoivent une liste issue de `FILTER` (y compris une liste vide).
2.  **Documenter les cas d'usage principaux :** Mettre à jour la documentation pour expliquer comment réaliser les opérations courantes par composition.
    - **SUM IF :** `SUM(FILTER({Montants}, {Statuts}, '='Payée''))`
    - **COUNT IF :** `COUNT(FILTER({Âges}, '> 18'))`
    - **ANY (au moins un) :** `COUNT(FILTER({Âges}, '> 18')) > 0`
    - **ALL (tous) :** `COUNT(FILTER({Statuts}, '='Signé'')) = COUNT({Statuts})`
    - **JOIN IF :** `JOIN(FILTER({Noms}, {Âges}, '> 18'), ', ')`

**Critères d'acceptation :**
- Les fonctions `SUM`, `COUNT`, `AVG`, `JOIN` acceptent en entrée le résultat de `FILTER`.
- La documentation interne est mise à jour avec les exemples de composition.

## Étape 10 : Amélioration de la Compatibilité Excel (Fonctions de convenance)

**Objectif :** Réduire la courbe d'apprentissage pour les utilisateurs familiers avec Excel en offrant des fonctions et des alias connus. Ces fonctions sont des "raccourcis" pour les compositions décrites à l'étape 9.

### User Story 1 : Alias des fonctions en français
**En tant qu'utilisateur d'Excel, je veux pouvoir utiliser les noms de fonctions en français que je connais déjà (SI, SOMME, NB...) pour ne pas avoir à réapprendre les noms en anglais.**

**Tâches (Développeur) :**
1.  **Identifier le point de configuration :** Localiser dans le code le service ou l'initialiseur où le moteur de calcul Dentaku est configuré.
2.  **Créer la table d'alias :** Définir une table de correspondance (`Hash` Ruby) qui mappe les noms français aux noms anglais : `{'SI' => 'IF', 'SOMME' => 'SUM', 'NB' => 'COUNT'...}`.
3.  **Intégrer les alias :** Modifier le processus d'évaluation pour que le moteur reconnaisse les alias français.
4.  **Tests :** Valider que `SI(VRAI, 1, 0)` et `IF(TRUE, 1, 0)` donnent le même résultat.

**Critères d'acceptation :**
- Les formules peuvent être écrites avec les noms de fonctions français (`SI`, `SOMME`...) ou anglais (`IF`, `SUM`...). 

---

### User Story 2 : Fonctions conditionnelles `NB.SI` et `SOMME.SI`
**En tant qu'utilisateur d'Excel, je veux disposer des fonctions `NB.SI` et `SOMME.SI` car je suis habitué à leur simplicité.**

**Note pour le développeur :** Ces fonctions sont des raccourcis pour `COUNT(FILTER(...))` et `SUM(FILTER(...))`. Elles doivent se comporter exactement comme leur équivalent sur Excel.

#### **Partie A : Implémentation de `NB.SI` (COUNTIF)**

**Tâches (Développeur) :**
1.  **Définir la fonction `NB.SI` :**
    - Signature : `NB.SI(plage, condition)`
    - En interne, cette fonction peut appeler `COUNT(FILTER(plage, condition))` pour assurer un comportement cohérent.
2.  **Tests :**
    - `NB.SI({'Oui', 'Non', 'Oui'}, '= 'Oui'')` doit retourner `2`.
    - `NB.SI({10, 20, 30}, '> 15')` doit retourner `2`.

**Critères d'acceptation :**
- La fonction `NB.SI({MonBloc.MonChamp}, {condition})` est disponible.
- Un alias `COUNTIF` est également disponible.

#### **Partie B : Implémentation de `SOMME.SI` (SUMIF)**

**Tâches (Développeur) :**
1.  **Définir la fonction `SOMME.SI` :**
    - Signature : `SOMME.SI(plage_condition, condition, [plage_somme])`
    - En interne, utiliser `SUM(FILTER(plage_somme, plage_condition, condition))`.
2.  **Tests :**
    - `SOMME.SI({'A', 'B', 'A'}, '= 'A'', {100, 200, 300})` doit retourner `400`.
    - `SOMME.SI({10, 20, 5}, '> 8')` doit retourner `30`.

**Critères d'acceptation :**
- La fonction `SOMME.SI(...)` est disponible.
- Un alias `SUMIF` est également disponible.

(... Le reste du document reste inchangé ...)