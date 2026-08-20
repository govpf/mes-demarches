# Devis — Référentiel de Polynésie : filtrage contextuel, « Dites-le-nous une fois » et préremplissage de pièces jointes

**Date :** 2026-07-21
**Statut :** devis figé (design verrouillé, prêt pour plan d'implémentation)
**Specs sources :** `2026-06-17-referentiel-polynesie-filtres-contextuels-design.md`, `2026-06-05-prefill-piece-justificative-referentiel-design.md`
**Objet :** ajuster et cadrer la charge de développement pour trois besoins autour du champ `referentiel_de_polynesie`, réorganisés autour de leur vraie ligne de partage.

---

## 1. Contexte

Le champ `referentiel_de_polynesie` cherche aujourd'hui dans une table Baserow sur un seul
critère : le terme `q` tapé par l'usager (`contains` sur la colonne « champ de recherche »).
Trois besoins terrain se sont exprimés :

- **Semences** (démarche existante, **mise en prod imminente**) : restreindre les lignes
  sélectionnables en fonction d'un **autre champ du dossier** (ex. « Semences » → seules les
  lignes Semences sont proposées).
- **Subventions** (7-8 démarches, **horizon ~3 mois**) : préremplir un dossier avec les
  **données déjà saisies par l'usager sur d'autres démarches**. Le référentiel Baserow sert
  de **vocabulaire commun** entre des démarches qui n'ont ni les mêmes champs ni le même
  libellé — chacune y pioche ce qu'elle veut préremplir. Principe « Dites-le-nous une fois ».
- **Pièces jointes** : que la sélection au référentiel puisse aussi **préremplir des champs
  pièce justificative** (ex. fiche association : Statuts + PV d'AG rapatriés automatiquement).

### Réorganisation par rapport au découpage initial (F1/F2)

Le premier découpage (F1 prefill PJ / F2 filtre) coupait au mauvais endroit. La ligne de
partage réelle est **la nature de la donnée** :

| Question | Réponse | Conséquence |
|---|---|---|
| Ces données appartiennent-elles à un usager ? | **Oui** → « Dites-le-nous une fois » | scope intrinsèque sur le mail titulaire, ergonomie prefill |
| | **Non** → catalogue partagé | recherche plein-texte, + éventuelle cascade |

Cette distinction est **intrinsèque à la donnée**, donc **définie dans Baserow** (table méta
des référentiels), **pas** dans l'interface d'administration → **transparente pour le créateur
de formulaire**. À l'inverse, la **cascade** (rétrécir par un autre champ) est une **relation
de formulaire**, donc configurée côté admin. C'est la même règle que celle appliquée
historiquement aux colonnes « affichées usager/instructeur » (sorties de Baserow vers l'admin
car non intrinsèques).

---

## 2. Décisions de design verrouillées

### 2.1 Détection du mode (intrinsèque, dans Baserow)

- La **table méta** des référentiels (qui stocke déjà : nom affiché, id de base + token,
  **id du champ de recherche**) reçoit **une nouvelle colonne nullable « champ propriétaire »**,
  contenant l'**id du champ e-mail propriétaire** (même mécanisme que l'id de recherche).
- Invariant : **`champ propriétaire` renseigné ⟺ mode « Dites-le-nous une fois »** ;
  vide ⟺ catalogue. Pas de booléen séparé — la présence de l'id **est** la désignation.
- Identification par **id de champ** (stable, survit au renommage), jamais par nom de colonne.

### 2.2 Clé d'identité = mail du titulaire (non négociable)

- La seule ancre non-usurpable est le **compte** ; son identifiant durable est le **mail**.
  DN, SIRET, etc. sont des **données déclarées** par l'usager (usurpables) → **exclus** comme
  clé de scope (les utiliser serait une autorisation choisie par l'usager lui-même = faille
  horizontale).
- Scope = **`dossier.user.email` (titulaire)**, pas l'utilisateur connecté : un **invité** qui
  co-remplit doit préremplir avec les données du **titulaire**, pas les siennes. Le transfert
  de dossier fonctionne par construction (le scope est relu à la volée).
- **Canonicalisation garantie** : c'est mes-demarches qui alimente le mail dans Baserow
  (normalisé en minuscules). La clé est la même chaîne aux deux bouts — fiable par construction.
