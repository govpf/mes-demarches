# PR 0 « DLNUF par marqueur » — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** Mes-Démarches détecte le mode DLNUF d'un référentiel Baserow à partir du marqueur posé dans la description de la colonne primaire, avec repli transitoire sur la colonne méta « Champ propriétaire » et mémorisation fail-closed du mode une fois la démarche publiée.

**Architecture :** un objet pur `ReferentielDePolynesie::Marqueur` analyse le texte ; `BaserowAPI.dlnuf_config` l'applique à la colonne primaire puis retombe sur la méta ; la façade `API.dlnuf_config` (après son cache) applique la mémorisation stockée sur `Referentiels::BaserowReferentiel`. Les appelants (composant, contrôleur `#search`, champ) ne changent pas : ils reçoivent toujours `nil`, `:invalid` ou `{ field_id:, field_name:, field_type: }` (+ `source:`).

**Tech Stack :** Rails 7, RSpec, Typhoeus (stubé), gem maintenance_tasks.

**Spec :** `docs/superpowers/specs/2026-11-06-prefill-piece-justificative-reference-md-design.md` §3 ; contrat `docs/superpowers/specs/2026-11-06-contrat-referentiel-dlnuf.md` §3.

## Global Constraints

- Toute spécificité marquée `# pf:` ; textes d'interface avec l'apostrophe typographique `’`.
- Contrat §3.2 : préfixe de ligne `mes-demarches:` (casse ignorée) ; paires `cle=valeur` séparées par `;` ; clés et valeurs sans espaces autour ; casse des clés ignorée, valeurs comparées sans casse ; clés inconnues ignorées ; plus d'une ligne `mes-demarches:` ou ligne illisible ⇒ invalide.
- Clés : `referentiel` (`DLNUF` | `archive`, absente ⇒ `archive`) ; `proprietaire` (id numérique de colonne, obligatoire en DLNUF) ; `contrat` (défaut `1`, version inconnue ⇒ invalide).
- Fail-closed : jamais de repli en catalogue (`nil`) quand une incohérence est détectée ; `:invalid` à la place.
- Pas de migration : `dlnuf_vu_le` vit dans le jsonb existant `autocomplete_configuration` (`store_accessor`).
- Aucune écriture vers Baserow.
- Tests : specs ciblées en local, le reste via la CI de la PR.

## Review Focus

1. **Faute de frappe dans le préfixe** (`mes-demarches : referentiel=DLNUF`, espace avant les deux-points) : doit donner `:invalid`, pas « absent » (sinon la table serait lue comme catalogue). → Task 1, test « préfixe mal formé ».
2. **Baserow indisponible sur une table mémorisée DLNUF** : le moteur renvoie `nil` ⇒ la façade doit renvoyer `:invalid`, pas `nil`. → Task 3, test « moteur muet + mémorisé ».
3. **Même table, deux démarches** (l'une publiée, l'autre en test) : la mémorisation vaut pour la table (`domain_id`), donc la démarche en test est bloquée elle aussi si le marqueur disparaît. Comportement voulu. → Task 3, test « mémorisation par table ».
4. **Description `null`** renvoyée par Baserow pour la colonne primaire : analyse ⇒ absent, pas d'exception. → Task 1.
5. **`referentiel=archive` alors que la méta porte un « Champ propriétaire »** : contradiction ⇒ `:invalid`, pas catalogue. → Task 2.

Limite acceptée (non testée) : une table testée en DLNUF dont le marqueur est retiré **avant** la première résolution suivant la publication n'est jamais mémorisée. C'est le cas « phase de test libre » du contrat.

---

### Task 0 : mesure en production (exécutée par l'exploitant, hors PR)

Script en lecture seule (GET Baserow, SELECT dans la base MD), conservé ici pour ne pas dépendre d'un fichier temporaire. Il n'affiche aucune donnée de ligne.

