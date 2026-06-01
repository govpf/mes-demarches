# Serveur MCP de construction de formulaires (démarches) — Design

**Date :** 2026-05-31
**Statut :** Design validé, prêt pour plan d'implémentation
**Auteur :** Christian Lautier (brainstorming assisté)

## 1. Objectif

Permettre à un administrateur de **construire et modifier la structure d'une démarche**
(champs, sections, répétitions, logique conditionnelle) en dialoguant en langage naturel
avec Claude, via un **serveur MCP** connecté à mes-demarches.

Claude ne contient aucune logique métier : il pilote des outils MCP qui se traduisent en
appels d'API d'écriture sur mes-demarches. La couche métier reste **dans le code Rails**
(source de vérité unique, testée), le MCP ne fait que la *refléter*.

## 2. Scénario cible

**Admin assisté par IA.** L'administrateur décrit sa démarche à Claude (« ajoute un champ
texte “Nom”, puis une section “Pièces”, et affiche le champ “SIRET” seulement si type =
entreprise »). Claude lit la structure, propose, puis applique les modifications sur le
**brouillon** de la procédure.

## 3. Modèle d'écriture

**Écriture directe sur la révision brouillon** de la procédure.

Garde-fous (le risque est contenu) :
- On n'écrit **jamais** sur une révision publiée : seulement le brouillon (`draft`).
- mes-demarches sait **réinitialiser les modifications d'un brouillon** par rapport à la
  version publiée → bouton « annuler tout » natif, le brouillon devient un bac à sable
  réversible.
- Token scopé (cf. §7).

## 4. Architecture & topologie

Approche retenue : **serveur MCP autonome + API GraphQL dédiée** (découplé du runtime Rails).

```
Machine de l'admin                                  mes-demarches
┌───────────────────────────────┐                  ┌──────────────────────┐
│ Claude ⇄ serveur MCP (stdio)   │ ──HTTPS GraphQL─►│ API v2 GraphQL        │
│ (TypeScript, process séparé)   │   + token admin  │ → mutations structure │
└───────────────────────────────┘                  │ → couche draft        │
                                                    └──────────────────────┘
```

- **Serveur MCP** : process TypeScript (SDK MCP officiel), **indépendant** = découplé du
  runtime Rails (codebase et process séparés). Aucune logique métier ni LLM : il traduit
  les appels d'outils MCP en mutations GraphQL et remonte les erreurs structurées.
- **mes-demarches** : nouvelles mutations GraphQL de construction, qui s'appuient sur la
  couche `draft` existante (`ProcedureRevision#add_type_de_champ`,
  `#move_type_de_champ_after`, `#remove_type_de_champ`, `#find_and_ensure_exclusive_use`,
  écriture du champ `condition`).
- **Lecture** : réutilise les `query` GraphQL existantes (procédure, descripteurs de champ),
  enrichies (cf. §6). L'introspection GraphQL sert de documentation aux outils MCP.

### Organisation : deux repos (décidé)

