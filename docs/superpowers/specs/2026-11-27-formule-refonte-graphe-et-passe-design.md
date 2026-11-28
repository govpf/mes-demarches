# Champ formule : graphe unique et passe de calcul accumulante

- **Date** : 2026-11-27
- **Auteurs** : clautier + Claude
- **Remplace et complète** : `2026-05-28-formule-passe-accumulante-design.md` (spec d'intention, limitée au
  moteur). Les sections 2 à 4 de cette spec restent valables ; ce document élargit le diagnostic et fixe le
  périmètre, le découpage et les règles.
- **État du code de départ** : `devpf` après la PR #642 (formule racine constante jamais calculée).

---

## 1. Intention

Le champ formule a été construit par couches successives. Chaque bug de recalcul a reçu un correctif local, et
le calcul repose aujourd'hui sur plusieurs mécanismes qui ne lisent pas les valeurs de la même façon. Le
chantier « passe accumulante », déjà prévu pour les formules-ligne des blocs répétables, est l'occasion de
reconstruire l'ensemble sur la vision la plus simple possible.

Deux raisons d'agir maintenant :

1. Les trois derniers correctifs de production (#618, #620, #642) sont trois contournements du même défaut :
   une formule amont dont la valeur n'est pas disponible au moment où l'aval la lit.
2. Le code formule est inséré dans des fichiers qu'upstream modifie beaucoup. La méthode `project_champ` est
   réécrite par upstream dans la release `2026-11-13-01` (champs construits une seule fois et mémoïsés,
   renommage `champ_data` dès `2026-07-20-01`). Le fork en est à `2026-01-06-01` : la refonte doit être en
   production avant d'atteindre ces lots.

## 2. Diagnostic du code actuel

| # | Défaut | Où |
|---|---|---|
| D1 | **Ordre de passe faux.** `compute_formulas_in_order` itère `revision.types_de_champ`, liste à plat triée par `(position, id)` qui mélange public, privé et sous-champs de blocs. Les positions repartent de 0 à chaque niveau : une annotation privée en position 0 est calculée avant la formule publique en position 3 qu'elle lit. Lu dans le code, non reproduit par un test. | `procedure_revision.rb:16`, `dossier_formula_refresh_concern.rb:152` |
| D2 | **Quatre moteurs de calcul**, chacun avec ses règles de lecture : `compute_formulas_in_order` ; `refresh_formulas_matching` (horloge, état — sans accumulateur ni création de champ) ; le recalcul à l'affichage de `project_champ` avec son garde `Thread.current` ; le recalcul à la volée dans le service (formules-ligne #618, formule racine sans valeur #642). | `dossier_formula_refresh_concern.rb`, `dossier_champs_concern.rb:40`, `formula_calculation_service.rb` |
| D3 | **Recalculs par drapeau sans suivi de l'aval.** `has_clock`, `has_state`, `has_identite` recalculent les formules marquées, pas celles qui en dépendent (vrai aussi pour `has_identite`, qui passe déjà par `compute_formulas_in_order(only:)`). | `dossier_formula_refresh_concern.rb:37-64` |
| D4 | **Accumulateur mal keyé et mal typé.** Clé `stable_id` seule (pas de valeur par ligne). `seed_overrides` injecte `champ.value` brut, ce qui court-circuite le typage des colonnes (rattrapé par `coerce_to_list`) et ne couvre que le chemin `:value`. | `dossier_formula_refresh_concern.rb:108`, `formula_calculation_service.rb:651` |
| D5 | **Formules-ligne jamais enregistrées.** `formule_champs_for_tdc` renvoie `[]` pour un sous-champ de bloc. La valeur n'existe qu'à l'affichage. | `dossier_formula_refresh_concern.rb:278` |
| D6 | **Graphe de dépendances en quatre exemplaires**, reconstruit à chaque sauvegarde de champ : `Champ#dependent_formula_stable_ids`, `Champ#dependent_formula_champs_from`, `ProcedureRevision#dependent_formulas`, le parcours de `circular_reference?`. Deux sont déjà sans appelant (`ProcedureRevision#dependent_formulas`, `Champ#dependent_formula_champs`) : à supprimer. Six fichiers analysent `{…}` avec leur propre expression régulière. | `champ.rb:372-492`, `procedure_revision.rb:228`, `formule_type_de_champ.rb:302` |
| D7 | **Règle d'ordre validée deux fois**, différemment : `forward_reference?` et `TypesDeChamp::FormulaValidator`. | `formule_type_de_champ.rb:347`, `app/validators/types_de_champ/formula_validator.rb` |
| D8 | **Service de 912 lignes à quatre métiers** (fonctions du DSL, traduction d'erreurs, lecture des valeurs, typage). Typage écrit quatre fois. Code mort : `resolve_field_references`, `find_champ_by_label`, `find_champ_by_stable_id` ; côté `compute_formulas_in_order`, les options `persist: false` et `create_missing: false` n'ont aucun appelant. Branche héritée `{123}` encore active alors qu'aucune expression de production ne l'utilise (vérifié en production le 2026-11-27 : zéro). | `formula_calculation_service.rb` |
| D9 | **Logique upstream recopiée.** `all_champs` réimplémente la sémantique tampon + principal de `champs_on_stream`. Divergence silencieuse possible. | `formula_calculation_service.rb:796` |
| D10 | **Aucune règle sur l'état du dossier.** Un dossier de test clôturé suit en direct les changements d'expression ; une formule non enregistrée qui dépend de la date change chaque jour sur un dossier clos ; le retour d'un job API Entreprise relance un calcul global sans filtre d'état. Deux gels existent déjà et sont conservés : le rebase et le job d'horloge excluent les dossiers terminés. | `dossier_champs_concern.rb:40`, `etablissement.rb:252` |
| D11 | **Le rendu Turbo recalcule de son côté** la liste des champs à rafraîchir. | `turbo_champs_concern.rb:16`, `champ.rb:421` |

## 3. Objectifs

- Un seul chemin de calcul, quel que soit le déclencheur.
- Une formule lit toujours une valeur amont fraîche, y compris par ligne de bloc et pour une formule jamais
  calculée.
- Les formules-ligne sont enregistrées en base comme les autres.
- Un seul graphe de dépendances par révision, une seule analyse des références `{…}`.
- Une règle explicite sur les dossiers terminés.
- Le code formule ne laisse dans les fichiers upstream que des accroches d'une ligne.

**Hors périmètre**

- La fusion des deux validateurs (D7) : second temps, après les deux PR.
- La convention de déclenchement explicite (`refresh_formulas_after` appelé par chaque site qui modifie une
  source, cf. `CLAUDE.md`) : elle reste telle quelle.
- Le langage lui-même (fonctions, syntaxe, messages d'erreur) : aucun changement fonctionnel.
- Le stockage des erreurs dans la valeur (`"Erreur : …"`) : inchangé.
- La spec `2026-10-09-formules-date-de-depot-recalcul-design.md` : chantier distinct, qui s'appuiera sur la
  passe.

**À ne pas faire**

- Ne pas créer de code parallèle qui recopie une logique upstream (cf. D9). Appeler la méthode upstream.
- Ne pas changer la valeur d'une formule publique figée sur un dossier déposé en dehors des cas prévus au § 6.
- Ne pas introduire de callback ActiveRecord implicite pour déclencher un calcul.

## 4. Contraintes

- **Conflits de merge.** Règle du chantier : *une ligne taguée `# pf:` par point d'accroche dans un fichier
  upstream, toute la logique dans des fichiers PF.* L'accroche reste en place (le conflit git reste un
  capteur), mais se résout en une ligne. Chaque accroche est couverte par une spec, pour que sa disparition
  casse un test.
- **Deux portes vers le code privé upstream, pas plus.** L'écriture passe par `champ_upsert_by!` et la
  lecture par `champs_on_stream`, toutes deux privées dans `DossierChampsConcern`. Chacun de ces deux appels
  est confiné à un seul endroit du code PF. À noter : `champs_on_stream` ne garde que les champs de la
  révision courante, ce que `all_champs` ne faisait pas ; c'est le comportement voulu.
- **Tests.** Chaque étape apporte des specs de modèle et de service, plus 1 à 3 scénarios système ciblés :
  l'historique montre que les bugs sont dans les chaînes de déclenchement, pas dans les calculs. La suite
  complète tourne en CI, pas en local.
- **Déploiement.** Deux PR, deux déploiements. Pas de tâche en PR 1 ; la tâche de rattrapage de la PR 2
  s'exécute automatiquement au déploiement (`run_on_first_deploy`).
- **Volume.** Environ 200 000 dossiers en production ; viser une passe en O(nombre de champs).

## 5. Approches

### 5.1 Découpage

| Approche | Principe | Verdict |
|---|---|---|
| **A. Graphe d'abord, moteur ensuite** | PR 1 pose le graphe et y branche le moteur actuel ; PR 2 remplace le moteur. | **Retenue** (clautier). La PR 1 ne change que l'ordre et le suivi de l'aval, deux corrections de bugs ; le risque est concentré dans la PR 2. |
| B. Moteur d'abord | La passe d'abord, le graphe ensuite. | Écartée : la passe a besoin de l'ordre, il faudrait en écrire un provisoire. |
| C. Une seule PR | Tout d'un coup. | Écartée (clautier) : deux déploiements pour limiter le risque. |

### 5.2 Valeur des formules non figées (brouillon, champ non enregistré)

| Approche | Principe | Verdict |
|---|---|---|
| **1. Le champ lit la passe** | `Champs::FormuleChamp#value` (fichier PF) renvoie la valeur en base si elle est figée, sinon interroge la passe du dossier. | **Retenue** (clautier, 2026-11-27, après avoir envisagé l'option 2). Aucune ligne dans `project_champ` ; tout lecteur est servi quel que soit le chemin par lequel il a obtenu le champ. Coût : lire `.value` peut déclencher un calcul, ce qui est implicite ; les lectures par `read_attribute(:value)` sont à revoir une par une. |
| 2. Accroche dans `project_champ` | Une ligne taguée `# pf:` en fin de méthode pose sur le champ projeté la valeur calculée par la passe. | Écartée : c'est la méthode qu'upstream réécrit ; ne sert que les champs obtenus par `project_champ`. |
| 3. Tout enregistrer, même en brouillon | Plus aucun calcul à l'affichage. | Écartée : impose une passe à chaque modification de la démarche, donc de nouvelles accroches côté administrateur. |

## 6. Conception

### 6.1 Le graphe (un par révision)

Objet PF, obtenu par `revision.formula_graph`. Il n'est **pas mémoïsé** sur la révision (décision prise à
l'implémentation de la PR 1) : les specs partagent l'instance de révision entre la démarche et le dossier,
et un graphe gardé en mémoire deviendrait périmé dès qu'une expression change. Chaque méthode appelante le
construit et le garde en variable locale : deux à trois constructions par enregistrement d'un champ, sans
requête SQL une fois les types de champ de la révision chargés. La passe de la PR 2 tiendra le sien pour sa
durée de vie. Il porte :

- **l'analyse des références** : la seule fonction qui découpe une expression en références
  (`{tdcN}`, `{tdcN/chemin}`, `{tdcBloc/sub_N}`, colonnes système). Les six analyses
  actuelles l'appellent ;
- **les nœuds** : chaque formule de la révision avec son niveau (racine publique, racine privée, ligne d'un
  bloc donné) ;
- **les arêtes**, avec la distinction que `formule_deps['champs']` ne fait pas aujourd'hui : dépendance vers
  un champ, vers un bloc entier (`NB({Bloc})`), vers un sous-champ d'un bloc (agrégat) ;
- **l'ordre de calcul** : champs publics dans l'ordre des positions, chaque bloc déplié à sa place
  (sous-champs dans leur ordre), puis champs privés selon la même logique. C'est l'ordre du § 2 de la spec de
  mai ; il corrige D1 ;
- **la fermeture aval** : pour un ensemble de sources (un champ, ou toutes les formules portant un drapeau),
  la liste ordonnée des formules à recalculer. La règle « un agrégat dépend du bloc, donc suivre le bloc
  parent d'une formule-ligne atteinte » (#620, § 3 ter de la spec de mai) y est exprimée une fois ;
- **la validation structurelle** : cycle et référence vers l'avant. La règle de visibilité reste
  **strictement** celle d'aujourd'hui (`available_columns_for_formula` : champs remplissables, frères
  précédents de la même ligne, racine avant le bloc, tout le public pour une annotation, blocs agrégeables).
  Son code déménage dans un objet PF à part, `FormulaReferenceScope`, que le graphe utilise ; le fichier
  upstream ne garde que des lignes de délégation, utilisées par l'éditeur. Aucune expression acceptée aujourd'hui ne doit être refusée, ni l'inverse (choix de Claude).
  Le format hérité `{N}` n'est pas reconnu par l'analyse : plus aucune expression ne l'utilise (§ 6.5).

`formule_deps` (stocké dans les options du type de champ) reste la donnée enregistrée : le job de nuit s'en
sert en SQL pour trouver les révisions concernées. Le graphe la lit et la produit ; son format ne change pas
dans ce chantier.

### 6.2 La passe (une par dossier)

Objet PF, obtenu par `dossier.formula_pass`. Il porte :

- **un accumulateur** keyé `(stable_id, row_id)`, qui contient des valeurs **typées** (nombre, booléen, date,
  liste, texte), pas des chaînes. Il est alimenté à la demande à partir des champs du dossier, lus par la
  méthode upstream `champs_on_stream` (tampon prioritaire sur principal) ;
- **le parcours** : les formules du périmètre, dans l'ordre du graphe ; pour une formule-ligne, une fois par
  ligne vivante du bloc. Chaque résultat entre dans l'accumulateur avant le calcul suivant ;
- **les lectures**, toutes dans l'accumulateur : une formule-ligne lit `(sous-champ, même ligne)` puis
  `(champ, sans ligne)` ; un agrégat lit toutes les entrées `(sous-champ, *)` des lignes vivantes ; une
  formule racine lit `(champ, sans ligne)` ;
- **la garantie « amont toujours disponible »** : si une formule lue n'est pas encore dans l'accumulateur et
  n'a pas de valeur enregistrée, elle est calculée à ce moment-là et mémorisée. Cela couvre la formule
  constante de #642 sans code particulier ;
- **deux paramètres seulement** : le périmètre (tout, ou la fermeture aval d'un ensemble de sources ou d'un
  drapeau) et enregistrer ou non. Le périmètre dit aussi pourquoi on calcule (source modifiée, transition
  d'état, horloge…) : c'est ce qui permet d'appliquer la règle du § 6.4 à l'entrée.

Tous les points d'entrée actuels deviennent des appels à la passe :

| Déclencheur | Périmètre | Enregistre |
|---|---|---|
| Création, préremplissage (`compute_initial_formulas`) | tout | oui |
| Source modifiée (`refresh_formulas_after`) | aval de la source, limité à sa ligne pour les formules-ligne | oui |
| Ligne ajoutée ou supprimée | aval du bloc | oui |
| Rebase, fusion du tampon | tout (rebase) / formules privées (fusion) | oui |
| Horloge, état, identité | formules portant le drapeau **et leur aval** | oui |
| Affichage d'une valeur non figée (§ 6.3) | tout | non |

Les signatures publiques `refresh_formulas_after`, `compute_initial_formulas`, `compute_formulas_in_order`,
`refresh_*_dependent_formulas` sont conservées : les 25 sites d'appel ne bougent pas. Le filtre existant sur
les formules privées quand la source est sur un tampon est conservé.

**Dossiers déposés non terminés : comportement inchangé** (choix de Claude). Le chantier ne modifie pas ce
qui se recalcule aujourd'hui sur un dossier en construction ou en instruction : rebase (tout), retour API
Entreprise (tout), transitions d'état, identité, et job de nuit limité aux annotations privées. La seule
règle d'état nouvelle concerne les dossiers terminés (§ 6.4).

L'enregistrement passe par une seule méthode PF qui appelle `champ_upsert_by!` et n'écrit que si la valeur a
changé (`update_columns` de `value` et `updated_at`, comme aujourd'hui).

Ce que la passe supprime : `value_overrides` et `seed_overrides`, `refresh_formulas_matching`,
`formule_champs_for_tdc`, `compute_line_formula_value`, `line_formula_champ`, la branche #642 de
`extract_column_value`, `all_champs`, le garde `Thread.current[:dossier_champs_formule_recomputing]`, le bloc
PF de `project_champ`, `Champs::FormuleChamp#compute_value_from_formula`.

### 6.3 Lecture de la valeur

`Champs::FormuleChamp#value` (fichier PF) :

- renvoie la valeur en base quand elle est **figée**, c'est-à-dire quand le champ est enregistré et que la
  révision du dossier n'est pas un brouillon ;
- sinon interroge `dossier.formula_pass`, qui calcule en mémoire une fois par requête : le premier appel
  calcule toutes les formules du dossier dans l'ordre du graphe, les suivants sont des lectures de
  l'accumulateur ;
- sur le flux en lecture seule `user:history` (vue « version d'origine »), renvoie toujours la valeur en base
  (choix de Claude).

Le bloc PF de `project_champ` disparaît entièrement : aucune ligne formule ne reste dans cette méthode, que
la réécriture upstream peut donc remplacer sans conflit.

`value` est lu partout (`blank?`, `ChampColumn` donc exports, GraphQL, balises d'attestation, conditions) :
c'est voulu, tous ces lecteurs reçoivent la même valeur. La passe lit ses sources par `champs_on_stream` et
ses formules amont dans l'accumulateur, jamais par `value` d'un champ formule : pas de rappel sur elle-même,
et le garde `Thread.current` disparaît.

Les lectures qui contournent `.value` sont à revoir une par une (décision clautier) :
`read_attribute(:value)` dans `FormuleTypeDeChamp#champ_value` et `#champ_value_for_export`, et dans le
moteur lui-même quand il compare l'ancienne et la nouvelle valeur avant d'écrire (là, la lecture brute est
voulue).

La passe mémorisée est jetée quand un champ source change en cours de requête (enregistrement puis
réaffichage Turbo) ; ce point est traité explicitement dans le plan de la PR 2, avec une spec.

Conséquence attendue : le test `pending` « révision brouillon : formule racine chaînée après modification de
l'expression amont » de `spec/models/champs/formule_cascade_audit_spec.rb` passe.

Les filtres et tris SQL du tableau instructeur ne voient que la base : c'est l'enregistrement des
formules-ligne qui les sert.

### 6.4 Règle sur les dossiers terminés

Un dossier terminé (accepté, refusé, classé sans suite) est **figé** : `value` renvoie la valeur en base, y
compris sur un dossier de test, et la passe refuse tout calcul, sauf deux déclencheurs :

1. **la transition d'état elle-même** : le recalcul des formules `has_state` et de leur aval, lancé par le
   `after_commit` au moment où le dossier devient terminé, reste en place. C'est la dernière écriture avant
   le gel ;
2. **la modification d'une annotation privée** (décision clautier) : les formules qui dépendent de cette
   annotation sont recalculées. Le critère est « la source est un champ privé », que la modification vienne
   d'un instructeur, d'un robot ou d'un retour de job sur cette annotation. Conséquence assumée : une formule
   aval qui utilise la date du jour prend la date de ce recalcul.

Tout le reste est ignoré sur un dossier terminé : horloge, identité, retour API Entreprise au niveau
dossier, et retour asynchrone sur un champ **public** (SIRET, RNA, référentiel, pièce justificative) —
confirmé par clautier le 2026-11-27.

À la réouverture d'un dossier (retour en instruction), pas de passe de dégel particulière : le changement
d'horodatage relance les formules `has_state`, le job de nuit reprend les annotations à horloge (choix de
Claude).

La règle est posée à un seul endroit : l'entrée de la passe.

### 6.5 Typage et DSL

Le typage d'une valeur lue (colonne → valeur Ruby pour Dentaku) et la mise en forme d'un résultat (valeur
Ruby → chaîne enregistrée) sont écrits une fois chacun. `FormulaCalculationService` est découpé : les
fonctions du langage et la traduction des erreurs Dentaku d'un côté, l'évaluation d'une expression de
l'autre. Le code mort listé en D8 est supprimé.

La branche héritée `{123}` (et sa conversion numérique par extraction de chiffres dans le texte) est
supprimée avec le découpage du service (PR 2), sans conversion : la requête en lecture seule exécutée en
production le 2026-11-27 ne trouve aucune expression à ce format.

## 7. Découpage

### PR 1 — Graphe unique

- Le graphe (§ 6.1) et l'analyse unique des références.
- Le moteur actuel est conservé, mais itère dans l'ordre du graphe (corrige D1) et les recalculs par drapeau
  utilisent la fermeture aval (corrige D3).
- Les méthodes de dépendances quittent `champ.rb`, `procedure_revision.rb` et
  `procedure_revision_type_de_champ.rb` ; il n'y reste que des accroches d'une ligne là où un appelant
  upstream en a besoin. `circular_reference?` et `forward_reference?` s'appuient sur le graphe.
- `TurboChampsConcern` demande au graphe la liste des formules à rafraîchir (D11).
- Aucune migration, aucun changement de stockage.
- Dans un recalcul par drapeau, l'accumulateur (indexé par `stable_id` seul) n'est pas alimenté pour les
  formules-ligne : une formule-ligne qui en lit une autre repasse par le calcul par ligne du service. La
  même limite subsiste dans `compute_formulas_in_order` jusqu'à la passe de la PR 2.
- À reprendre en PR 2 : `formule_deps['champs']` n'est plus lu par aucun code Ruby depuis que le graphe lit
  l'expression ; seuls les drapeaux de `formule_deps` servent encore (dont la requête SQL du job de nuit).
- Écarts assumés sur des formes que l'éditeur ne produit jamais : une référence écrite avec des espaces de
  bord (`{ tdcN }`) est désormais vue par l'analyse (donc refusée si elle pointe vers l'avant) ; `{tdcNabc}`
  et une accolade non fermée ne sont plus prises pour une référence au champ N.
- **Pas de tâche de rattrapage en PR 1** (décision de clautier, 2026-11-27) : les valeurs déjà fausses en
  base à cause de D1 et D3 ne se corrigent qu'au prochain déclencheur. Les formules sont encore peu
  nombreuses et le périmètre est maîtrisé ; une correction ponctuelle se fait à la main si un cas remonte.

### PR 2 — Passe accumulante

- La passe (§ 6.2), la lecture de la valeur (§ 6.3), la règle des dossiers terminés (§ 6.4), le découpage du
  service (§ 6.5).
- Suppression des contournements et du bloc de `project_champ`.
- Tâche de maintenance de rattrapage, exécutée au déploiement : crée **uniquement les champs formule-ligne
  manquants** des dossiers existants, sans relancer de passe complète (les formules racine figées ne sont pas
  réécrites). Elle couvre tous les états sur révision publiée ; les dossiers de test sur révision brouillon
  sont exclus (calculés à l'affichage). Les champs créés reçoivent comme `updated_at` la date de dépôt du
  dossier (ou sa date de création), pour ne pas afficher « modifié le » à la date du déploiement dans la vue
  instructeur (choix de Claude). Pour un dossier terminé, la valeur enregistrée est celle calculée le jour du
  rattrapage (une formule dépendant de la date du jour sera figée à cette date et non à celle de la clôture).

## 8. Tests

**Non-régression, à garder verts d'un bout à l'autre**

- `spec/models/champs/formule_cascade_audit_spec.rb`, `spec/models/concerns/dossier_clone_concern_spec.rb`
  (contexte formule), `spec/services/formula_calculation_service_spec.rb`,
  `spec/models/concerns/dossier_formula_refresh_concern_spec.rb`, `spec/graphql/annotation_spec.rb`.
- Les scénarios système `spec/system/users/formula_*` et `spec/system/instructeurs/formula_*`.

**Nouveaux, PR 1**

- Annotation privée placée en première position qui lit une formule publique placée plus bas : valeur juste
  après modification de la source (D1).
- Formule-ligne qui lit une formule racine placée après le rang de la formule-ligne dans son bloc (D1).
- Formule B qui lit une formule A contenant `AUJOURDHUI()` : B est à jour après le job de nuit (D3). Même
  cas pour un horodatage d'état et pour l'identité.
- Spec du graphe : ordre, fermeture aval, cycle, référence vers l'avant, les trois sortes d'arêtes.

**Nouveaux, PR 2**

- Formules-ligne enregistrées après saisie, après ajout de ligne, après rebase ajoutant une formule dans un
  bloc.
- Annotation privée qui agrège un bloc public.
- Le test `pending` du brouillon, réactivé.
- Dossier terminé : l'affichage ne recalcule pas (dossier de test, formule à date du jour) ; une annotation
  modifiée recalcule ses formules dépendantes.
- Tâche de rattrapage.
- Scénarios système : (1) usager, bloc avec formule-ligne chaînée et agrégat, puis rechargement de la page ;
  (2) administrateur, dossier de test, modification d'une expression amont ; (3) instructeur, annotation
  modifiée sur un dossier accepté.

## 9. Laissé à l'implémentation

- Les noms des classes et leur emplacement (`app/models/formules/…` ou `app/services/…`).
- La structure interne du graphe et de l'accumulateur.
- L'invalidation de la passe mémorisée quand un champ source change en cours de requête.
- Le traitement d'un champ formule non enregistré sur un dossier terminé qui aurait échappé au rattrapage
  (afficher « — » ou calculer une fois).