```ruby
# mesure_dlnuf_prod.rb — LECTURE SEULE
api = ReferentielDePolynesie::BaserowAPI
table_ids = Referentiels::BaserowReferentiel.where("url LIKE 'baserow://%'").distinct.pluck(:url).map { _1.delete_prefix('baserow://') }

puts %w[id_meta table nom proprietaire_meta marqueur_primaire procedures_publiees].join(';')
table_ids.sort_by(&:to_i).each do |id|
  config = api.config(id)
  next puts("#{id};?;(ligne méta introuvable);;;") if config.nil?

  fields = Typhoeus.get(api.list_database_table_fields(config['Table']), headers: api.database_headers(config['Token']), timeout: api::TIMEOUT)
  primary = fields.success? ? JSON.parse(fields.body).find { _1['primary'] } : nil
  marqueur = if primary.nil? then '(colonnes illisibles)'
  elsif primary['description'].to_s.match?(/^\s*mes-demarches\s*:/i) then 'present'
  else 'absent'
  end

  # sous-requêtes : joins(revisions: ...) aliase types_de_champ et casse le where
  tdc_ids = TypeDeChamp.where(referentiel_id: Referentiels::BaserowReferentiel.where(url: "baserow://#{id}")).select(:id)
  revision_ids = ProcedureRevisionTypeDeChamp.where(type_de_champ_id: tdc_ids).select(:revision_id)
  publiees = Procedure.publiees_ou_closes.where(id: ProcedureRevision.where(id: revision_ids).select(:procedure_id)).count

  puts [id, config['Table'], config['Nom'], config['Champ propriétaire'].presence || '-', marqueur, publiees].join(';')
end
```

