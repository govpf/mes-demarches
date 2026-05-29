# Design doc — Refonte du calcul des formules : passe unique accumulante

_Date : 2026-05-28 | Auteur : architecture review (clautier + Claude)_

Spec d'intention pour une refonte ultérieure. Pas de chantier ouvert — capture
le raisonnement validé pour remplacer le workaround « recalcul à la volée » des
formules-ligne en répétition (cf. `app/services/formula_calculation_service.rb`
→ `compute_line_formula_value`).

---

## 1. Problème actuel

Le calcul des formules s'appuie aujourd'hui sur **trois mécanismes disjoints**,
ce qui crée des angles morts :

1. **`all_champs`** (`FormulaCalculationService`) = lecture directe de
   `@dossier.champs` (persistés, filtrés par stream). Rapide, mais **ne contient
   pas** les champs jamais persistés — notamment les **formules-ligne dans un
   bloc** (`formule_champs_for_tdc` fait `return [] if tdc.child?`).
2. **`value_overrides`** (`compute_formulas_in_order`) = accumulateur de valeurs
   fraîches pour la transitivité A→B→C. **Keyé par `stable_id` seul** → incapable
   de tenir une valeur **par ligne** (un sous-champ de bloc a un stable_id mais N
   lignes). C'est la limite qui casse l'agrégat de formules-ligne.
3. **Le garde anti-récursion** de `project_champ`
   (`Thread.current[:dossier_champs_formule_recomputing]`) = recalcul en mémoire
   à l'affichage draft, mais qui **bloque** toute relecture imbriquée → une
   formule-agrégat ne peut pas lire une formule-ligne via `project_champs`.

Conséquence : `SOMME({Bloc/Sous-formule})` ne trouvait aucune valeur. Workaround
actuel : recalculer la formule-ligne à la volée pour chaque ligne (correct mais
inélégant — cf. [[project_formule_ligne_repetition_materialization]]).

---

## 2. Cible : un seul accumulateur ordonné, keyé par ligne

Une **passe unique** qui calcule les champs dans l'ordre et **stocke chaque
résultat au fur et à mesure** dans un accumulateur que toute formule lit.

### Structure
- Accumulateur keyé par **`public_id` = (stable_id, row_id)** (et non `stable_id`
  seul). C'est la clé de voûte : permet de tenir une valeur **par ligne**.
- Remplace simultanément les 3 mécanismes : `all_champs` (lecture), `value_overrides`
  (transitivité), et le garde de `project_champ` (plus nécessaire).

### Ordre de la passe
L'invariant qui rend la passe correcte et **sans récursion** existe déjà :
`forward_reference?` garantit qu'une dépendance **précède toujours** son
consommateur (pas de référence « vers l'avant », pas de cycle). Donc une passe
en **ordre de position** suffit : au moment de calculer X, tout ce dont X dépend
est déjà dans l'accumulateur.

1. **Public, dans l'ordre des positions**, blocs **dépliés inline** : pour chaque
   bloc → sous-champs sources puis formules-ligne **par ligne**, puis les
   agrégats positionnés après le bloc.
2. **Puis privé**, même logique.

### Lectures (tout devient un lookup dans l'accumulateur)
- **Formule-ligne** : lit ses siblings `(sibling_sid, même row_id)`.
- **Agrégat de bloc** : lit toutes les entrées `(sub_sid, *)` du bloc.
- **Formule racine** : lit `(sid, nil)`.
- **Formule privée** : lit n'importe quelle entrée publique déjà calculée.

---

## 3. Le cas privé → public (et blocs)

`forward_reference?` autorise une **annotation privée à référencer TOUT le
public** (pas seulement ce qui précède). Traduction dans la passe : **tout le
public doit être calculé avant la première formule privée** — naturellement
satisfait par « public en entier, puis privé ».

Au moment où une formule privée calcule, sont déjà dans l'accumulateur :
- les formules publiques racine ✓
- les **agrégats de blocs publics** (`SOMME({BlocPublic/...})`) ✓
- les **formules-ligne publiques** (présentes par `(stable_id, row_id)`) ✓

La dimension « ligne » de l'accumulateur est ce qui rend le cas bloc traitable —
c'est précisément ce qui manque à `value_overrides` aujourd'hui.

---

## 4. Le point dur

Le seul morceau non trivial : **l'ordre de dépliage des blocs** quand les
dépendances croisent les frontières de lignes (formule-ligne → agrégat →
formule racine → annotation privée → …). Comme `forward_reference` interdit déjà
cycles et références avant, un **tri topologique par `(position, row_id)`** reste
linéaire et déterministe.

---

## 5. Point de départ d'implémentation

1. Remplacer `value_overrides` (keyé `stable_id`) par un accumulateur keyé
   `public_id` dans `compute_formulas_in_order`.
2. Faire lire `FormulaCalculationService` dans cet accumulateur **en priorité**
   (avant `all_champs`).
3. Déplier les lignes de bloc dans la passe (sous-champs + formules-ligne par
   ligne) et **persister** les formules-ligne au passage (lève la limitation
   `return [] if tdc.child?` de `formule_champs_for_tdc`).
4. Retirer le workaround `compute_line_formula_value` et le garde
   `dossier_champs_formule_recomputing` une fois la passe en place.
5. Spec de non-régression : `spec/models/champs/formule_cascade_audit_spec.rb`
   (agrégat de formule-ligne) + un cas **annotation privée agrégeant un bloc
   public**.

---

## 6. Out of scope (ici)

- L'implémentation elle-même (chantier séparé).
- La perf fine de la passe (mais viser O(N champs), pas O(N²)).
- Le bug de debug `Rails.log.info` (typo `Rails.logger`) dans
  `DossierChampsConcern#project_champs_public_all` — à corriger indépendamment.
