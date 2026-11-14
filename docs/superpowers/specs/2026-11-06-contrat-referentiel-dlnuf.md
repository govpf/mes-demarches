# Contrat « référentiel DLNUF » entre Mes-Démarches, le robot inspecteur et Baserow

**Date :** 2026-11-06
**Statut :** contrat validé dans son principe, à appliquer dans les deux dépôts
**Parties :** Mes-Démarches (ce dépôt) · inspecteur-mes-demarches (schema builder + synchro `baserow_sync`) · tables Baserow
**Documents liés :** spec du lot C `2026-11-06-prefill-piece-justificative-reference-md-design.md` ; devis `2026-07-21-devis-referentiel-dlnuf-cascade-prefill.md` ; devis global inspecteur `docs/superpowers/specs/2026-07-22-devis-dlnuf-subventions-global.md`

## 1. Objet

Fixer les **formats partagés** qui permettent à trois composants indépendants de s'accorder sur
la nature d'une table Baserow **sans configuration répétée** :

- le **schema builder** (inspecteur) crée la table et y pose un marqueur ;
- la **synchro** (inspecteur) lit le marqueur et en déduit son comportement ;
- le **champ « Référentiel de Polynésie »** (Mes-Démarches) lit le marqueur et en déduit le mode DLNUF.

Le marqueur est porté **par la table elle-même**. Il n'y a plus qu'**une seule déclaration**,
faite à la création de la table.

## 2. Deux types de référentiels

| | **archive** (défaut) | **DLNUF** |
|---|---|---|
| Usage | Consultation, registre (ex. DJS, DCA) | « Dites-le-nous une fois » : données de l'usager réutilisées d'une démarche à l'autre |
| Accès dans Baserow | Selon l'application (agents, public…) | **Exploitant seul** |
| Durée de vie d'une ligne | Indépendante du dossier MD (peut dépasser sa purge) | **Égale à celle du dossier MD** |
| Pièces jointes | Copie du fichier (colonne `file`) | **Référence** vers le champ MD (colonne texte) |
| Effacement à la suppression du dossier MD | Non (option future, si un besoin est prouvé) | **Oui** |
| Lecture par MD | Catalogue : toute ligne sélectionnable | Restreinte aux lignes du **titulaire** du dossier |
| Préremplissage de PJ par MD | Refusé (ouverture future sur cas prouvé) | Autorisé |

Les trois propriétés DLNUF (effacement, références, restriction au titulaire) sont **solidaires** :
une référence n'est valable que tant que le dossier existe, donc une table à références doit être
effacée avec ses dossiers ; et une table effacée avec ses dossiers ne doit pas contenir de copies
de fichiers. D'où **un seul label**, `DLNUF`, plutôt que des options indépendantes.

## 3. Marqueur de table

### 3.1 Emplacement

La **description de la colonne primaire** de la table (colonne `Dossier` créée par le schema
builder). Baserow interdit de supprimer la colonne primaire : le marqueur ne peut pas disparaître
avec elle. Les lecteurs identifient la colonne par son attribut `primary: true`, jamais par son nom.

Lecture : API `GET /api/database/fields/table/{id}/` (jeton de base de données suffisant), attribut
`description`. Écriture : création ou modification de colonne (JWT). Vérifié sur Baserow 2.0.6.

### 3.2 Format

Une ligne lisible pour l'exploitant, puis **une ligne machine** commençant par `mes-demarches:` :

```
Référentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.
mes-demarches: referentiel=DLNUF; proprietaire=12345
```

Règles d'analyse (identiques dans les deux dépôts) :

- On retient les lignes dont le début, espaces retirés, est `mes-demarches:` (casse ignorée).
- Le reste de la ligne est une suite de paires `cle=valeur` séparées par `;`. Espaces autour des
  clés et valeurs ignorés ; casse des clés ignorée ; valeurs comparées sans tenir compte de la casse.
- Clés inconnues : ignorées (extensibilité).
- **Plus d'une ligne `mes-demarches:`**, ou ligne présente mais illisible : marqueur **invalide**.

| Clé | Valeurs | Signification |
|---|---|---|
| `referentiel` | `DLNUF` \| `archive` | Type de la table. Absente ⇒ `archive`. |
| `proprietaire` | identifiant numérique de colonne Baserow | Colonne contenant l'e-mail du titulaire (obligatoire si `DLNUF`). Un identifiant reste stable si la colonne est renommée. |
| `contrat` | entier, défaut `1` | Version de ce contrat. Un lecteur qui ne connaît pas la version déclarée traite le marqueur comme invalide. |