- [ ] Copier le script dans un pod web de production (`kubectl cp mesure_dlnuf_prod.rb ds-production/<pod>:/tmp/`), puis `kubectl exec -n ds-production <pod> -- bin/rails runner /tmp/mesure_dlnuf_prod.rb`. À défaut, le coller dans `bin/rails console`.
- [ ] Résultat attendu : une ligne CSV par référentiel avec `proprietaire_meta`, `marqueur_primaire` (absent partout aujourd'hui) et `procedures_publiees`. Les lignes où `proprietaire_meta` ≠ `-` sont les tables à marquer avant de retirer le repli (PR ultérieure).

### Task 1 : `ReferentielDePolynesie::Marqueur`

**Files :**
- Create : `app/lib/referentiel_de_polynesie/marqueur.rb`
- Test : `spec/lib/referentiel_de_polynesie/marqueur_spec.rb`

**Interfaces :**
- Produces : `ReferentielDePolynesie::Marqueur.parse(texte) -> nil | :invalid | Hash{String => String}` (clés en minuscules, valeurs sans espaces autour, casse conservée). `nil` = pas de ligne marqueur. Constante `CONTRATS_CONNUS = ['1']`. Réutilisé au lot C pour le marqueur de colonne.

- [ ] **Step 1 : écrire la spec en échec**

```ruby
describe ReferentielDePolynesie::Marqueur do
  def parse(t) = described_class.parse(t)

  it { expect(parse(nil)).to be_nil }
  it { expect(parse("Texte libre\nsans marqueur")).to be_nil }
  it 'lit la ligne machine après une ligne humaine' do
    expect(parse("Référentiel DLNUF : …\nmes-demarches: referentiel=DLNUF; proprietaire=12345"))
      .to eq('referentiel' => 'DLNUF', 'proprietaire' => '12345')
  end
  it 'ignore casse du préfixe et des clés, et les espaces' do
    expect(parse("  MES-DEMARCHES:  Referentiel = dlnuf ;PROPRIETAIRE=7 ")).to eq('referentiel' => 'dlnuf', 'proprietaire' => '7')
  end
  it 'conserve les clés inconnues sans erreur' do
    expect(parse('mes-demarches: referentiel=archive; futur=x')).to include('referentiel' => 'archive')
  end
  it 'accepte contrat=1' do
    expect(parse('mes-demarches: referentiel=archive; contrat=1')).to include('contrat' => '1')
  end
  it('refuse une version de contrat inconnue') { expect(parse('mes-demarches: contrat=2')).to eq(:invalid) }
  it('refuse deux lignes marqueur') { expect(parse("mes-demarches: referentiel=archive\nmes-demarches: referentiel=DLNUF")).to eq(:invalid) }
  it('refuse une paire sans =') { expect(parse('mes-demarches: referentiel DLNUF')).to eq(:invalid) }
  it('refuse une ligne vide après le préfixe') { expect(parse('mes-demarches:')).to eq(:invalid) }
  it('refuse un préfixe mal formé') { expect(parse('mes-demarches : referentiel=DLNUF')).to eq(:invalid) }
end
```

- [ ] **Step 2 :** `bundle exec rspec spec/lib/referentiel_de_polynesie/marqueur_spec.rb` → échec (`uninitialized constant`).
- [ ] **Step 3 : implémenter `parse`.** Une ligne est candidate si elle correspond à `/\A\s*mes-demarches\s*:/i` ; elle n'est **valide** que si elle correspond à `/\A\s*mes-demarches:/i` (sinon `:invalid`). Plus d'une candidate ⇒ `:invalid`. Segments vides (`;;`, `;` final) ignorés ; aucune paire ⇒ `:invalid` ; segment sans `=` ou clé vide ⇒ `:invalid`. `contrat` présent hors `CONTRATS_CONNUS` ⇒ `:invalid`.
- [ ] **Step 4 :** relancer la spec → verte.
- [ ] **Step 5 :** commit `feat(referentiel): analyse du marqueur mes-demarches (contrat DLNUF §3.2)`.

### Task 2 : `BaserowAPI.dlnuf_config` lit le marqueur

**Files :**
- Modify : `app/lib/referentiel_de_polynesie/baserow_api.rb` (`fields`, `dlnuf_config`)
- Test : `spec/lib/referentiel_de_polynesie/baserow_api_spec.rb` (bloc `.dlnuf_config` l. 211 et attentes `fields` l. 293-294)

**Interfaces :**
- Consumes : `Marqueur.parse`.
- Produces : `fields(config)` ajoute `description:` et `primary:` à chaque entrée. `dlnuf_config(domain_id) -> nil | :invalid | { field_id: Integer, field_name:, field_type:, source: :marqueur | :table_meta }`.

- [ ] **Step 1 : adapter et compléter la spec.** Ajouter une colonne primaire au stub, `{ 'id' => 1, 'name' => 'Dossier', 'type' => 'number', 'primary' => true, 'description' => description }`, avec `let(:description) { nil }`. Mettre à jour les deux `eq` existants : ajouter `source: :table_meta` aux hash l. 245/262, et `description: nil, primary: nil` aux attentes l. 293-294. **Supprimer** le test « ne lit pas le modèle de la table » (l. 235) : le marqueur impose de lire les colonnes. Nouveaux contextes :

| Contexte | `description` | `owner_field_id` (méta) | Attendu |
|---|---|---|---|
| marqueur DLNUF seul | `"mes-demarches: referentiel=DLNUF; proprietaire=9"` | nil | `{ field_id: 9, field_name: 'Email', field_type: 'email', source: :marqueur }` |
| marqueur + méta concordants | idem | 9 | idem (`source: :marqueur`) |
| marqueur + méta discordants | idem | 6 | `:invalid` |
| marqueur DLNUF sans propriétaire | `"mes-demarches: referentiel=DLNUF"` | nil | `:invalid` |
| propriétaire non numérique | `"…; proprietaire=abc"` | nil | `:invalid` |
| propriétaire inexistant | `"…; proprietaire=999"` | nil | `:invalid` |
| `referentiel=archive` | `"mes-demarches: referentiel=archive"` | nil | `nil` |
| archive + méta renseignée | idem | 9 | `:invalid` |
| type inconnu | `"mes-demarches: referentiel=autre"` | nil | `:invalid` |
| marqueur invalide | `"mes-demarches: contrat=2"` | 9 | `:invalid` |
| marqueur absent, méta seule | nil | 9 | comportement actuel, `source: :table_meta` |
| colonnes illisibles (fields en échec) et méta vide | — | nil | `nil` (inchangé) |

- [ ] **Step 2 :** `bundle exec rspec spec/lib/referentiel_de_polynesie/baserow_api_spec.rb` → les nouveaux contextes échouent.
- [ ] **Step 3 : implémenter.** `fields` conserve `field['description']` et `field['primary']`. `dlnuf_config` : `config` absente ⇒ `nil` ; `model = fields(config)` ; marqueur = `Marqueur.parse(model&.values&.find { _1[:primary] }&.dig(:description))` ; `:invalid` ⇒ `:invalid` ; `nil` ⇒ logique actuelle (méta), avec `source: :table_meta` ; sinon on applique le tableau ci-dessus (comparaison sans casse de `referentiel`, `proprietaire` qui doit correspondre à `/\A\d+\z/`). Pour chaque discordance, `Rails.logger.warn` avec `domain_id`. Garder l'avertissement `EMAIL_LIKE_TYPES` dans les deux voies. Commentaire `# pf:` en tête, qui renvoie au contrat §3.
- [ ] **Step 4 :** spec verte ; puis `bundle exec rspec spec/lib/referentiel_de_polynesie spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb spec/models/champs/referentiel_de_polynesie_champ_spec.rb` → vert. Les stubs `fields` qui n'ont pas de colonne primaire restent valides : marqueur absent, donc repli sur la méta.
- [ ] **Step 5 :** commit `feat(referentiel): détection DLNUF par marqueur de table avec repli sur la table méta`.

### Task 3 : mémorisation du mode (anti-bascule)

**Files :**
- Modify : `app/models/referentiels/baserow_referentiel.rb`
- Modify : `app/lib/referentiel_de_polynesie/api.rb` (`dlnuf_config`)
- Test : `spec/models/referentiels/baserow_referentiel_spec.rb` (existant, ajouter un bloc), `spec/lib/referentiel_de_polynesie/api_spec.rb`

**Interfaces :**
- Consumes : `BaserowAPI.dlnuf_config` (Task 2).
- Produces :
  - `store_accessor :autocomplete_configuration, :dlnuf_vu_le` (chaîne ISO 8601) ;
  - `Referentiels::BaserowReferentiel.pour_table(domain_id) -> Relation` (`where(url: "baserow://#{domain_id.to_i}")`) ;
  - `Referentiels::BaserowReferentiel.dlnuf_vu?(domain_id) -> Boolean` (au moins un référentiel de la table porte `dlnuf_vu_le`) ;
  - `Referentiels::BaserowReferentiel.memoriser_dlnuf!(domain_id) -> void` : pose `dlnuf_vu_le = Time.zone.now.iso8601` sur les référentiels de la table qui ne l'ont pas **et** sont utilisés par une procédure `publiees_ou_closes`. Jointure par sous-requêtes TypeDeChamp → ProcedureRevisionTypeDeChamp → ProcedureRevision, car `joins(revisions: ...)` crée un alias sur `types_de_champ`. Écriture par `update_column` (pas de callbacks, pas de `updated_at`), et `Rails.logger.info` à chaque pose.

- [ ] **Step 1 : spec modèle en échec.**

```ruby
describe Referentiels::BaserowReferentiel do
  let(:referentiel) { create(:baserow_referentiel, table_id: 24) }
  let!(:procedure) { create(:procedure, types_de_champ_public: [{ type: :referentiel_de_polynesie, referentiel: }]) }

  describe '.memoriser_dlnuf!' do
    it 'ne mémorise rien tant que la démarche est en brouillon' do
      described_class.memoriser_dlnuf!(24)
      expect(described_class.dlnuf_vu?(24)).to be(false)
    end

    it 'mémorise dès que la démarche est publiée, sans écraser la date' do
      procedure.publish!
      described_class.memoriser_dlnuf!(24)
      date = referentiel.reload.dlnuf_vu_le
      expect(date).to be_present
      travel(1.day) { described_class.memoriser_dlnuf!(24) }
      expect(referentiel.reload.dlnuf_vu_le).to eq(date)
    end
  end
end
```

  (Vérifier la factory et la manière de lier `referentiel` au type de champ dans `spec/factories`. Adapter la création, pas les assertions.)

- [ ] **Step 2 : spec façade en échec** (`api_spec.rb`, bloc `.dlnuf_config`) :
  - `Hash` renvoyé ⇒ `memoriser_dlnuf!('24')` appelé, résultat inchangé ;
  - `nil` et `dlnuf_vu?` faux ⇒ `nil` ;
  - `nil` et `dlnuf_vu?` vrai ⇒ `:invalid` et `Sentry.capture_message('ReferentielDePolynesie: bascule de mode DLNUF', extra: { domain_id: '24' })` (couvre aussi le cas du moteur muet, Review Focus 2) ;
  - `:invalid` ⇒ `:invalid`, sans appel à `memoriser_dlnuf!` ;
  - mémorisation par table : deux référentiels sur `baserow://24`, un seul mémorisé, ⇒ `dlnuf_vu?(24)` vrai (Review Focus 3) ;
  - le test existant avec `caching: true` reste vert : la mémorisation s'applique **après** le cache.
- [ ] **Step 3 :** lancer les deux specs → échec.
- [ ] **Step 4 : implémenter.** Dans `API.dlnuf_config`, après la lecture du cache, `appliquer_memorisation(domain_id, resultat)` (méthode privée de classe, `# pf:` qui renvoie au contrat §3.4). Le chemin « moteur absent / domain_id ≤ 0 » reste `nil` sans mémorisation.
- [ ] **Step 5 :** specs vertes, puis relancer la liste ciblée de la Task 2, Step 4, et `spec/system/users/referentiel_dlnuf_spec.rb` en headless (`NO_HEADLESS=`).
- [ ] **Step 6 :** commit `feat(referentiel): mémoriser le mode DLNUF des démarches publiées (fail-closed)`.

### Task 4 : tâche de maintenance de remise à zéro

**Files :**
- Create : `app/tasks/maintenance/t20261106reinitialiser_memorisation_dlnuf_task.rb`
- Test : `spec/tasks/maintenance/t20261106reinitialiser_memorisation_dlnuf_task_spec.rb`

**Interfaces :**
- Consumes : `BaserowReferentiel.pour_table`, `dlnuf_vu_le`.
- Produces : `Maintenance::T20261106reinitialiserMemorisationDlnufTask` avec `attribute :table_id, :integer` (`validates :table_id, presence: true, numericality: { greater_than: 0 }`) ; `collection` = `pour_table(table_id)` ; `process(referentiel)` journalise (`Rails.logger.warn`, id du référentiel, `table_id`, ancienne date) puis `update_column` en retirant la clé. Pas de `run_on_first_deploy` : lancement manuel uniquement.

- [ ] **Step 1 :** spec en échec : après `process`, `dlnuf_vu?(table_id)` est faux ; un référentiel d'une autre table reste mémorisé ; `table_id` absent rend la tâche invalide.
- [ ] **Step 2 :** `bundle exec rspec spec/tasks/maintenance/t20261106reinitialiser_memorisation_dlnuf_task_spec.rb` → échec.
- [ ] **Step 3 :** implémenter (suivre la forme de `app/tasks/maintenance/create_variants_for_pjs_from_messagerie__task.rb`).
- [ ] **Step 4 :** spec verte. Vider ensuite le cache de `dlnuf_config` pour la table ? Non : le cache ne contient que la réponse Baserow, et la mémorisation est relue à chaque appel.
- [ ] **Step 5 :** commit `feat(referentiel): tâche de remise à zéro de la mémorisation DLNUF`.

### Task 5 : PR

- [ ] `bundle exec rubocop` sur les fichiers touchés ; pousser la branche `feature/dlnuf-par-marqueur` (créée depuis `docs/dlnuf-lot-c`, donc avec le contrat, la spec et ce plan) ; ouvrir la PR avec `--repo govpf/mes-demarches` vers `devpf`. La description résume le contrat §3 et rappelle que le repli méta sera retiré après le marquage des tables relevées en Task 0.
