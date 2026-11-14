# Lot C « préremplissage des PJ par référence MD » — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** quand l'usager sélectionne sa ligne dans un référentiel DLNUF, les champs « pièce justificative » mappés sur une colonne de référence reçoivent les fichiers du champ désigné dans un autre dossier du même titulaire (rattachement synchrone du blob existant).

**Architecture :**
- Une fonction de détection, `API.colonnes_reference_pj`, sert à l'éditeur web, au MCP et à la règle de validation. Elle ne répond que pour une table DLNUF dont la colonne porte le marqueur `reference=piece_justificative`.
- Une règle unique, `MappingPieceJustificative.erreurs`, rejette côté serveur tout mapping PJ invalide.
- Au préremplissage, une branche dans `ReferentielChamp#update_prefillable_champ` délègue au service `PrefillPieceJustificative`, qui vérifie la référence et le titulaire puis rattache les blobs.

**Tech Stack :** Rails 7, ActiveStorage (blob partagé), RSpec, Capybara/Playwright (headless).

**Spec :** `docs/superpowers/specs/2026-11-06-prefill-piece-justificative-reference-md-design.md` §4 à §9 ; contrat `docs/superpowers/specs/2026-11-06-contrat-referentiel-dlnuf.md` §4.

## Global Constraints

- Spécificités PF marquées `# pf:` ; fichiers upstream modifiés **en place** (le conflit au prochain bump sert de capteur), jamais d'override séparé.
- Textes d'interface : apostrophe typographique `’`.
- Marqueur de colonne : `mes-demarches: reference=piece_justificative` (analysé par `ReferentielDePolynesie::Marqueur.parse`, déjà en place).
- Référence : `\Amd:(\d+):(\d+)(?::([A-Za-z0-9_-]+))?\z` (numéro de dossier, stable_id, row_id facultatif). Une référence désigne le champ, donc tous ses fichiers.
- Préremplissage de PJ **uniquement** en DLNUF (`API.dlnuf_config` renvoie un Hash). Cible `piece_justificative` seulement, jamais `titre_identite`, en source comme en cible.
- Pas de nouveau scan antivirus : on exclut les blobs `infected?` ou `corrupt?` (`ActiveStorage::VirusScanner`).
- Dépôt public : aucune mention de faille de sécurité dans le code, les commits ou la PR.
- Tests : specs ciblées en local, système en headless (`NO_HEADLESS=`), le reste via la CI.

## Review Focus

1. **Référentiel désélectionné ou ligne sans référence** : la cible préremplie doit être vidée, et une cible remplie à la main ne doit pas être touchée. → Task 3, tests « référence vide ».
2. **Dossier source déposé puis supprimé par l'usager**, y compris un dossier terminé encore visible de l'administration : aucun rattachement. → Task 3, test « source cachée par l'usager (terminée) ».
3. **Titulaire sans compte (`user` nil) côté source ou cible** : arrêt sans exception. → Task 3.
4. **PJ cible dans un bloc répétable alors que le référentiel est à la racine** : le chemin upstream (`update_repetition_prefillable_champs`) ajouterait une ligne au bloc à chaque sélection. Hors périmètre (spec §9) : refusé par la règle serveur. → Task 2, règle 5.
5. **Admin qui forge un mapping `string` vers une cible PJ** (ou `piece_justificative` vers une cible texte) : rejet côté serveur, et aucun rattachement au préremplissage si la configuration passe malgré tout. → Task 2 (règle), Task 4 (la branche se décide sur le type de la cible, et le service revérifie le mode DLNUF).

---

### Task 1 : détection des colonnes de référence et type `piece_justificative` dans l'éditeur