### 3.3 Interprétation et règles de sécurité

Côté Mes-Démarches, le mode DLNUF repose sur **deux clés** : le marqueur de table et la colonne
« Champ propriétaire » de la ligne de la table méta qui déclare le référentiel (§3.4).

| Situation | Synchro (inspecteur) | Mes-Démarches |
|---|---|---|
| Pas de marqueur | archive | catalogue si la méta n'a pas de « Champ propriétaire », sinon DLNUF (méta) |
| `referentiel=archive` | archive | idem |
| `referentiel=DLNUF` valide | DLNUF | DLNUF (le « Champ propriétaire » méta, s'il est renseigné, doit désigner la même colonne, sinon **refus**) |
| `DLNUF` sans `proprietaire`, ou `proprietaire` ne désignant aucune colonne | refus de synchroniser + alerte | **refus** (jamais de repli en catalogue) |
| Marqueur invalide | refus + alerte | **refus** |
| Table méta ou colonnes de la table illisibles | — | **refus** |

**Principe :** l'absence de marqueur vaut `archive`, seul défaut sans effet irréversible côté
robot (aucun effacement). Côté MD, le défaut dangereux est l'inverse (une table DLNUF lue comme
un catalogue exposerait toutes ses lignes) : il est couvert par les deux clés du §3.4.

### 3.4 Deux clés côté Mes-Démarches, mémorisation côté synchro

**Mes-Démarches : deux clés, pas de mémorisation.** Une table est servie en DLNUF si le marqueur
**ou** la colonne « Champ propriétaire » de la table méta le déclare ; elle n'est servie en
catalogue que si **aucune des deux** ne le déclare. Une erreur sur un seul des deux endroits
(description écrasée, ligne méta modifiée) laisse donc la table protégée. Repasser en catalogue
demande deux gestes délibérés, dans deux projets Baserow distincts. MD ne mémorise rien : pas de
stockage supplémentaire, pas de remise à zéro à prévoir.

Conditions d'exploitation (obligatoires, ce sont elles qui donnent leur valeur aux deux clés) :

- la table méta et les tables DLNUF sont dans des **projets Baserow distincts** ;
- **accès administrateur seulement** à ces projets, jamais d'accès métier ;
- **jetons en lecture seule** sur la table méta (dont le jeton de Mes-Démarches) ; aucun autre
  jeton, celui du robot compris, n'a accès au projet de la table méta ;
- le marqueur n'est modifiable qu'en session utilisateur : un jeton de base de données ne peut pas
  changer la description d'une colonne (vérifié sur Baserow 2.0.6).

Limite assumée : un administrateur qui modifie les deux endroits obtient un catalogue. C'est par
construction une décision prise en connaissance de cause.

**La synchro** mémorise le type par table :

- `DLNUF → archive` (marqueur retiré) : arrêt de l'effacement + **alerte** (l'engagement de durée
  de vie n'est plus tenu) ;
- `archive → DLNUF` sur une table déjà synchronisée : **alerte et effacement suspendu** jusqu'à
  confirmation explicite de l'exploitant dans l'administration de l'inspecteur. Protège une table
  d'archive contre un effacement massif par erreur de marqueur.

Phase de test : côté synchro, ces règles ne s'appliquent pas tant que la démarche source est en test.

**Retour de `DLNUF` à `archive` sur la même table** (changer le marqueur ne convertit pas les colonnes) :

1. supprimer dans Baserow les colonnes de référence de PJ (colonnes texte marquées) ;
2. relancer le schema builder en mode `archive` : il **réécrit le marqueur de table**
   (`referentiel=archive`) et recrée les colonnes de PJ manquantes en `file` (les colonnes
   existantes, dont la colonne propriétaire, sont conservées) ;
3. vider le « Champ propriétaire » de la ligne de la table méta (seconde clé) ; tant qu'il reste
   renseigné, Mes-Démarches continue de servir la table en DLNUF ;
4. relancer la synchro depuis le début (remise du curseur de la démarche) pour copier les fichiers
   des lignes déjà présentes.

## 4. Colonnes de référence de pièce jointe

### 4.1 Marqueur de colonne

Dans une table DLNUF, une pièce jointe est représentée par une **colonne texte** dont la
description contient :

```
mes-demarches: reference=piece_justificative
```

(mêmes règles d'analyse qu'au §3.2.) Mes-Démarches s'appuie sur ce marqueur pour typer la colonne
dans l'éditeur de mapping ; il ne devine jamais une référence d'après le contenu des cellules.