- Changement de mail : les dossiers suivent le `user` ; seul Baserow décroche jusqu'à
  resynchronisation (rare, contournable, hors code).

### 2.3 Sûreté par construction (fail-closed partout)

- La **valeur source n'est JAMAIS lue depuis le client** : résolue côté serveur depuis la
  session / le dossier persisté.
- **Champ propriétaire mort** (id pointant vers un champ supprimé/introuvable) → **refus
  d'exposer** (« configuration référentiel invalide » + alerte), **jamais** de repli en
  catalogue ouvert. La suppression de la colonne propriétaire ne doit pas pouvoir déclasser
  des données personnelles en liste publique.
- **Source vide** (cascade : champ pilote non rempli) → **retour vide** + message
  « Renseignez d'abord *<libellé source>* », jamais le référentiel complet.
- Deux remparts indépendants : à la **sélection** (`#search` filtré côté serveur) et au
  **dépôt** (validation locale, cf. 2.5).

### 2.4 Ergonomie DLNUF ≠ recherche

- Le cas « mes données » n'est pas une recherche : à l'ouverture/au focus, **lister les 0/1/N
  lignes de l'usager**, **auto-remplir si une seule ligne**. L'endpoint doit accepter un `q`
  **vide** lorsqu'un scope est présent (aujourd'hui `q` vide → HTTP 400).
- Aucun message n'écho le mail (« Aucune donnée enregistrée à votre nom », pas
  « Aucun résultat pour xxx@yyy.com »).

### 2.5 Cascade : validation non-destructive (anti-stale)

- Si l'usager change le champ pilote **après** sélection (« Semences » → « Plants »), on **ne
  réinitialise PAS** (éviter la perte de données sur un clic, notamment en répétition).
- Validation **locale au dépôt** : comparer `row_data[colonne]` (déjà stocké dans le champ) à
  la valeur source résolue ; si divergence → **erreur bloquante sur ce champ précis**. Aucun
  appel Baserow au dépôt.

### 2.6 Préremplissage de pièces jointes

- Point d'insertion : `Champs::ReferentielChamp#update_prefillable_champ` (branche dédiée PJ,
  car attacher un fichier ≠ affecter un attribut).
- **Job asynchrone** : download (`Typhoeus.get`) + `attach` + **re-scan antivirus**
  (on ne force **pas** `virus_scan_result: SAFE` — la source Baserow a pu être modifiée).
- **Idempotence** : purger les PJ existantes **uniquement si** le champ est `prefilled?` ; ne
  rien toucher si l'usager a uploadé manuellement.
- **Échec gracieux** : URL morte / type non autorisé / taille / scan KO → skip + log, sans
  casser le reste du prefill.