- **Mutations GraphQL** → dans `mes-demarches` (code Rails, indissociable de l'API).
- **Serveur MCP (TypeScript)** → **repo séparé** (`mcp-mes-demarches`, voisin de
  `mes-demarches`). Motifs : cloisonnement (accès/déploiement/secrets séparés), hygiène
  vis-à-vis de la sync upstream permanente de `mes-demarches` (le serveur MCP est insensible
  aux `feature/bump-*`), toolchain Node isolée du repo Ruby, mapping direct sur le service
  déployable de la Phase B.
- **Contrat de schéma** : le serveur MCP consomme l'API comme un client GraphQL classique. Il
  s'appuie sur l'artefact déjà versionné `app/graphql/schema.graphql` (dump
  `graphql:schema:dump`) pour son codegen de types, en épinglant une version. Pas de couplage
  runtime.

### Pourquoi GraphQL (vs REST dédié)

Réutilise l'auth scopée (`APIToken`), le routing, le rate-limiting et le typage déjà en
place ; cohérent avec l'unique point d'entrée programmatique de mes-demarches ;
introspectable (auto-doc). Coût : la plomberie GraphQL est verbeuse (type + descriptor +
résolution + dump du schéma), mais ponctuel.

## 5. Périmètre MVP : champs + logique conditionnelle

### Nouvelles mutations GraphQL (écriture structure)

Toutes opèrent sur la **révision brouillon** de la procédure.

| Mutation | Rôle | S'appuie sur |
|---|---|---|
| `demarcheAjouterChamp` | Ajouter un type de champ (libellé, type, options, parent répétition/section, position) | `draft.add_type_de_champ` |
| `demarcheModifierChamp` | Modifier libellé/description/options/obligatoire (+ type si autorisé) | `find_and_ensure_exclusive_use` |
| `demarcheDeplacerChamp` | Repositionner un champ | `move_type_de_champ_after` |
| `demarcheSupprimerChamp` | Supprimer par `stable_id` | `remove_type_de_champ` |
| `demarcheDefinirCondition` | Poser/retirer la condition d'affichage | écriture `condition` |

### Outils MCP exposés à Claude

| Outil MCP | Type | Effet |
|---|---|---|
| `lire_demarche` | lecture | Structure complète : champs, types, options, `type_modifiable`, conditions existantes |
| `lister_types_champ` | lecture | Catalogue des types + options configurables + colonnes apportées (cf. §6) |
| `ajouter_champ` | écriture | Crée un champ |
| `modifier_champ` | écriture | Libellé/description/options/obligatoire (+ type si autorisé) |
| `deplacer_champ` | écriture | Repositionne |
| `supprimer_champ` | écriture | Supprime |
| `definir_condition` | écriture | Pose/retire une condition d'affichage |

### Logique conditionnelle

La condition est un arbre `Logic` (`LogicSerializer` : `And/Or/Eq/NotEq/GreaterThan/…`,
`ChampValue`, `Constant`, + opérateurs PF `in_archipel`, `in_departement`…).

`definir_condition` n'expose **pas** l'arbre brut (fragile). Forme simplifiée et validée
côté serveur :
- `champ_source` (stable_id), `opérateur` (`égal`, `différent`, `supérieur`, `inclut`,
  + opérateurs PF `dans_archipel` / `dans_commune`…), `valeur`.
- Combinaisons `ET` / `OU` à **un seul niveau** — confirmé : l'éditeur de conditions de
  mes-demarches lui-même ne gère pas l'imbrication, donc aucune fonctionnalité perdue.
- Le serveur traduit en arbre `Logic` et **valide la compatibilité de type** via
  `Logic.compatible_type?` (existe déjà). Erreur structurée sinon.

## 6. Description des champs (la « doc » lue par Claude) — critique

`lister_types_champ` et `lire_demarche` exposent **dynamiquement** :

- **Pour chaque type de champ** : libellé, options configurables, et **colonnes apportées**
  (`columns` / `info_columns`, délégués au `dynamic_type`).
- **Spécifiquement `referentiel_de_polynesie`** : la **liste live des référentiels
  disponibles** (modèle `Referentiel` ; `BaserowReferentiel` / `CsvReferentiel` /
  `ApiReferentiel`) avec leur identifiant + leurs colonnes. Donnée **dynamique**, requêtée
  à chaud — sans elle, Claude ne peut pas configurer un champ référentiel PF.

## 7. Sécurité

### Phasage du déploiement

| Phase | Modèle | Public | Auth réseau |
|---|---|---|---|
| **A (v1, maintenant)** | MCP **local** (stdio) sur la machine de l'admin | Utilisateur technique (l'auteur) | L'admin renseigne **son propre CIDR** |
| **B (plus tard)** | MCP **hébergé** par la DSI + connecteur **OAuth** | Admins non-techniques (zéro install) | CIDR = IP du serveur hébergé, posée par l'ops |

