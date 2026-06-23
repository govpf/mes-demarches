# Pré-remplissage des pièces justificatives via référentiel Baserow — Spec de faisabilité

**Date :** 2026-06-05
**Statut :** Spec de faisabilité (pas de plan d'implémentation tant que non validée)
**Scope décidé :** cibles `piece_justificative` pré-remplies depuis une colonne **fichier** Baserow, via le mapping `referentiel_de_polynesie` existant
**Décision attendue :** **arbitrage avec l'option Clone** (cf. §3) — les deux ne couvrent pas le même besoin

## 1. Objectif

Permettre qu'une sélection dans un champ `referentiel_de_polynesie` (Baserow) **pré-remplisse des champs pièce justificative** du formulaire, en réutilisant le mécanisme de mapping/prefill déjà en place pour les champs scalaires.

### Use case de référence (round-trip « fiche association »)

1. Une association dépose une fiche décrivant l'asso, avec PJ **Statuts** + **PJ AG**.
2. Une synchro **externe** (hors de cette codebase) consolide la fiche dans Baserow, **en copiant les fichiers** dans une colonne fichier Baserow.
3. Plus tard, l'asso actualise sa fiche / dépose une autre démarche → en se sélectionnant dans un champ référentiel, **ses deux PJ sont rapatriées automatiquement**.

Contrainte structurante : le **dossier d'origine peut avoir été purgé pour RGPD**. La copie hébergée par Baserow est alors **la seule source durable** — ce qui élimine toute solution reposant sur le dossier d'origine ou sur notre propre blob ActiveStorage (purgé avec le dossier).

## 2. État du code (constaté, juin 2026)

**Ni upstream ni PF ne savent pré-remplir une PJ.** À développer entièrement côté PF.

- `TypeDeChamp#prefillable?` (`app/models/type_de_champ.rb` ~397-424) — whitelist des liens de préremplissage `?champ_x=…` : **exclut explicitement** `piece_justificative` et `titre_identite`. Un param PJ est filtré silencieusement (`app/models/prefill_champs.rb`, `.filter(&:prefillable?)`). Idem `upstream/main` (vérifié au 2026-06-04).
- Caster du référentiel `Champs::ReferentielChamp#call_caster` (`app/models/champs/referentiel_champ.rb` ~103-143) : **aucun cas attachment** (pas de `.attach`, `blob`, `io:`). Une cible PJ tombe dans `else → nil` → aucune écriture aujourd'hui.
- L'intégration Baserow de l'app est **en lecture seule** (`ReferentielDePolynesie::BaserowAPI`, `Typhoeus.get`). La synchro dossier → Baserow (étape 2) est **externe**.

**Brique réutilisable (clé) :** le pattern « URL distante → attachment » existe déjà — `Etablissement#upload_attestation` (`app/models/etablissement.rb` ~185-205) : `Typhoeus.get(url)` + `attachment.attach(io: StringIO.new(body), filename:, metadata:)`. Une différence majeure ici (cf. §4) : on **ne** reprend **pas** le `virus_scan_result: SAFE` de cette méthode.

**Attachment PJ :** `has_many_attached :piece_justificative_file` (`app/models/champs/piece_justificative_champ.rb:6`), max 200 Mo, content-types `AUTHORIZED_CONTENT_TYPES`.

## 3. Arbitrage avec l'option Clone (cœur de la décision)

Les deux approches **ne sont pas concurrentes** : elles répondent à deux besoins distincts.

| | **Clone (« repartir d'un dossier »)** | **Prefill référentiel Baserow (cette spec)** |
|---|---|---|
| Mécanisme | Natif (`DossierCloneConcern` + `ClonePiecesJustificativesService.clone_attachments`) | Nouveau dev (~3-5 j) |
| Coût dev | ~0 | ~3-5 j |
| Périmètre | **Même démarche** — `clone` recopie `revision_id` (`app/models/concerns/dossier_clone_concern.rb:12`), donc reste sur la même révision | **Cross-démarches** — la fiche Baserow alimente n'importe quelle démarche |
| Partage inter-démarches | ❌ impossible par construction | ✅ **unique mécanisme** |
| Source | Dernier dossier brut de l'usager | Fiche consolidée / curée (Baserow) |
| Condition de viabilité | Le dossier source doit exister → **rétention** ≥ cadence (ex. 15 mois ⇒ AG annuelle OK) | La synchro externe a copié le fichier dans Baserow |
| Découvrabilité usager | Faible (démarche explicite à initier) — atténuable par **mail auto + lien de clonage** piloté par le robot | Forte (déclenchement passif à la sélection de l'asso) |
| RGPD | PII gardée dans DS le temps de la rétention | PII **relocalisée** dans Baserow (déplacée, pas réduite) — à gouverner |

**Conséquence :**
- Besoin **« reconduction de la même démarche »** (re-dépôt annuel) → **Clone** (+ mail/lien robot pour la découvrabilité). Le présent dev n'est pas nécessaire.
- Besoin **« mutualiser des infos collectées à travers plusieurs démarches »** → **Prefill référentiel = unique voie**. C'est ce qui justifie ce dev.

Cette spec ne se justifie donc **que pour le second besoin**. Si seul le premier est visé, recommander Clone.

## 4. Décisions verrouillées

- **Antivirus : RE-SCAN systématique.** On **ne** force **pas** `virus_scan_result: SAFE` (contrairement à `upload_attestation`). Justification : la source Baserow est éditable par un agent et a pu être remplacée — on ne peut pas garantir le fichier. La PJ n'est exploitable qu'après scan normal.
- **Échec gracieux.** URL morte, content-type non autorisé, dépassement de taille, scan KO → **skip + log**, sans casser le reste du prefill (les champs scalaires se remplissent quand même).
- **Idempotence.** Sur re-sélection : **purger** les PJ existantes **uniquement si** le champ est `prefilled?` ; ne **rien** toucher si l'usager a uploadé manuellement.
- **Asynchrone assumé.** Download + attach + scan dans un job (jamais inline dans la requête de saisie). UI dégradée acceptée → état temporaire sous le champ.

## 5. Architecture proposée (isolée, sans refactor)

### 5.1 Point d'insertion

`Champs::ReferentielChamp#update_prefillable_champ` (`app/models/champs/referentiel_champ.rb` ~236-240). Attacher un fichier ≠ affecter un attribut → `cast_value_for_type_de_champ` (qui retourne un hash pour `.update`) ne convient pas. On **branche** sur le type cible :

```ruby
def update_prefillable_champ(type_de_champ:, raw_value:, row_id: nil)
  prefill_champ = dossier.champ_for_update(type_de_champ, row_id:, updated_by: :api)
  if type_de_champ.type_champ.to_sym == :piece_justificative
    PrefillPieceJustificativeJob.perform_later(prefill_champ, Array(raw_value)) # async (§5.3)
  else
    prefill_champ.update(cast_value_for_type_de_champ(raw_value, type_de_champ))
  end
end
```

> Les champs scalaires restent inline (rapides) ; seules les PJ partent en job.

### 5.2 Forme de la donnée source

Colonne **fichier** Baserow → tableau d'objets `[{ url, name, mime_type }, …]`. Le `has_many_attached` accueille naturellement plusieurs fichiers. Le jsonpath du mapping pointe vers cette colonne (comme pour les autres mappings).

### 5.3 Job de download / attach / scan

```ruby
# 1. idempotence : purge UNIQUEMENT si prefilled
prefill_champ.piece_justificative_file.purge_later if prefill_champ.prefilled?

# 2. download + attach + RE-SCAN (pas de virus_scan_result: SAFE)
Array(files).each do |file|
  resp = Typhoeus.get(file[:url], timeout: …)
  next unless resp.success?                       # échec gracieux
  io = StringIO.new(resp.body)
  next unless authorized_content_type?(file[:mime_type]) # échec gracieux
  prefill_champ.piece_justificative_file.attach(io:, filename: file[:name])
rescue => e
  Sentry.capture_exception(e)                     # skip + log, on continue
end

# 3. marquer prefilled + déclencher refresh UI
prefill_champ.update(prefilled: true)
```

Le scan antivirus ActiveStorage tourne ensuite via le flux normal (la PJ reste « en cours de vérification » jusqu'à `virus_scan_result` final).

### 5.4 Feedback UI (asynchrone)

- Sous le champ PJ, état temporaire : **« Les pièces justificatives sont en cours de téléchargement… patientez »**, puis **« vérification du fichier… »** pendant le scan (le délai cumule download **et** scan — l'état doit couvrir les deux).
- **Réutiliser le canal de refresh existant** : le flux *exact-match* du référentiel met déjà à jour le champ en async (`update_external_data!` → `app/models/champs/referentiel_de_polynesie_champ.rb`). On rediffuse le composant champ (Turbo Stream) quand le job a terminé. Pas de mécanisme nouveau à inventer.

### 5.5 Éditeur de mapping

- Autoriser `piece_justificative` comme type cible (`prefill_stable_id`) dans la config du `referentiel_mapping`.
- **Validation** : cible PJ ⇒ la colonne source doit être de **type fichier** Baserow. (S'aligne sur la logique d'éligibilité décrite dans `2026-06-03-mcp-referentiel-mapping-design.md` §4.)

## 6. Tests

- **Unitaire** : Typhoeus stubbé (succès / 404 / type non autorisé) → attach ou skip ; idempotence (purge si `prefilled`, no-op sinon) ; `prefilled: true` posé.
- **Système (Capybara) — indispensable** : sélection au référentiel → état *pending* affiché → PJ attachée et **remplaçable** par l'usager. C'est exactement la chaîne de propagation (sélection → job → refresh) où les bugs se logent ; un test système est requis (cf. politique de tests système sur les chaînes de déclenchement).

## 7. Estimation

| Lot | Charge |
|---|---|
| Backend (branche PJ + job download/attach/scan/purge + échec gracieux) | ~1-2 j |
| UI (état pending download+scan, refresh Turbo) + éditeur de mapping (cible PJ + validation colonne fichier) | ~1-2 j |
| Tests (unitaire + système) | ~1 j |
| **Total** | **~3-5 j** |

## 8. Points ouverts / risques

- **Gouvernance RGPD de Baserow** : ce dev relocalise de la PII (les fichiers) dans Baserow. À cadrer : rétention, accès, base légale — c'est un *system-of-record* à part entière, pas un simple cache.
- **Autorisation / fuite** : s'assurer que la ligne de référentiel rapatriée appartient bien à l'usager/asso qui la sélectionne (pas d'accès aux PJ d'une autre asso via une sélection arbitraire).
- **Poids / timeout** : fichiers jusqu'à 200 Mo + scan → le job doit être robuste (retry, timeout généreux) ; l'état pending peut durer.
- **Dépendance synchro externe** : la qualité du prefill dépend de ce que la synchro écrit dans Baserow (URL valide, fichier réellement copié, type autorisé). Hors périmètre de ce dev mais condition de bon fonctionnement.

## 9. Affichage de PJ — hors périmètre (et pourquoi)

Question soulevée (juin 2026) : un champ référentiel sert traditionnellement soit à
**pré-remplir**, soit à **afficher** une donnée à l'usager/l'instructeur. Doit-on
aussi pouvoir **afficher** une PJ issue du référentiel (à côté du prefill) ?

**Décision : non. L'affichage de PJ est explicitement hors périmètre.** On autorise le
prefill de PJ (cette spec) mais on **n'expose pas** les colonnes fichier comme colonnes
*displayable* (config d'affichage usager/instructeur).

### Raisonnement (immuabilité)

Pour un **scalaire**, l'immuabilité est gratuite : la valeur Baserow est recopiée dans
`value_json` à la sélection et figée au dépôt — même si Baserow change ensuite, le
dossier garde sa copie.

Pour un **fichier**, il n'existe **aucun équivalent à un « lien live immuable »** :

- soit on **copie les octets** dans le stockage du dossier → immuable, mais c'est
  *exactement* le mécanisme de prefill décrit ici (la PJ devient une pièce normale du
  dossier, figée au dépôt) ;
- soit on **pointe vers le fichier Baserow** (lien) → **mutable** : l'instructeur
  pourrait voir un fichier différent de celui « déposé », ce qui casse l'immuabilité
  légale.

Conséquence : « afficher une PJ de façon immuable » **se réduit à « copier la PJ »**.
Pour les fichiers, prefill et affichage-immuable **convergent** ; il n'y a pas de
troisième voie. Le seul « affichage » distinct serait un **lien live assumé non figé**,
sans valeur de pièce déposée.

### Pourquoi ne pas trancher maintenant

Pas de use case terrain solide pour l'affichage de PJ à ce jour (le seul candidat —
référencer un permis de construire — porte sur un objet qui sera lui-même déjà devenu
immuable). On **limite donc la fonction** pour la faire évoluer le jour où le besoin
réel se présentera, plutôt que de coder spéculativement la gestion « figé vs live ».

### Bénéfice de cadrage

En n'offrant **aucun chemin d'affichage live**, on supprime **tout trou d'immuabilité
possible** : la seule PJ qui peut exister dans un dossier est une copie snapshotée
(immuable par construction). Aucun arbitrage figé/live n'est nécessaire aujourd'hui ; la
porte reste ouverte (read-only figé *ou* lien live) pour un futur use case.

### Implication d'implémentation (un seul garde-fou)

Dans l'éditeur de mapping (`referentiel_mapping`) : une colonne de **type fichier**
Baserow est éligible comme **cible de prefill** (`prefill_stable_id` → champ PJ) mais
**jamais** listée comme colonne *displayable*. Un type, deux traitements — cohérent avec
la logique d'éligibilité de `2026-06-03-mcp-referentiel-mapping-design.md` §4.