### 4.2 Format d'une référence

```
md:<numero_dossier>:<stable_id>
md:<numero_dossier>:<stable_id>:<row_id>     (pièce dans un bloc répétable)
```

- `numero_dossier` : numéro du dossier MD source (entier).
- `stable_id` : `stable_id` du champ pièce justificative source dans sa démarche.
- `row_id` : identifiant de ligne du bloc répétable, si le champ en fait partie.
- **Une référence par cellule.** Cellule vide ⇒ pas de pièce. La référence désigne **le champ**,
  pas un fichier : tous les fichiers du champ source sont concernés.
- La référence **n'est pas un secret** : MD vérifie à chaque usage que le dossier source
  appartient au même titulaire (§5). Une référence forgée ne donne rien.

## 5. Responsabilités

### 5.1 Schema builder (inspecteur)

- Propose le choix **archive / DLNUF** à la création (défaut : archive).
- En DLNUF :
  - écrit le marqueur de table dans la description de la colonne primaire, avec `proprietaire`
    = identifiant de la colonne e-mail du titulaire qu'il crée ;
  - crée les colonnes de pièce jointe en **texte** avec le marqueur de colonne (§4.1), jamais en `file` ;
  - signale en erreur dans son rapport toute colonne `file` déjà présente.

### 5.2 Synchro `baserow_sync` (inspecteur)

- Lit le marqueur à chaque passage (cache court autorisé) et applique le §3.3 et le §3.4.
- En DLNUF :
  - écrit l'e-mail du **titulaire** du dossier, en minuscules, dans la colonne `proprietaire` ;
  - pour un champ PJ, écrit la **référence** (§4.2) dans la colonne marquée — **aucun
    téléversement de fichier** ;
  - **refuse** d'écrire dans une colonne `file` (erreur + alerte) ;
  - **efface** la ligne quand le dossier MD est supprimé, **par l'administration ou par l'usager** :
    - dossier détruit : flux `deletedDossiers` ;
    - dossier en construction supprimé par l'usager : flux `pendingDeletedDossiers` ;
    - dossier terminé supprimé par l'usager : il reste visible de l'administration (et dans le flux
      `dossiers`) jusqu'à sa destruction, mais son champ `dateSuppressionParUsager` est renseigné ;
      la ligne est effacée dès que ce champ l'est. L'usager ne voit plus ce dossier dans MD : ses
      données ne doivent plus lui être reproposées.
- En archive : comportement actuel inchangé (copie des fichiers, pas d'effacement).

### 5.3 Mes-Démarches

- Détermine le mode DLNUF à partir des **deux clés** (§3.3, §3.4) : le marqueur et la colonne
  « Champ propriétaire » de la table méta.
- En DLNUF : restreint recherche et lecture aux lignes du titulaire (comportement existant).
- Préremplissage de PJ (lot C) : uniquement en DLNUF, uniquement depuis une colonne marquée
  référence ; vérifie le titulaire du dossier source ; tolère les références mortes (ignorées).

## 6. Pourquoi des références plutôt que des copies de fichiers

- **Minimisation :** une seule copie de chaque pièce, dans MD, où l'accès est contrôlé
  (autorisations MD, URL signées à durée courte). Aucune copie supplémentaire dans Baserow.
- **Cohérence de durée de vie :** la pièce disparaît avec son dossier ; la référence aussi (W2).
- **Simplicité :** pas de téléchargement, pas de nouveau scan antivirus (le fichier MD a déjà été
  analysé), rattachement instantané.

## 7. Évolutions prévues (hors contrat v1)

- Préremplissage de PJ depuis un référentiel **archive** (ex. modificatif de permis plusieurs
  années après le permis, quand le dossier MD source n'existe plus) : nécessitera une source
  `fichier_baserow` et un accès aux fichiers Baserow par URL signée à durée courte. À ouvrir sur
  cas prouvé.
- Effacement optionnel en mode archive : option de synchro, à implémenter si un besoin apparaît.
- Parité Grist (projet de bascule des subventions) : mêmes marqueurs dans la description des
  colonnes Grist, à vérifier le moment venu. **Point d'attention :** l'identifiant d'une colonne
  Grist (`colId`) suit par défaut son libellé ; renommer la colonne propriétaire change donc son
  identifiant et rend `proprietaire=` caduc. Effet borné par le fail-closed (§3.3 : refus, pas de
  fuite) mais bloquant pour les usagers. À la création, le builder devra **désolidariser libellé
  et identifiant** de cette colonne (ou s'appuyer sur un identifiant interne stable, à vérifier).