**Files :**
- Modify : `app/lib/referentiel_de_polynesie/api.rb` (nouvelle méthode)
- Modify : `app/models/referentiel.rb` (méthode par défaut), `app/models/referentiels/baserow_referentiel.rb`
- Modify : `app/components/referentiels/mapping_form_component.rb` (`TYPES`, `cast_tag`)
- Modify : `app/components/referentiels/referentiel_prefill_component.rb` (`MAPPING_TYPE_TO_TYPE_DE_CHAMP`)
- Modify : `app/components/referentiels/referentiel_display_component.rb` (`display_mapping`)
- Modify : `config/locales/*` : clé `utils.piece_justificative` (fr : « Pièce justificative », en : « Supporting document »), à côté des autres `utils.<type>`
- Test : `spec/lib/referentiel_de_polynesie/api_spec.rb`, `spec/components/referentiels/mapping_form_component_spec.rb`, `spec/components/referentiels/referentiel_display_component_spec.rb`, `spec/components/referentiels/mapping_type_constant_canary_spec.rb`

**Interfaces :**
- Produces :
  - `ReferentielDePolynesie::API.colonnes_reference_pj(domain_id) -> Array<String>` : noms des colonnes dont la description porte `reference=piece_justificative` (valeur comparée sans casse), **seulement si** `dlnuf_config(domain_id)` est un Hash ; `[]` sinon (catalogue, `:invalid`, Baserow muet). Utilise `table_fields` (cache court) et `Marqueur.parse` ; un marqueur de colonne `:invalid` compte comme non marqué.
  - `Referentiel#jsonpaths_reference_pj -> Array<String>` (`[]` par défaut, `# pf:`) ; `Referentiels::BaserowReferentiel#jsonpaths_reference_pj` → `colonnes_reference_pj(table_id).map { "$.#{_1}" }` (mémoïsé dans l'instance).
  - `Referentiels::MappingFormComponent::TYPES[:piece_justificative]`.
  - `MAPPING_TYPE_TO_TYPE_DE_CHAMP[:piece_justificative] == %w[piece_justificative]`.

- [ ] **Step 1 : specs en échec.**
  - `api_spec` : avec `dlnuf_config` = Hash et `table_fields` = `{ 1 => { name: 'Statuts', description: "mes-demarches: reference=piece_justificative" }, 2 => { name: 'Nom', description: nil }, 3 => { name: 'RIB', description: 'mes-demarches: reference=autre' } }`, on obtient `['Statuts']`. Avec `dlnuf_config` = nil ⇒ `[]`, = `:invalid` ⇒ `[]`, `table_fields` nil ⇒ `[]`.
  - `mapping_form_component_spec` : sur une ligne `$.Statuts` dont le référentiel renvoie `jsonpaths_reference_pj == ['$.Statuts']`, il n'y a **pas** de `select` de type. Il y a un champ caché `type_de_champ[referentiel_mapping][$.Statuts][type]` de valeur `piece_justificative` et le texte « Pièce justificative ». Sur `$.Nom`, la liste déroulante ne propose pas `piece_justificative`.
  - `referentiel_display_component_spec` : une entrée `{ 'type' => 'piece_justificative', 'prefill' => '0' }` n'est pas rendue.
  - Canari : `subject[:piece_justificative] == ['piece_justificative']`.
- [ ] **Step 2 :** `bundle exec rspec spec/lib/referentiel_de_polynesie/api_spec.rb spec/components/referentiels` → échecs attendus.
- [ ] **Step 3 : implémenter.**
  - Dans `cast_tag`, si `referentiel.jsonpaths_reference_pj.include?(jsonpath)` : `hidden_field_tag(attribute_name(jsonpath, 'type'), 'piece_justificative')` + libellé traduit.
  - Sinon, la liste reprend `TYPES` **sans** `piece_justificative`.
  - `display_mapping` exclut les entrées de type `piece_justificative`.
- [ ] **Step 4 :** relancer → vert.
- [ ] **Step 5 :** commit `feat(referentiel): type de mapping pièce justificative sur les colonnes de référence DLNUF`.

### Task 2 : règle serveur du mapping PJ (éditeur web et MCP)

**Files :**
- Create : `app/lib/referentiel_de_polynesie/mapping_piece_justificative.rb`
- Modify : `app/controllers/administrateurs/referentiels_controller.rb` (`update_mapping_type_de_champ`, `update_prefill_and_display_type_de_champ`)
- Modify : `app/services/mcp/referentiel_mapping_service.rb` (`colonnes_pour_table`, `mapping_type_for`, `configurer!`)
- Test : `spec/lib/referentiel_de_polynesie/mapping_piece_justificative_spec.rb`, `spec/controllers/administrateurs/referentiels_controller_spec.rb`, `spec/services/mcp/referentiel_mapping_service_spec.rb`

**Interfaces :**
- Consumes : `API.colonnes_reference_pj` (Task 1).
- Produces : `ReferentielDePolynesie::MappingPieceJustificative.erreurs(type_de_champ:, mapping:) -> Array<String>` (messages en français, vide = valide). `mapping` = Hash jsonpath → options (clés chaînes). La révision sert à résoudre `prefill_stable_id` : `type_de_champ` étant un TDC de la révision brouillon, prendre `procedure.draft_revision.types_de_champ`.

Règles (une erreur par entrée fautive, avec le nom de la colonne) :
1. Entrée de type `piece_justificative` dont le jsonpath ne figure pas dans `"$." + colonnes_reference_pj(type_de_champ.table_id)` ⇒ « La colonne « X » n’est pas une colonne de référence de pièce justificative d’un référentiel DLNUF. »
2. Entrée de type `piece_justificative` avec `display_usager` ou `display_instructeur` égal à `"1"` ⇒ refus (pas d'affichage de référence).
3. Entrée dont `prefill_stable_id` désigne un TDC `piece_justificative` ou `titre_identite` alors que son type n'est pas `piece_justificative` ⇒ refus.
4. Entrée de type `piece_justificative` avec un `prefill_stable_id` désignant un TDC qui n'est pas `piece_justificative` ⇒ refus.
5. Entrée de type `piece_justificative` dont la cible est dans un bloc répétable (`revision.parent_of(cible)` présent) **différent** de celui du référentiel ⇒ refus. La seule configuration en bloc admise : référentiel et PJ dans la même ligne (spec §9).

Les entrées sans rapport avec les PJ ne déclenchent aucun appel à Baserow : on court-circuite si aucune entrée n'est de type `piece_justificative` et si aucune cible n'est une PJ.

- [ ] **Step 1 : spec de la règle en échec**, un exemple par règle et un exemple « mapping sans PJ ⇒ `[]` sans appel à `colonnes_reference_pj` ».
- [ ] **Step 2 : specs contrôleur en échec.** Un `update_mapping_type_de_champ` et un `update_prefill_and_display_type_de_champ` avec un mapping fautif :
  - ils ne modifient pas `referentiel_mapping` ;
  - ils redirigent vers l'étape courante avec `flash[:alert]` contenant le message.
- [ ] **Step 3 : spec MCP en échec.**
  - `colonnes_pour_table` expose `type_mapping: 'piece_justificative'` pour une colonne de référence d'une table DLNUF, et `'string'` hors DLNUF.
  - `configurer!` lève `CibleInvalide` pour `display_usager: true` sur cette colonne, et pour une cible PJ sur une colonne `string`.
- [ ] **Step 4 :** `bundle exec rspec spec/lib/referentiel_de_polynesie/mapping_piece_justificative_spec.rb spec/controllers/administrateurs/referentiels_controller_spec.rb spec/services/mcp/referentiel_mapping_service_spec.rb` → échecs.
- [ ] **Step 5 : implémenter.**
  - **Contrôleur** : calculer le mapping fusionné (`safe_referentiel_mapping.deep_merge(...)`), appeler `erreurs` **avant** `update`, et rediriger avec `alert: erreurs.join(' ')` s'il y en a.
  - **MCP** :
    - `mapping_type_for(field)` renvoie `'piece_justificative'` si le nom figure dans `colonnes_reference_pj(@tdc.table_id)`. Faire de même dans `colonnes_pour_table(table_id)`.
    - `configurer!` appelle `erreurs` sur le mapping final et lève `CibleInvalide` avec le premier message.
    - `valider_cible!` fonctionne déjà avec la nouvelle clé de `MAPPING_TYPE_TO_TYPE_DE_CHAMP`.
  - La mutation GraphQL `demarcheConfigurerReferentielMapping` délègue au service : rien à changer. Vérifier seulement qu'aucune description d'argument n'est à mettre à jour ; sinon, `bin/rails graphql:schema:dump`.
- [ ] **Step 6 :** relancer → vert.
- [ ] **Step 7 :** commit `feat(referentiel): règle serveur du mapping pièce justificative (éditeur et MCP)`.

### Task 3 : service `PrefillPieceJustificative`

**Files :**
- Create : `app/lib/referentiel_de_polynesie/prefill_piece_justificative.rb`
- Test : `spec/lib/referentiel_de_polynesie/prefill_piece_justificative_spec.rb`, `spec/models/champs/piece_justificative_blob_partage_spec.rb` (reprise de la vérification du 2026-11-06, ci-dessous)

**Interfaces :**
- Produces : `ReferentielDePolynesie::PrefillPieceJustificative.new(referentiel_champ:, cible:, reference:).call -> Symbol`. Le symbole renvoyé sert aux tests et aux logs :

| Retour | Cas |
|---|---|
| `:non_dlnuf` | `dlnuf_config(referentiel_champ.table_id)` n'est pas un Hash |
| `:reference_illisible` | la référence ne correspond pas à l'expression |
| `:source_introuvable` | dossier inexistant, caché par l'usager (`visible_by_user`), en brouillon, ou égal au dossier cible |
| `:autre_titulaire` | e-mails différents (`casecmp?`), ou `user` absent d'un côté ; envoie `Sentry.capture_message('ReferentielDePolynesie: référence de PJ d’un autre titulaire', extra: { cible_dossier_id:, source_dossier_id: })` sauf si un `user` manque |
| `:cible_manuelle` | cible non vide et non `prefilled?` |
| `:rattache` | rattachement fait (au moins une pièce) |
| `:vide` | aucune pièce à rattacher ; la cible préremplie a été vidée |

Ordre des étapes (spec §5.2) :
1. **Garde DLNUF.**
2. **Référence** : vide ou `nil` ⇒ liste de blobs vide, on passe directement à l'étape 6.
3. **Source.**
4. **Titulaire.**
5. **Champ source** :
   - TDC de `stable_id` dans `source.revision`, de type `piece_justificative` uniquement ;
   - lu par `source.project_champ(tdc, row_id:)` ;
   - TDC absent ou d'un autre type ⇒ liste vide.
6. **Idempotence** : cible vide, ou `prefilled?` ⇒ `piece_justificative_file.purge_later` des pièces existantes ; sinon `:cible_manuelle`. Puis `attach` de chaque blob de la source qui n'est ni `infected?` ni `corrupt?` (`blob.virus_scanner`).
7. `cible.update!(prefilled: blobs_rattaches.any?)`.

Décision : `prefilled` repasse à faux quand la cible est vidée. Un champ vide n'est plus « prérempli », et l'ajout manuel qui suit ne sera pas écrasé.

- [ ] **Step 1 : spec du service en échec.** Mise en place :
  - un `user` ;
  - une démarche source publiée avec un TDC `piece_justificative` (stable_id `s`) et un TDC `titre_identite` ;
  - un dossier source `en_construction` de ce `user`, avec deux fichiers sur `s` ;
  - une démarche cible avec un référentiel et une PJ ;
  - un dossier cible `brouillon` du même `user` ;
  - `API.dlnuf_config` stubé en Hash.

  Exemples, un par ligne du tableau ci-dessus, plus :
  - les deux fichiers sont rattachés, avec les **mêmes `blob_id`** que la source, et `prefilled` vaut vrai ;
  - un blob `virus_scan_result: 'infected'` est exclu ;
  - une référence vers le TDC `titre_identite` donne `:vide` ;
  - une cible préremplie est remplacée par une nouvelle référence ;
  - une cible remplie à la main reste intacte, même avec une référence valide ;
  - une référence vide sur une cible préremplie donne `:vide` : cible vidée, `prefilled` à faux ;
  - une source terminée (`accepte`) cachée par l'usager (`hidden_by_user_at` posé) donne `:source_introuvable` ;
  - une source dont le `user` a été supprimé donne `:autre_titulaire` sans exception et sans Sentry ;
  - une référence avec `row_id` lit le champ de la ligne du bloc répétable source.
- [ ] **Step 2 : spec du blob partagé.** Reprendre tel quel le fichier de vérification du 2026-11-06 : 3 exemples, survie à `purge_discarded`, survie à `purge_later`, suppression au dernier rattachement. La copie qui suit en reprend le contenu ; seul `require 'rails_helper'` change.

  ```ruby
  RSpec.describe 'Blob partagé entre deux dossiers' do
    include ActiveJob::TestHelper
    let(:procedure_a) { create(:procedure, :published, types_de_champ_public: [{ type: :piece_justificative }]) }
    let(:procedure_b) { create(:procedure, :published, types_de_champ_public: [{ type: :piece_justificative }]) }
    let(:dossier_a) { create(:dossier, :en_construction, :with_populated_champs, procedure: procedure_a) }
    let(:dossier_b) { create(:dossier, :brouillon, procedure: procedure_b) }
    let(:champ_a) { dossier_a.project_champs_public.first }
    let(:champ_b) { dossier_b.champ_for_update(procedure_b.active_revision.types_de_champ_public.first, updated_by: :api) }
    let(:blob) { champ_a.piece_justificative_file.blobs.first }

    before do
      ClonePiecesJustificativesService.clone_attachments(champ_a, champ_b)
      champ_b.save!
    end

    def blob_intact? = ActiveStorage::Blob.exists?(blob.id) && blob.service.exist?(blob.key)

    it 'survit à la suppression du dossier source (purge_discarded)' do
      dossier_a.update!(hidden_by_user_at: Time.zone.now, hidden_by_reason: :user_request)
      perform_enqueued_jobs { Dossier.find(dossier_a.id).purge_discarded }
      expect(blob_intact?).to be(true)
    end

    it 'survit au remplacement de la PJ source (purge_later)' do
      perform_enqueued_jobs { champ_a.piece_justificative_file.first.purge_later }
      expect(blob_intact?).to be(true)
    end

    it 'est supprimé quand le dernier rattachement disparaît' do
      perform_enqueued_jobs { dossier_a.destroy!; Dossier.find(dossier_b.id).destroy! }
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    end
  end
  ```
- [ ] **Step 3 :** `bundle exec rspec spec/lib/referentiel_de_polynesie/prefill_piece_justificative_spec.rb spec/models/champs/piece_justificative_blob_partage_spec.rb` → le service échoue (`NameError`). La spec du blob partagé passe déjà, ce qui est attendu : elle documente un comportement existant.
- [ ] **Step 4 : implémenter le service.** Un seul `Rails.logger.info` par appel, avec le symbole et les identifiants de dossiers. Aucune donnée personnelle dans les logs, pas même l'e-mail.
- [ ] **Step 5 :** relancer → vert.
- [ ] **Step 6 :** commit `feat(referentiel): service de préremplissage des pièces justificatives par référence MD`.

### Task 4 : branchement au préremplissage et drapeau `prefilled` du contrôleur PJ

**Files :**
- Modify : `app/models/champs/referentiel_champ.rb:235-239` (upstream, en place, `# pf:`)
- Modify : `app/controllers/champs/piece_justificative_controller.rb` (`attach_piece_justificative`, `# pf:`)
- Test : `spec/models/champs/referentiel_de_polynesie_champ_spec.rb`, `spec/controllers/champs/piece_justificative_controller_spec.rb`

**Interfaces :**
- Consumes : `PrefillPieceJustificative.new(referentiel_champ:, cible:, reference:).call` (Task 3).

- [ ] **Step 1 : specs en échec.**
  - Champ : un `referentiel_de_polynesie` dont le mapping est `'$.Statuts' => { 'type' => 'piece_justificative', 'prefill' => '1', 'prefill_stable_id' => <pj> }`. Après `propagate_prefill('Statuts' => 'md:12:34')`, le service a été appelé avec `reference: 'md:12:34'` et une cible du TDC `<pj>`, et `cast_value_for_type_de_champ` ne l'a pas été pour ce TDC. Faire `expect_any_instance_of(...)`, ou injecter un double par `allow(ReferentielDePolynesie::PrefillPieceJustificative).to receive(:new)`.
  - Champ : une cible texte du même mapping reste remplie par le chemin upstream (non-régression).
  - Champ : référentiel et PJ dans la **même** ligne de bloc répétable ⇒ le service est appelé avec le `row_id` de la ligne (chemin `update_sibling_prefillable_champs`).
  - Contrôleur PJ : un champ `prefilled: true` sur lequel l'usager ajoute un fichier (`update` avec `blob_signed_id`) se retrouve avec `prefilled == false`.
- [ ] **Step 2 :** `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb spec/controllers/champs/piece_justificative_controller_spec.rb` → échecs.
- [ ] **Step 3 : implémenter.**
  - `update_prefillable_champ` : le code exact est donné en spec §5.1, avec la condition `type_de_champ.type_champ == TypeDeChamp.type_champs.fetch(:piece_justificative)`.
  - `attach_piece_justificative` : `@champ.prefilled = false` avant le `save`, dans la transaction.
- [ ] **Step 4 :** relancer, puis lancer la liste ciblée `spec/models/champs/referentiel_champ_spec.rb spec/models/champs/referentiel_de_polynesie_champ_spec.rb spec/controllers/champs spec/lib/referentiel_de_polynesie spec/components/referentiels` → vert.
- [ ] **Step 5 :** commit `feat(referentiel): préremplir les pièces justificatives depuis un référentiel DLNUF`.

### Task 5 : scénarios système

**Files :**
- Create : `spec/system/users/referentiel_dlnuf_pj_spec.rb`

**Interfaces :**
- Consumes : tout ce qui précède.

Mise en place : on reprend `spec/system/users/referentiel_dlnuf_spec.rb`.
- **Stubs** : `dlnuf_config('24')` renvoie un Hash. `search_with_data` renvoie une ligne dont `row_data` contient `'Statuts' => "md:#{source.id}:#{pj_source_stable_id}"`. `API.colonnes_reference_pj('24')` renvoie `['Statuts']`.
- **Démarche cible** :
  - un `referentiel_de_polynesie` en mode autocomplete, lié à un `create(:baserow_referentiel, url: 'baserow://24')` (cf. `spec/models/champ_spec.rb:824` pour la liaison) ;
  - suivi d'une PJ `Statuts`, mappée `prefill_stable_id`.
- **Dossier source** : en construction, du même usager, avec un fichier `statuts.pdf`.

- [ ] **Step 1 : écrire les scénarios.**
  1. Sélection de la ligne ⇒ le champ « Statuts » affiche `statuts.pdf` et le message « Donnée remplie automatiquement. ». L'usager peut retirer le fichier.
  2. Ajout manuel d'un fichier `autre.pdf` dans « Statuts », puis nouvelle sélection de la ligne ⇒ `autre.pdf` est toujours là, et `statuts.pdf` n'a pas été ajouté.
- [ ] **Step 2 :** `NO_HEADLESS= bundle exec rspec spec/system/users/referentiel_dlnuf_pj_spec.rb` → vert. Relancer une fois en cas de timeout de navigation au premier scénario (assets à froid).
- [ ] **Step 3 :** commit `test(referentiel): scénarios système du préremplissage de PJ DLNUF`.

### Task 6 : documents et PR

- [ ] Spec §6 : remplacer la ligne « Bascule silencieuse DLNUF → catalogue | Mémorisation (PR 0, §3.3) : refus » par « Bascule silencieuse DLNUF → catalogue | Deux clés (marqueur OU table méta, contrat §3.4) ».
- [ ] `bundle exec rubocop` sur les fichiers touchés, `bundle exec haml-lint` si un gabarit a changé.
- [ ] Pousser `feature/dlnuf-prefill-pj` et ouvrir la PR avec `gh pr create --repo govpf/mes-demarches --base devpf`.