- **Affichage de PJ issue du référentiel = hors périmètre** (décidé) : une colonne fichier est
  cible de prefill mais **jamais** exposée comme colonne *displayable* (raisonnement
  immuabilité : pour un fichier, « immuable » = copier les octets = c'est déjà le prefill ; un
  lien live serait mutable → casse l'immuabilité légale).

---

## 3. Lots et charges

| Lot | Contenu | Charge |
|---|---|---|
| **Socle** | `champ_id` transmis à l'endpoint `#search` ; autorisation 403 (le dossier doit appartenir au user) ; résolution serveur de la valeur source (`Column#value`) ; injection du filtre en `AND` dans `build_search_filters` ; opérateur par type de colonne Baserow ; fail-closed générique ; lecture de la config méta (« champ propriétaire ») comme l'id de recherche existant | **~2 j** |
| **A — Catalogue + cascade** *(prod imminente — Semences)* | Config côté formulaire du champ pilote (colonne du dossier, filtrée sur `type ∈ {text, enum, enums}`) ; cascade ; **validation non-destructive anti-stale** ; état vide simplifié (2 messages, jamais masquer) ; tests système (cascade) + sécurité (request : 403, fail-closed, `q` libre) + unitaires | **~2,5-3 j** |
| **B — Dites-le-nous une fois** *(~3 mois — subventions)* | Détection du mode via « champ propriétaire » (table méta) + **fail-closed si id mort** + diagnostic (le champ existe et ressemble à un mail) ; scope titulaire `dossier.user.email` intrinsèque ; endpoint acceptant `q` vide quand scopé ; ergonomie liste / **auto-fill si 1 ligne** au focus ; messages n'échoant jamais le mail ; tests | **~2,5-3 j** |
| **C — Préremplissage PJ** *(avec B — fiche association)* | Branche PJ dans `update_prefillable_champ` ; job async download/attach/**re-scan**/purge idempotente + échec gracieux ; UI d'attente (download + scan) via refresh Turbo existant ; éditeur de mapping (cible PJ + validation colonne fichier) ; tests unitaires + système | **~4-5 j** |

---

## 4. Scénarios de facturation

Le **Socle** n'est payé qu'une fois ; il est porté par le premier chantier livré.

| Chantier | Composition | Charge |
|---|---|---|
| **Court terme — « Semences »** | Socle + A | **~4,5-5 j** |
| **Fiche association / subventions** | (Socle amorti) + B + C | **~6,5-8 j** |
| **Tout, séquencé** | Socle + A + B + C | **~9-11 j** |

**Option** — diagnostic admin étendu (tableau de bord distinguant « 0 ligne » d'un mauvais
mapping mail sur un référentiel DLNUF) : **~+0,5 j** (le minimum vital est déjà dans B).

---

## 5. Invariants de sécurité (transversaux, à ne pas déprioriser)

1. Valeur source **jamais** lue depuis le client — résolution serveur (session/dossier).
2. Clé DLNUF = **mail du titulaire** ; DN/SIRET exclus comme clé (déclarés, usurpables).
3. DLNUF **fail-closed** si le champ propriétaire est manquant/mort — jamais de repli catalogue.
4. Cascade source vide → retour vide (fail-closed), jamais le référentiel complet.
5. Deux remparts : filtre serveur à la sélection **et** validation locale au dépôt.
6. Prefill PJ : **re-scan antivirus** systématique (pas de `SAFE` forcé).

---

## 6. Hors périmètre (à cadrer séparément, hors code applicatif)

- **Synchro externe** dossier → Baserow (précondition des deux usages ; l'app est en lecture
  seule sur Baserow).
- **Gouvernance RGPD de Baserow** : ce système devient un *system-of-record* de PII (rétention,
  accès, base légale) — décision de gouvernance, pas de dev.
- **Affichage** de PJ issue du référentiel (décision verrouillée : hors périmètre).
- Multi-règles de filtre (résolu par formule côté dossier + colonne équivalente Baserow).
- Colonnes source non-texte (date, nombre).

---

## 7. Hypothèses et risques résiduels

- **`form_filterable_columns` / `usager_filterable_columns`** : catalogue de colonnes pilotes à
  localiser (non trouvé dans `procedure.rb` lors de l'audit) — risque mineur d'adaptation.
- **Robustesse du job PJ** : fichiers jusqu'à 200 Mo + scan → timeout généreux + retry ; l'état
  « en cours » peut durer (budget inclus dans le haut de fourchette du lot C).
- **Cache de la config méta** : si la config référentiel est mise en cache côté app, invalider
  au changement de « champ propriétaire » (sinon fenêtre courte de scope obsolète).
- **Dépendance qualité synchro** : la valeur du prefill dépend de ce que la synchro écrit dans
  Baserow (URL valide, fichier réellement copié, mail normalisé) — hors périmètre mais
  condition de bon fonctionnement.

---

## 8. Fichiers principaux concernés (indicatif)

- `app/models/types_de_champ/referentiel_de_polynesie_type_de_champ.rb`
- `app/models/champs/referentiel_de_polynesie_champ.rb` / `app/models/champs/referentiel_champ.rb`
  (`update_prefillable_champ`, validation non-destructive)
- `app/controllers/data_sources/referentiel_de_polynesie_controller.rb`
  (`champ_id`, autorisation, résolution source, fail-closed, `q` vide si scopé)
- `app/lib/referentiel_de_polynesie/baserow_api.rb`
  (`build_search_filters`, opérateur par type, lecture « champ propriétaire » de la table méta)
- `app/components/editable_champ/referentiel_de_polynesie_component*` (loader `champ_id`,
  ergonomie liste/auto-fill DLNUF, état vide)
- Éditeur de mapping (`referentiel_mapping`) — cible PJ + colonne pilote de cascade
- Job `PrefillPieceJustificativeJob` (nouveau)