Phase A a déjà de la valeur (création rapide de formulaires par l'auteur) et valide la
mécanique à moindre coût avant d'investir dans l'hébergement + OAuth de la Phase B.

### Token (Phase A) — entièrement self-service

Le serveur MCP tourne **en local chez l'admin** (stdio) → l'IP qui frappe l'API est **le
réseau de l'admin**, qu'il connaît. L'admin crée lui-même son token dans mes-demarches
(`Administrateurs::ApiTokensController` existe déjà) en réglant les **trois bornes qu'il
connaît** :

- `write_access` = true
- `allowed_procedure_ids` = la (les) procédure(s) cible(s)
- `authorized_networks` = **son propre CIDR** (`APIToken#forbidden_network?` rejette hors plage)

Le token MCP est donc **triplement borné** : écriture / procédure cible / réseau de l'admin.
Aucun secret central. Le token est injecté dans le serveur MCP par config/env, jamais codé
en dur.

### Contrainte de changement de type (démarche publiée)

Sur une démarche publiée, un champ ne peut presque jamais changer de type (pour garantir la
migration / le *cast* des valeurs des dossiers existants). **La règle existe déjà et vit dans
le code Rails, pas dans le prompt.**

**Contexte de friction upstream :** la règle fine vit dans le composant d'éditeur
`TypesDeChampEditor::ChampComponent#accepted_type_champs` (via `Columns::ChampColumn::CAST`),
qui grise les types impossibles dans le dropdown. C'est une **feature upstream récente et
volatile** : la déplacer ou la refactorer créerait des conflits de merge à chaque
`feature/bump-*`. De plus, la sécurité de migration n'est **pas** une validation modèle —
c'est l'UI qui contraint. Une mutation doit donc porter sa **propre** garde.

**Décision (mode simple, MVP) : aucun refactor de mes-demarches.** `demarcheModifierChamp`
applique une règle conservatrice, dans du **code PF isolé** (`# pf:`) qui ne dépend ni de
`ChampComponent` ni de `Columns::ChampColumn::CAST` :

1. **Garde-fou dur** — changement de type **interdit dès que le champ existe dans la révision
   publiée**. Test sur modèles stables : `procedure.published_revision&.types_de_champ&.exists?(stable_id:)`.
   → mutation **échoue avec message explicite** (« le type d'un champ déjà publié n'est pas
   modifiable via le MCP, utilisez l'éditeur web »). Claude ne peut pas contourner.
2. **Champ neuf (brouillon seul)** — tous les types permis (aucun dossier à migrer).
3. **Lecture proactive** — le descripteur porte `type_modifiable: bool` (= le champ n'est pas
   dans la révision publiée). Claude sait avant d'essayer et l'explique à l'admin.

C'est volontairement **plus restrictif** que l'éditeur web (qui autorise les morphs
*compatibles* via `CAST`) : changer le type d'un champ publié vers un type compatible reste
faisable à la main dans l'UI. On évite ainsi tout refactor de code upstream volatile. Un mode
plus fin (lecture seule de `Columns::ChampColumn::CAST`, sans toucher au composant) est
possible en v2 si le besoin émerge.

## 8. Hors périmètre

- **Construction de formules → v2.** Exposer les colonnes (§6) est peu coûteux et descriptif.
  Mais un outil `definir_formule` suppose l'introspection de **toutes les variables
  disponibles dans un formulaire donné** (champs, sous-champs de blocs répétables, colonnes de
  référentiels, agrégats…) : lourd, outil dédié à part entière. Reporté en v2, porte laissée
  ouverte.
- **Cycle complet de démarche** (création de la procedure, service, libellés, routage,
  attestation) : hors MVP. Le MVP suppose une procédure existante avec un brouillon.
- **Phase B (hébergement + OAuth)** : documentée ici comme cap, implémentée ultérieurement.

## 9. Tests

- **Specs request GraphQL** par mutation : succès + refus (type non modifiable, hors scope
  procédure, hors réseau autorisé, brouillon absent).
- **Mapping condition** simplifiée → arbre `Logic` : aller-retour, validation
  `compatible_type?`.
- **Référentiels** : `lister_types_champ` retourne bien la liste live des référentiels PF +
  leurs colonnes.
- **Serveur MCP** (TypeScript) : mock GraphQL, vérifier la traduction outil → mutation et la
  remontée d'erreurs structurées.

## 10. Risques & points ouverts

- **Changement de type** (cf. §7) : mode simple MVP = interdiction sur champ déjà publié,
  dans du **code PF isolé**, **sans aucun refactor** du composant upstream volatile
  `ChampComponent`. Compromis assumé : plus restrictif que l'UI web (pas de morph compatible
  via MCP). Évite la friction de merge upstream.
- Verrouillage concurrent : `find_and_ensure_exclusive_use` existe déjà côté Rails ; vérifier
  son comportement quand Claude enchaîne plusieurs mutations rapprochées.
- Coût de la plomberie GraphQL pour chaque mutation (type + descriptor + résolution + dump).
- Phase B : choix du fournisseur OAuth et de l'hébergement (DSI / souveraineté) — à
  instruire séparément.
