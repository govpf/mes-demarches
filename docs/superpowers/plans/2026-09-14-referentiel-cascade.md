# Référentiel de Polynésie — Cascade et filtres contextuels (lot A) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un champ `referentiel_de_polynesie` peut être restreint aux lignes Baserow dont une colonne égale la valeur d'un autre champ du dossier (le « pilote »), configuré par l'administrateur derrière une case à cocher, filtré côté serveur, validé au dépôt, et signalé dans l'éditeur si le pilote disparaît.

**Architecture:** La configuration vit dans `options['referentiel_filter']` du type de champ (`baserow_field_id`, `baserow_field_name`, `pilot_column_id` = `Column#column_id`). Un service `ReferentielDePolynesie::ContextualFilter` centralise la résolution du pilote (via `Column#value` sur le dossier ou sur le champ projeté dans la bonne ligne de bloc), la construction du filtre Baserow (opérateur selon le type de colonne, résolution des options de sélection en id) et la comparaison locale au dépôt. Le endpoint `#search` reçoit `stable_id` + `row_id` en plus du `dossier_id` existant et cumule les filtres (`scopes:`) avec le mode « Dites-le-nous une fois ». Le composant re-rend le référentiel quand son pilote change via `TurboChampsConcern`. Un validateur de procédure bloque la publication si le pilote n'est plus admissible.

**Tech Stack:** Rails 7.0 / Ruby 3.3, Typhoeus (Baserow REST), Pundit, React (react-aria `RemoteComboBox`), Stimulus (`hide-target`), RSpec (+ Capybara/Playwright headless).

**Spec:** `docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md` (révisée le 2026-09-14). Devis : `docs/superpowers/specs/2026-07-21-devis-referentiel-dlnuf-cascade-prefill.md` §2.5 et §3 (lot A).

## Global Constraints

- **Sécurité (spec §3)** : la valeur du pilote n'est **jamais** lue depuis le client ; pilote vide, config invalide ou option Baserow introuvable → liste vide, **jamais la table entière** ; deux remparts (filtre serveur à la sélection + validation locale au dépôt).
- **Jamais masquer** le champ filtré (spec « Décisions de cadrage ») : pas de `hideWhenEmpty` pour la cascade.
- **Emplacement du pilote** : racine avant le référentiel (ou avant son bloc), ou frère précédent de la **même ligne** ; jamais un autre bloc.
- **Types de pilote v1** : `Column#type ∈ {:text, :enum}` (les colonnes `:enums` multi-valuées sont hors v1 : la sémantique OU n'est pas définie).
- **Colonnes Baserow filtrables v1** : `text`, `long_text`, `email`, `formula`, `single_select`, `multiple_select`. Jamais `contains` (« Plants » attraperait « Plants aromatiques ») : `equal` pour le texte, `single_select_equal` / `multiple_select_has` sur l'**id d'option**.
- **Pas de réinitialisation destructive** au changement de pilote ; validation locale au dépôt sans appel Baserow ; colonne absente de `row_data` → on n'invalide pas (antériorité).
- **Suppression / déplacement / changement de type du pilote** : autorisés, signalés par `TypesDeChamp::ReferentielFilterValidator` (contextes `types_de_champ_public_editor`, `types_de_champ_private_editor`, `publication`), comme `ConditionValidator`.
- Tous les textes UI français utilisent l'apostrophe typographique `'` (U+2019) et les guillemets « », y compris dans les expectations de tests.
- Toute spécificité PF est marquée `# pf:` (Ruby / HAML `-# pf:`) ou `// pf:` (TS/TSX).
- Branche de travail : `feature/referentiel-cascade` (worktree `.claude/worktrees/feature-referentiel-cascade`, créée depuis `origin/devpf`). Convention CI : `feature/*` → PR vers `devpf`.
- Commits : message en français, terminé par `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Commandes : `bundle exec rspec <fichier>` ; lint : `bundle exec rubocop -a <fichiers>` ; specs système : `NO_HEADLESS= bundle exec rspec <fichier>` (toujours headless).
- Vérifier avant chaque tâche que la base de test répond : `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb -e 'focusable_input_id'` doit être vert.

---

### Task 1 : Option `referentiel_filter` sur le type de champ

**Files:**
- Modify: `app/models/type_de_champ.rb:146` (`INSTANCE_OPTIONS_BY_TYPE`) et ajout de méthodes après `drop_down_other?` (~ligne 388)
- Test: `spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb`

**Interfaces:**
- Produces: `TypeDeChamp#referentiel_filter` (Hash à clés string ou nil, via `store_accessor`), `TypeDeChamp#referentiel_filter?` (Boolean), `TypeDeChamp#referentiel_filter_form=(Hash{enabled:, baserow_field_id:, pilot_column_id:})` (écriture depuis l'éditeur, résout `baserow_field_name` via `ReferentielDePolynesie::API.table_fields` — défini Task 2 ; en Task 1 on stubbe).
- Consumes: rien.

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter à la fin du `describe TypesDeChamp::ReferentielDePolynesieTypeDeChamp do` de `spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb` :

```ruby
  describe 'referentiel_filter (cascade)' do
    let(:type_de_champ) { build(:type_de_champ_referentiel_de_polynesie, table_id: '24', no_coordinate: true) }
    let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 1, value: 'Semences' }] } } }

    before { allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields) }

    it 'est absent par défaut' do
      expect(type_de_champ.referentiel_filter).to be_nil
      expect(type_de_champ.referentiel_filter?).to be(false)
    end

    it 'est conservé par clean_options pour ce type' do
      type_de_champ.referentiel_filter = { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7' }
      expect(type_de_champ.clean_options.keys).to include('referentiel_filter')
      expect(type_de_champ.referentiel_filter?).to be(true)
    end

    describe '#referentiel_filter_form=' do
      it 'enregistre la config et résout le nom de la colonne Baserow' do
        type_de_champ.referentiel_filter_form = { 'enabled' => '1', 'baserow_field_id' => '12', 'pilot_column_id' => 'type_de_champ/7' }
        expect(type_de_champ.referentiel_filter).to eq(
          'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7'
        )
      end

      it 'efface la config quand la case est décochée' do
        type_de_champ.referentiel_filter = { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7' }
        type_de_champ.referentiel_filter_form = { 'baserow_field_id' => '12', 'pilot_column_id' => 'type_de_champ/7' }
        expect(type_de_champ.referentiel_filter).to be_nil
      end

      it 'n\'enregistre rien si une des deux listes est vide' do
        type_de_champ.referentiel_filter_form = { 'enabled' => '1', 'baserow_field_id' => '', 'pilot_column_id' => 'type_de_champ/7' }
        expect(type_de_champ.referentiel_filter).to be_nil
      end

      it 'garde le nom en cache si Baserow est injoignable' do
        allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(nil)
        type_de_champ.referentiel_filter = { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7' }
        type_de_champ.referentiel_filter_form = { 'enabled' => '1', 'baserow_field_id' => '12', 'pilot_column_id' => 'type_de_champ/9' }
        expect(type_de_champ.referentiel_filter).to eq(
          'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/9'
        )
      end
    end
  end
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `bundle exec rspec spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb -e 'referentiel_filter'`
Expected: FAIL — `NoMethodError: undefined method 'referentiel_filter'`.

- [ ] **Step 3 : Implémenter**

Dans `app/models/type_de_champ.rb`, ligne 146, remplacer :

```ruby
    referentiel_de_polynesie: [:table_id, :drop_down_other, :referentiel_mapping],
```

par :

```ruby
    referentiel_de_polynesie: [:table_id, :drop_down_other, :referentiel_mapping, :referentiel_filter],
```

Puis, juste après la méthode `drop_down_other?` (vers la ligne 388), ajouter :

```ruby
  # pf: cascade référentiel — config { 'baserow_field_id', 'baserow_field_name', 'pilot_column_id' }
  # (cf. docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md §1)
  def referentiel_filter?
    referentiel_de_polynesie? && referentiel_filter.present?
  end

  # pf: écriture depuis l'éditeur (case « Restreindre… » + deux listes). Case décochée ou liste
  # vide → config effacée. Le nom de la colonne Baserow est résolu côté serveur et mis en cache
  # pour la validation locale au dépôt ; si Baserow est injoignable on garde le nom précédent.
  def referentiel_filter_form=(form)
    form = Hash(form).with_indifferent_access
    if form[:enabled] == '1' && form[:baserow_field_id].present? && form[:pilot_column_id].present?
      field_id = form[:baserow_field_id].to_i
      field = ReferentielDePolynesie::API.table_fields(table_id)&.dig(field_id)
      self.referentiel_filter = {
        'baserow_field_id' => field_id,
        'baserow_field_name' => field&.dig(:name) || Hash(referentiel_filter)['baserow_field_name'],
        'pilot_column_id' => form[:pilot_column_id].to_s,
      }
    else
      self.referentiel_filter = nil
    end
  end
```

- [ ] **Step 4 : Vérifier le succès**

Run: `bundle exec rspec spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb`
Expected: PASS (les 5 nouveaux exemples verts ; `table_fields` est stubbé, il n'existe pas encore).

- [ ] **Step 5 : Lint + commit**

```bash
bundle exec rubocop -a app/models/type_de_champ.rb spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb
git add app/models/type_de_champ.rb spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb
git commit -m "feat(referentiel): option referentiel_filter sur le type de champ

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2 : `BaserowAPI` — filtres multiples (`scopes:`), options de sélection, `table_fields`

**Files:**
- Modify: `app/lib/referentiel_de_polynesie/baserow_api.rb:56-84` (`search_with_data`), `:133-139` (`fields`), `:203-215` (`build_search_filters`)
- Modify: `app/lib/referentiel_de_polynesie/api.rb` (`search_with_data`, nouveau `table_fields`)
- Modify: `app/controllers/data_sources/referentiel_de_polynesie_controller.rb:27` (appel DLNUF → `scopes:`)
- Modify: `spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`, `spec/lib/referentiel_de_polynesie/api_spec.rb`, `spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`, `spec/system/users/referentiel_dlnuf_spec.rb` (renommage `scope:` → `scopes:`)

**Interfaces:**
- Produces:
  - `ReferentielDePolynesie::BaserowAPI.search_with_data(domain_id, term, drop_down_other: false, scopes: [])` — `scopes` : Array de `{ field_id: Integer, type: String, value: }` ; `type` ∈ `'equal' | 'single_select_equal' | 'multiple_select_has'`.
  - `ReferentielDePolynesie::BaserowAPI.fields(config)` → `{ Integer => { name: String, type: String, select_options: [{ id: Integer, value: String }] } }` (`select_options` = `[]` pour les colonnes sans options).
  - `ReferentielDePolynesie::BaserowAPI.table_fields(domain_id)` → même Hash, ou `nil` si config absente / erreur réseau.
  - `ReferentielDePolynesie::API.search_with_data(domain_id, term, drop_down_other: false, scopes: [])`.
  - `ReferentielDePolynesie::API.table_fields(domain_id)` → même Hash, mis en cache 5 min (sentinel `:none`), `nil` si `domain_id` invalide ou moteur absent.
- Consumes: rien de nouveau.

- [ ] **Step 1 : Écrire les tests qui échouent (BaserowAPI)**

Dans `spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`, repérer le `let(:fields_response)` (ligne ~20) et ajouter à la fin du fichier, à l'intérieur du `describe` principal :

```ruby
  describe '.fields' do
    let(:fields_response) do
      [
        { 'id' => 1, 'name' => 'Nom', 'type' => 'text' },
        { 'id' => 12, 'name' => 'Catégorie', 'type' => 'single_select', 'select_options' => [{ 'id' => 100, 'value' => 'Semences', 'color' => 'blue' }, { 'id' => 101, 'value' => 'Plants', 'color' => 'green' }] },
      ]
    end

    before do
      stub_fields = instance_double(Typhoeus::Response, success?: true, body: fields_response.to_json)
      allow(Typhoeus).to receive(:get).with("#{base_url}/api/database/fields/table/#{table_id}/", anything).and_return(stub_fields)
    end

    it 'expose les options des colonnes de sélection (id + libellé), [] sinon' do
      fields = described_class.fields({ 'Table' => table_id, 'Token' => 'tok' })
      expect(fields[1]).to eq(name: 'Nom', type: 'text', select_options: [])
      expect(fields[12]).to eq(name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }, { id: 101, value: 'Plants' }])
    end
  end

  describe '.build_search_filters avec plusieurs scopes' do
    it 'cumule les filtres en AND avec les mots recherchés' do
      params = described_class.send(:build_search_filters, 3, 'Papeete', scopes: [
        { field_id: 9, type: 'equal', value: 'a@b.pf' },
        { field_id: 12, type: 'single_select_equal', value: 100 },
      ])
      filters = JSON.parse(params['filters'])
      expect(filters['filter_type']).to eq('AND')
      expect(filters['filters']).to eq([
        { 'field' => 3, 'type' => 'contains', 'value' => 'Papeete' },
        { 'field' => 9, 'type' => 'equal', 'value' => 'a@b.pf' },
        { 'field' => 12, 'type' => 'single_select_equal', 'value' => 100 },
      ])
    end

    it 'sans terme ni scope, ne construit aucun filtre (table entière interdite en amont)' do
      expect(described_class.send(:build_search_filters, 3, '', scopes: [])).to eq({})
    end
  end
```

Puis, dans ce même fichier, remplacer **toutes** les occurrences de `scope: { field_id: 9, value:` par `scopes: [{ field_id: 9, type: 'equal', value:` et fermer le crochet correspondant (`}` → `}]`) ; vérifier avec `grep -n "scope" spec/lib/referentiel_de_polynesie/baserow_api_spec.rb` qu'il ne reste plus de `scope:` au singulier.

- [ ] **Step 2 : Vérifier l'échec**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`
Expected: FAIL — `ArgumentError: unknown keyword: :scopes` et écart sur `select_options`.

- [ ] **Step 3 : Implémenter dans `BaserowAPI`**

Dans `app/lib/referentiel_de_polynesie/baserow_api.rb` :

Remplacer la signature et l'appel dans `search_with_data` :

```ruby
    def search_with_data(domain_id, term, drop_down_other: false, scopes: [])
      config = config(domain_id)
      return [] unless config

      search_field_id = config['Champ de recherche']
      model = fields(config)

      params = build_search_filters(search_field_id, term, scopes:)
```

(le reste de la méthode est inchangé).

Remplacer `fields` :

```ruby
    # pf: retourne { id => { name:, type:, select_options: [{ id:, value: }] } } ; select_options
    # est vide pour les colonnes sans options. Sert au mapping ET à la cascade (résolution des
    # options en id pour single_select_equal / multiple_select_has).
    def fields(config)
      response = Typhoeus.get(list_database_table_fields(config['Table']), headers: database_headers(config['Token']), timeout: TIMEOUT)
      if response.success?
        JSON.parse(response.body).to_h do |field|
          options = Array(field['select_options']).map { { id: _1['id'], value: _1['value'] } }
          [field['id'], { name: field['name'], type: field['type'], select_options: options }]
        end
      end
    end

    # pf: colonnes d'une table désignée par son id de référentiel (table méta) ; nil si inconnue
    def table_fields(domain_id)
      config = config(domain_id)
      return nil unless config

      fields(config)
    end
```

Remplacer `build_search_filters` :

```ruby
    def build_search_filters(search_field, term, scopes: [])
      filters = extract_search_words(term).map do |word|
        { "field" => search_field.to_i, "type" => "contains", "value" => word }
      end
      # pf: DLNUF et cascade — les filtres de périmètre sont TOUJOURS appliqués quand présents ;
      # q ne fait que réduire à l'intérieur du périmètre (la sécurité tient quel que soit q)
      Array(scopes).each do |scope|
        filters << { "field" => scope[:field_id].to_i, "type" => scope[:type].presence || "equal", "value" => scope[:value] }
      end
      return {} if filters.empty?

      { "filters" => JSON.generate({ "filter_type" => "AND", "filters" => filters }) }
    end
```

Vérifier que `dlnuf_config` (ligne ~123 : `field = fields(config)&.dig(owner_field_id.to_i)`) fonctionne toujours : il lit `field[:type]` et `field[:name]`, inchangés.

- [ ] **Step 4 : Implémenter dans `API` (wrapper cache)**

Dans `app/lib/referentiel_de_polynesie/api.rb`, remplacer `search_with_data` et ajouter `table_fields` :

```ruby
    def search_with_data(domain_id, term, drop_down_other: false, scopes: [])
      return [] if domain_id.to_i <= 0
      engine&.search_with_data(domain_id, term, drop_down_other:, scopes:) || []
    end

    # pf: cascade — colonnes de la table (nom, type, options de sélection) avec le même cache
    # court que dlnuf_config : sert à l'éditeur admin, au endpoint #search et au composant.
    def table_fields(domain_id)
      return nil if domain_id.to_i <= 0 || engine.nil?

      cached = Rails.cache.fetch("referentiel_de_polynesie/table_fields/#{domain_id}", expires_in: DLNUF_CONFIG_TTL) do
        engine.table_fields(domain_id) || :none
      end
      cached == :none ? nil : cached
    end
```

- [ ] **Step 5 : Adapter le contrôleur et les specs existantes**

Dans `app/controllers/data_sources/referentiel_de_polynesie_controller.rb`, ligne ~27, remplacer :

```ruby
          table, @params[:q], drop_down_other:, scope: { field_id: dlnuf[:field_id], value: email }
```

par :

```ruby
          table, @params[:q], drop_down_other:, scopes: [{ field_id: dlnuf[:field_id], type: 'equal', value: email }]
```

Dans `spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`, remplacer chaque `scope: { field_id: 9, value: <expr> }` par `scopes: [{ field_id: 9, type: 'equal', value: <expr> }]` (commande : `grep -n "scope:" spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb` puis édition ligne à ligne).

Dans `spec/system/users/referentiel_dlnuf_spec.rb`, remplacer :

```ruby
  let(:scope) { { field_id: 9, value: user.email.downcase } }
```

par :

```ruby
  let(:scopes) { [{ field_id: 9, type: 'equal', value: user.email.downcase }] }
```

et chaque `.with('24', anything, drop_down_other: anything, scope:)` par `.with('24', anything, drop_down_other: anything, scopes:)`.

Dans `spec/lib/referentiel_de_polynesie/api_spec.rb`, ajouter :

```ruby
  describe '.table_fields' do
    let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [] } } }

    before do
      allow(described_class).to receive(:engine).and_return(ReferentielDePolynesie::BaserowAPI)
      Rails.cache.clear
    end

    it 'délègue au moteur et met en cache' do
      expect(ReferentielDePolynesie::BaserowAPI).to receive(:table_fields).with('24').once.and_return(fields)
      2.times { expect(described_class.table_fields('24')).to eq(fields) }
    end

    it 'retourne nil (mis en cache) quand la table est inconnue' do
      expect(ReferentielDePolynesie::BaserowAPI).to receive(:table_fields).with('99').once.and_return(nil)
      2.times { expect(described_class.table_fields('99')).to be_nil }
    end

    it 'retourne nil pour un id invalide sans appeler le moteur' do
      expect(ReferentielDePolynesie::BaserowAPI).not_to receive(:table_fields)
      expect(described_class.table_fields('0')).to be_nil
    end
  end
```

(Si `api_spec.rb` utilise déjà un `before` global qui stubbe `engine`, réutiliser le sien et ne pas dupliquer.)

- [ ] **Step 6 : Vérifier le succès**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/ spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`
Expected: PASS. Puis `grep -rn "scope:" app/ spec/ --include=*.rb | grep -i "referentiel\|dlnuf"` ne doit plus rien renvoyer au singulier lié au référentiel.

- [ ] **Step 7 : Lint + commit**

```bash
bundle exec rubocop -a app/lib/referentiel_de_polynesie/ app/controllers/data_sources/referentiel_de_polynesie_controller.rb spec/lib/referentiel_de_polynesie/ spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb spec/system/users/referentiel_dlnuf_spec.rb
git add -A app/lib/referentiel_de_polynesie/ app/controllers/data_sources/referentiel_de_polynesie_controller.rb spec/lib/referentiel_de_polynesie/ spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb spec/system/users/referentiel_dlnuf_spec.rb
git commit -m "refactor(referentiel): filtres Baserow multiples (scopes) et options de sélection

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3 : Service `ReferentielDePolynesie::ContextualFilter`

**Files:**
- Create: `app/lib/referentiel_de_polynesie/contextual_filter.rb`
- Test: `spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb`

**Interfaces:**
- Produces: `ReferentielDePolynesie::ContextualFilter.for(type_de_champ:, dossier:, row_id: nil)` → instance avec :
  - `configured?` → Boolean (config présente)
  - `invalid?` → Boolean (config présente mais colonne pilote introuvable, TDC pilote absent de la révision du dossier, ou pilote dans un autre bloc)
  - `pilot_column` → `Column` ou nil ; `pilot_tdc` → `TypeDeChamp` ou nil ; `pilot_libelle` → String
  - `pilot_value` → String ou nil (première valeur non vide, normalisée `to_s.strip`)
  - `baserow_field_id` → Integer ; `baserow_field_name` → String
  - `baserow_scope(fields)` → `{ field_id:, type:, value: }` ou nil (pilote vide, colonne absente des `fields`, option introuvable, type non filtrable)
  - `matches_row_data?(row_data)` → Boolean (true si `row_data` nil ou sans la clé `baserow_field_name`)
  - `empty_label` → String (I18n `shared.champs.referentiel_de_polynesie.filter_pilot_blank` / `filter_no_match`)
  - Constantes : `TEXT_TYPES`, `SELECT_TYPES`, `FILTERABLE_BASEROW_TYPES`, `PILOT_COLUMN_TYPES = [:text, :enum]`.
- Consumes: `TypeDeChamp#referentiel_filter` (Task 1) ; `Column#value`, `Procedure#find_column`, `Dossier#project_champ`, `ProcedureRevision#parent_of`.

- [ ] **Step 1 : Ajouter les clés I18n**

Dans `config/locales/shared.fr.yml`, sous `referentiel_de_polynesie:` (ligne ~56, à côté de `dlnuf_empty`), ajouter :

```yaml
        filter_pilot_blank: "Renseignez d'abord « %{pilot} »"
        filter_no_match: "Aucun résultat pour « %{value} »"
```

Dans `config/locales/shared.en.yml`, même emplacement :

```yaml
        filter_pilot_blank: "Fill in “%{pilot}” first"
        filter_no_match: "No result for “%{value}”"
```

- [ ] **Step 2 : Écrire les tests qui échouent**

Créer `spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb` :

```ruby
# frozen_string_literal: true

describe ReferentielDePolynesie::ContextualFilter do
  let(:referentiel) { create(:baserow_referentiel) } # url baserow://24, autocomplete
  let(:filter_config) { { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => pilot_column_id } }
  let(:fields) do
    {
      1 => { name: 'Nom', type: 'text', select_options: [] },
      12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }, { id: 101, value: 'Plants' }] },
      13 => { name: 'Familles', type: 'multiple_select', select_options: [{ id: 200, value: 'Semences' }] },
      14 => { name: 'Code', type: 'text', select_options: [] },
    }
  end

  context 'pilote à la racine (liste déroulante avant le référentiel)' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, referentiel_filter: filter_config },
      ])
    end
    let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
    let(:pilot_column_id) { "type_de_champ/#{pilot_tdc_stable_id}" }
    let(:pilot_tdc_stable_id) { create(:procedure).id * 0 + 999_999 } # remplacé ci-dessous par le vrai stable_id
    let(:dossier) { create(:dossier, procedure:) }
    let(:filter) { described_class.for(type_de_champ: rdp_tdc, dossier:) }

    # Le stable_id n'est connu qu'après création : on réécrit la config du TDC.
    before do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}"))
    end

    it 'est configuré, valide, et connaît le pilote' do
      expect(filter.configured?).to be(true)
      expect(filter.invalid?).to be(false)
      expect(filter.pilot_tdc).to eq(pilot_tdc)
      expect(filter.pilot_libelle).to eq('Type de produit')
      expect(filter.baserow_field_id).to eq(12)
      expect(filter.baserow_field_name).to eq('Catégorie')
    end

    it 'résout la valeur du pilote depuis le dossier persisté' do
      dossier.project_champ(pilot_tdc).update!(value: 'Semences')
      expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).pilot_value).to eq('Semences')
    end

    it 'a une valeur nil quand le pilote est vide' do
      expect(filter.pilot_value).to be_nil
    end

    describe '#baserow_scope' do
      before { dossier.project_champ(pilot_tdc).update!(value: 'Semences') }
      let(:filter) { described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload) }

      it 'single_select → single_select_equal sur l\'id de l\'option (insensible à la casse)' do
        expect(filter.baserow_scope(fields)).to eq(field_id: 12, type: 'single_select_equal', value: 100)
      end

      it 'multiple_select → multiple_select_has sur l\'id de l\'option' do
        rdp_tdc.update!(referentiel_filter: rdp_tdc.referentiel_filter.merge('baserow_field_id' => 13, 'baserow_field_name' => 'Familles'))
        expect(described_class.for(type_de_champ: rdp_tdc.reload, dossier:).baserow_scope(fields)).to eq(field_id: 13, type: 'multiple_select_has', value: 200)
      end

      it 'texte → equal sur la valeur' do
        rdp_tdc.update!(referentiel_filter: rdp_tdc.referentiel_filter.merge('baserow_field_id' => 14, 'baserow_field_name' => 'Code'))
        expect(described_class.for(type_de_champ: rdp_tdc.reload, dossier:).baserow_scope(fields)).to eq(field_id: 14, type: 'equal', value: 'Semences')
      end

      it 'option introuvable → nil (fail-closed)' do
        dossier.project_champ(pilot_tdc).update!(value: 'Fleurs')
        expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).baserow_scope(fields)).to be_nil
      end

      it 'colonne absente des fields → nil' do
        expect(filter.baserow_scope({})).to be_nil
      end

      it 'pilote vide → nil' do
        dossier.project_champ(pilot_tdc).update!(value: nil)
        expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).baserow_scope(fields)).to be_nil
      end
    end

    describe '#matches_row_data?' do
      before { dossier.project_champ(pilot_tdc).update!(value: 'Semences') }
      let(:filter) { described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload) }

      it { expect(filter.matches_row_data?({ 'Catégorie' => 'Semences' })).to be(true) }
      it { expect(filter.matches_row_data?({ 'Catégorie' => 'semences' })).to be(true) }
      it { expect(filter.matches_row_data?({ 'Catégorie' => 'Plants' })).to be(false) }
      it('multiple_select simplifié « A, B »') { expect(filter.matches_row_data?({ 'Catégorie' => 'Plants, Semences' })).to be(true) }
      it('colonne absente → antériorité tolérée') { expect(filter.matches_row_data?({ 'Nom' => 'x' })).to be(true) }
      it('row_data nil → toléré') { expect(filter.matches_row_data?(nil)).to be(true) }
    end

    describe '#empty_label' do
      it 'demande de renseigner le pilote quand il est vide' do
        expect(filter.empty_label).to eq("Renseignez d'abord « Type de produit »")
      end

      it 'annonce l\'absence de résultat pour la valeur du pilote' do
        dossier.project_champ(pilot_tdc).update!(value: 'Plants')
        expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).empty_label).to eq('Aucun résultat pour « Plants »')
      end
    end

    it 'est invalide si le pilote a disparu de la révision' do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => 'type_de_champ/424242'))
      expect(described_class.for(type_de_champ: rdp_tdc.reload, dossier:).invalid?).to be(true)
    end

    it 'n\'est pas configuré sans referentiel_filter' do
      rdp_tdc.update!(referentiel_filter: nil)
      f = described_class.for(type_de_champ: rdp_tdc.reload, dossier:)
      expect(f.configured?).to be(false)
      expect(f.invalid?).to be(false)
    end
  end

  context 'pilote dans la même ligne d\'un bloc répétable' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        {
          type: :repetition, libelle: 'Produits', children: [
            { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
            { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, referentiel_filter: filter_config },
          ],
        },
      ])
    end
    let(:repetition_tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:pilot_tdc) { procedure.draft_revision.children_of(repetition_tdc).first }
    let(:rdp_tdc) { procedure.draft_revision.children_of(repetition_tdc).second }
    let(:pilot_column_id) { 'type_de_champ/0' }
    let(:dossier) { create(:dossier, procedure:) }

    before do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}"))
    end

    it 'résout le pilote ligne par ligne' do
      row1 = dossier.repetition_row_ids(repetition_tdc).first || dossier.repetition_add_row(repetition_tdc, updated_by: 'test')
      row2 = dossier.repetition_add_row(repetition_tdc, updated_by: 'test')
      dossier.reload
      dossier.project_champ(pilot_tdc, row_id: row1).update!(value: 'Semences')
      dossier.project_champ(pilot_tdc, row_id: row2).update!(value: 'Plants')
      dossier.reload

      expect(described_class.for(type_de_champ: rdp_tdc, dossier:, row_id: row1).pilot_value).to eq('Semences')
      expect(described_class.for(type_de_champ: rdp_tdc, dossier:, row_id: row2).pilot_value).to eq('Plants')
    end
  end

  context 'pilote dans un autre bloc' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :repetition, libelle: 'Autre bloc', children: [{ type: :drop_down_list, libelle: 'Type', options: ['A'] }] },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, referentiel_filter: filter_config },
      ])
    end
    let(:other_pilot) { procedure.draft_revision.children_of(procedure.draft_revision.types_de_champ_public.first).first }
    let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
    let(:pilot_column_id) { 'type_de_champ/0' }
    let(:dossier) { create(:dossier, procedure:) }

    it 'est invalide (sémantique ambiguë : quelle ligne ?)' do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => "type_de_champ/#{other_pilot.stable_id}"))
      f = described_class.for(type_de_champ: rdp_tdc.reload, dossier:)
      expect(f.invalid?).to be(true)
      expect(f.pilot_value).to be_nil
    end
  end
end
```

Note pour l'implémenteur : le `let(:pilot_tdc_stable_id)` du premier contexte est un artefact de construction (le stable_id n'existe qu'après `create`) ; il est immédiatement écrasé par le `before`. Le supprimer si RuboCop se plaint d'un `let` inutilisé et poser `let(:pilot_column_id) { 'type_de_champ/0' }` à la place.

- [ ] **Step 3 : Vérifier l'échec**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb`
Expected: FAIL — `NameError: uninitialized constant ReferentielDePolynesie::ContextualFilter`.

- [ ] **Step 4 : Implémenter**

Créer `app/lib/referentiel_de_polynesie/contextual_filter.rb` :

```ruby
# frozen_string_literal: true

# pf: cascade référentiel — résout le champ « pilote » d'un referentiel_de_polynesie filtré,
# construit le filtre Baserow correspondant et compare localement une ligne sélectionnée.
# Point unique de résolution partagé par le endpoint #search (rempart n°1), le composant
# éditable (message d'état vide) et la validation au dépôt (rempart n°2).
# Spec : docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md
class ReferentielDePolynesie::ContextualFilter
  TEXT_TYPES = ['text', 'long_text', 'email', 'formula'].freeze
  SELECT_TYPES = ['single_select', 'multiple_select'].freeze
  FILTERABLE_BASEROW_TYPES = (TEXT_TYPES + SELECT_TYPES).freeze
  # pf: v1 — pas de :enums (pilote multi-valué : sémantique OU non définie)
  PILOT_COLUMN_TYPES = [:text, :enum].freeze

  attr_reader :type_de_champ, :dossier, :row_id

  def self.for(type_de_champ:, dossier:, row_id: nil)
    new(type_de_champ:, dossier:, row_id:)
  end

  def initialize(type_de_champ:, dossier:, row_id: nil)
    @type_de_champ = type_de_champ
    @dossier = dossier
    @row_id = row_id.presence
  end

  def config
    @config ||= Hash(type_de_champ.referentiel_filter).with_indifferent_access.presence
  end

  def configured? = config.present?

  def baserow_field_id = config&.dig(:baserow_field_id).to_i

  def baserow_field_name = config&.dig(:baserow_field_name).to_s

  # pf: config présente mais inexploitable : colonne pilote inconnue de la procédure, TDC pilote
  # absent de la révision du dossier, ou pilote dans un bloc qui n'est pas celui du référentiel.
  def invalid?
    return false unless configured?

    pilot_column.nil? || baserow_field_id <= 0 || (pilot_column.is_a?(Columns::ChampColumn) && (pilot_tdc.nil? || foreign_block_pilot?))
  end

  def pilot_column
    return @pilot_column if defined?(@pilot_column)

    @pilot_column = begin
      return nil unless configured?

      dossier.procedure.find_column(h_id: { procedure_id: dossier.procedure_id, column_id: config[:pilot_column_id].to_s })
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end

  def pilot_tdc
    return @pilot_tdc if defined?(@pilot_tdc)

    @pilot_tdc = if pilot_column.is_a?(Columns::ChampColumn)
      dossier.revision.types_de_champ.find { _1.stable_id == pilot_column.stable_id }
    end
  end

  def pilot_libelle
    pilot_tdc&.libelle.presence || pilot_column&.label.to_s
  end

  # pf: valeur du pilote résolue côté serveur (dossier persisté), jamais depuis le client.
  # Pour un pilote de la même ligne de bloc, on projette le champ dans la ligne du référentiel.
  def pilot_value
    return @pilot_value if defined?(@pilot_value)

    @pilot_value = begin
      raw = if invalid? || pilot_column.nil?
        nil
      elsif pilot_column.is_a?(Columns::ChampColumn)
        pilot_column.value(dossier.project_champ(pilot_tdc, row_id: pilot_row_id))
      else
        pilot_column.value(dossier)
      end
      Array.wrap(raw).map { _1.to_s.strip }.compact_blank.first
    end
  end

  # pf: filtre Baserow { field_id:, type:, value: } ou nil (fail-closed : le contrôleur renvoie []).
  # fields : Hash id → { name:, type:, select_options: } (ReferentielDePolynesie::API.table_fields)
  def baserow_scope(fields)
    return nil if pilot_value.blank?

    field = fields&.dig(baserow_field_id)
    return nil if field.nil?

    case field[:type]
    when *TEXT_TYPES
      { field_id: baserow_field_id, type: 'equal', value: pilot_value }
    when *SELECT_TYPES
      option = Array(field[:select_options]).find { _1[:value].to_s.casecmp?(pilot_value) }
      return nil if option.nil?

      { field_id: baserow_field_id, type: field[:type] == 'single_select' ? 'single_select_equal' : 'multiple_select_has', value: option[:id] }
    end
  end

  # pf: comparaison locale (aucun appel Baserow). row_data est le hash plat stocké dans champ.data ;
  # une multiple_select y est simplifiée en « A, B ». Colonne absente → antériorité tolérée.
  def matches_row_data?(row_data)
    return true if row_data.nil? || !row_data.key?(baserow_field_name)

    values = row_data[baserow_field_name].to_s.split(',').map(&:strip)
    values.any? { _1.casecmp?(pilot_value.to_s) }
  end

  def empty_label
    if pilot_value.blank?
      I18n.t('shared.champs.referentiel_de_polynesie.filter_pilot_blank', pilot: pilot_libelle)
    else
      I18n.t('shared.champs.referentiel_de_polynesie.filter_no_match', value: pilot_value)
    end
  end

  private

  def own_parent_tdc
    return @own_parent_tdc if defined?(@own_parent_tdc)

    @own_parent_tdc = dossier.revision.parent_of(type_de_champ)
  end

  def pilot_parent_tdc
    return @pilot_parent_tdc if defined?(@pilot_parent_tdc)

    @pilot_parent_tdc = pilot_tdc && dossier.revision.parent_of(pilot_tdc)
  end

  def same_row_pilot?
    pilot_parent_tdc.present? && own_parent_tdc.present? && pilot_parent_tdc.stable_id == own_parent_tdc.stable_id
  end

  def foreign_block_pilot?
    pilot_parent_tdc.present? && !same_row_pilot?
  end

  def pilot_row_id
    same_row_pilot? ? row_id : nil
  end
end
```

- [ ] **Step 5 : Vérifier le succès**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb`
Expected: PASS. Si `create(:dossier, procedure:)` ne crée pas de ligne de répétition par défaut, le `|| dossier.repetition_add_row(...)` du test couvre le cas.

- [ ] **Step 6 : Lint + commit**

```bash
bundle exec rubocop -a app/lib/referentiel_de_polynesie/contextual_filter.rb spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb
git add app/lib/referentiel_de_polynesie/contextual_filter.rb spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb config/locales/shared.fr.yml config/locales/shared.en.yml
git commit -m "feat(referentiel): service ContextualFilter (résolution du pilote et filtre Baserow)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4 : Endpoint `#search` — paramètres `stable_id` / `row_id`, filtre cascade, fail-closed

**Files:**
- Modify: `app/controllers/data_sources/referentiel_de_polynesie_controller.rb`
- Test: `spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`

**Interfaces:**
- Consumes: `ReferentielDePolynesie::ContextualFilter` (Task 3), `ReferentielDePolynesie::API.table_fields` / `search_with_data(…, scopes:)` (Task 2).
- Produces: `GET data_sources/referentiel_de_polynesie/:table/search?q=&dossier_id=&stable_id=&row_id=` — `stable_id` (Integer) et `row_id` (String ULID, optionnel) ; 400 si `stable_id` ne désigne pas un `referentiel_de_polynesie` de la révision du dossier portant `table` ; `[]` si pilote vide / config invalide (Sentry) / option introuvable ; sinon filtre cumulé aux autres `scopes`.

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`, à l'intérieur de `describe 'GET #search'`, ajouter :

```ruby
    context 'sur un champ à filtre contextuel (cascade)' do
      let(:referentiel) { create(:baserow_referentiel) } # baserow://24
      let(:procedure) do
        create(:procedure, :published, types_de_champ_public: [
          { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
          { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
        ])
      end
      let(:pilot_tdc) { procedure.active_revision.types_de_champ_public.first }
      let(:rdp_tdc) { procedure.active_revision.types_de_champ_public.second }
      let(:dossier) { create(:dossier, procedure:, user:) }
      let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }, { id: 101, value: 'Plants' }] } } }
      let(:cascade_params) { { table: domain_id, dossier_id: dossier.id, stable_id: rdp_tdc.stable_id } }

      before do
        rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
        allow(ReferentielDePolynesie::API).to receive(:table_fields).with(domain_id).and_return(fields)
      end

      it 'injecte le filtre single_select_equal résolu depuis le pilote, même avec q vide' do
        dossier.project_champ(pilot_tdc).update!(value: 'Semences')
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, nil, drop_down_other: nil, scopes: [{ field_id: 12, type: 'single_select_equal', value: 100 }])
          .and_return([{ label: 'Blé', value: '24:1', row_data: }])

        get :search, params: cascade_params
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.first['label']).to eq('Blé')
      end

      it 'q libre ne désactive jamais le filtre' do
        dossier.project_champ(pilot_tdc).update!(value: 'Plants')
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, 'Rosier', drop_down_other: nil, scopes: [{ field_id: 12, type: 'single_select_equal', value: 101 }])
          .and_return([])

        get :search, params: cascade_params.merge(q: 'Rosier')
        expect(response).to have_http_status(:ok)
      end

      it 'pilote vide → [] sans appeler Baserow (fail-closed)' do
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)
        get :search, params: cascade_params
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end

      it 'option Baserow introuvable → []' do
        dossier.project_champ(pilot_tdc).update!(value: 'Semences')
        allow(ReferentielDePolynesie::API).to receive(:table_fields).with(domain_id).and_return({ 12 => { name: 'Catégorie', type: 'single_select', select_options: [] } })
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)
        get :search, params: cascade_params
        expect(response.parsed_body).to eq([])
      end

      it 'config invalide (pilote disparu) → [] + Sentry, jamais la table entière' do
        rdp_tdc.update!(referentiel_filter: rdp_tdc.referentiel_filter.merge('pilot_column_id' => 'type_de_champ/424242'))
        expect(Sentry).to receive(:capture_message).with('ReferentielDePolynesie: filtre contextuel invalide', extra: hash_including(table: domain_id))
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)
        get :search, params: cascade_params.merge(q: 'Blé')
        expect(response.parsed_body).to eq([])
      end

      it 'refuse (403) le dossier d\'un autre usager' do
        other = create(:dossier, procedure:)
        get :search, params: cascade_params.merge(dossier_id: other.id)
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuse (400) un stable_id qui n\'est pas un référentiel de cette table' do
        get :search, params: cascade_params.merge(stable_id: pilot_tdc.stable_id, q: 'x')
        expect(response).to have_http_status(:bad_request)
      end

      it 'sans referentiel_filter, stable_id est ignoré et le comportement catalogue est inchangé' do
        rdp_tdc.update!(referentiel_filter: nil)
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, 'Blé', drop_down_other: nil, scopes: [])
          .and_return([])
        get :search, params: cascade_params.merge(q: 'Blé')
        expect(response).to have_http_status(:ok)
      end

      it 'cumule le filtre cascade avec le scope DLNUF' do
        allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with(domain_id).and_return({ field_id: 9, field_name: 'Email', field_type: 'email' })
        dossier.project_champ(pilot_tdc).update!(value: 'Semences')
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, nil, drop_down_other: nil, scopes: [
            { field_id: 9, type: 'equal', value: user.email.downcase },
            { field_id: 12, type: 'single_select_equal', value: 100 },
          ]).and_return([])
        get :search, params: cascade_params
        expect(response).to have_http_status(:ok)
      end
    end
```

Adapter aussi l'exemple existant « avec des paramètres valides » : le stub `.with(domain_id, term, drop_down_other: nil)` devient `.with(domain_id, term, drop_down_other: nil, scopes: [])` (idem pour les autres stubs catalogue du fichier qui n'ont pas de `scopes:`).

- [ ] **Step 2 : Vérifier l'échec**

Run: `bundle exec rspec spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb -e 'cascade'`
Expected: FAIL — `search_with_data` appelé sans `scopes` cascade, 400 attendu non obtenu, etc.

- [ ] **Step 3 : Réécrire l'action `search`**

Remplacer intégralement le corps de `app/controllers/data_sources/referentiel_de_polynesie_controller.rb` par :

```ruby
# frozen_string_literal: true

class DataSources::ReferentielDePolynesieController < ApplicationController
  before_action :authenticate_logged_user!

  def search
    @params = search_params
    table = @params[:table]
    dlnuf = ReferentielDePolynesie::API.dlnuf_config(table)
    drop_down_other = ActiveModel::Type::Boolean.new.cast(@params[:drop_down_other])

    if dlnuf == :invalid
      # pf: fail-closed — champ propriétaire mort : refuser d'exposer, JAMAIS de repli en
      # catalogue ouvert (les données personnelles seraient déclassées en liste publique)
      Sentry.capture_message('ReferentielDePolynesie: champ propriétaire invalide', extra: { table: })
      return render json: { message: 'Configuration du référentiel invalide' }, status: :unprocessable_entity
    end

    scopes = []
    dossier = nil

    if dlnuf.present?
      dossier = authorized_dossier
      return if performed?

      # pf: DLNUF — scope = mail du TITULAIRE (dossier.user), pas l'utilisateur connecté :
      # un invité doit préremplir avec les données du titulaire. Jamais lu depuis le client.
      email = dossier.user&.email&.downcase
      return render json: [] if email.blank? # pf: fail-closed silencieux (dossier orphelin prefillé, etc.)

      scopes << { field_id: dlnuf[:field_id], type: 'equal', value: email }
    end

    if @params[:stable_id].present?
      dossier ||= authorized_dossier
      return if performed?

      filter = contextual_filter_for(dossier, table)
      return if performed?

      if filter.configured?
        scope = contextual_scope(filter, table)
        # pf: cascade fail-closed — pilote vide, config invalide ou option introuvable → liste
        # vide, jamais la table entière
        return render json: [] if scope.nil?

        scopes << scope
      end
    end

    if scopes.empty? && (table.blank? || @params[:q].blank?)
      render json: { message: "table & q parameters are required" }, status: :bad_request
    else
      results = ReferentielDePolynesie::API.search_with_data(table, @params[:q], drop_down_other:, scopes:)
      render json: encrypted_results(results)
    end
  end

  private

  # pf: autorisation DLNUF / cascade — le dossier doit être accessible à current_user via
  # DossierPolicy::Scope (propriétaire, invité, instructeur assigné — l'ancre de scope
  # reste le mail du titulaire). La clause preview du Scope étant globale, on exige en
  # plus qu'un dossier de preview appartienne à current_user : sinon n'importe quel
  # usager pourrait ancrer le scope sur le mail de l'admin d'une autre démarche.
  def authorized_dossier
    dossier = policy_scope(Dossier).find_by(id: @params[:dossier_id])
    if dossier.nil? || (dossier.for_procedure_preview? && dossier.user != current_user)
      render json: { message: 'Accès refusé' }, status: :forbidden
      return nil
    end
    dossier
  end

  # pf: cascade — le stable_id doit désigner un referentiel_de_polynesie de la révision du
  # dossier ET porter la table demandée (sinon un client pourrait filtrer une autre table
  # avec la config d'un autre champ).
  def contextual_filter_for(dossier, table)
    tdc = dossier.revision.types_de_champ.find { _1.stable_id == @params[:stable_id].to_i }
    if tdc.nil? || !tdc.referentiel_de_polynesie? || tdc.table_id != table.to_s
      render json: { message: 'Champ invalide pour cette table' }, status: :bad_request
      return nil
    end

    ReferentielDePolynesie::ContextualFilter.for(type_de_champ: tdc, dossier:, row_id: @params[:row_id])
  end

  def contextual_scope(filter, table)
    if filter.invalid?
      Sentry.capture_message('ReferentielDePolynesie: filtre contextuel invalide', extra: { table:, stable_id: @params[:stable_id] })
      return nil
    end
    return nil if filter.pilot_value.blank?

    filter.baserow_scope(ReferentielDePolynesie::API.table_fields(table))
  end

  def encrypted_results(results)
    results.map do |r|
      data = r[:row_data].present? ? message_encryptor_service.encrypt_and_sign(r[:row_data].to_json, purpose: :storage, expires_in: 1.hour) : ""
      r.slice(:label, :value).merge(data:)
    end
  end

  def search_params = params.permit(:table, :q, :drop_down_other, :dossier_id, :stable_id, :row_id)
end
```

- [ ] **Step 4 : Vérifier le succès**

Run: `bundle exec rspec spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`
Expected: PASS (anciens et nouveaux exemples).

- [ ] **Step 5 : Lint + commit**

```bash
bundle exec rubocop -a app/controllers/data_sources/referentiel_de_polynesie_controller.rb spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb
git add app/controllers/data_sources/referentiel_de_polynesie_controller.rb spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb
git commit -m "feat(referentiel): filtre contextuel côté serveur dans #search (fail-closed)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5 : Validation non-destructive au dépôt (rempart n°2)

**Files:**
- Modify: `app/models/champs/referentiel_de_polynesie_champ.rb` (après la ligne `validate :dlnuf_owner_integrity …`, et méthode privée après `dlnuf_owner_integrity`)
- Modify: `config/locales/models/champs/champs.fr.yml`, `config/locales/models/champs/champs.en.yml`
- Test: `spec/models/champs/referentiel_de_polynesie_champ_spec.rb`

**Interfaces:**
- Consumes: `ReferentielDePolynesie::ContextualFilter` (Task 3), `TypeDeChamp#referentiel_filter?` (Task 1).
- Produces: erreurs `:value` avec clés `filter_pilot_blank` (`%{pilot}`) et `filter_mismatch` (`%{row_value}`, `%{pilot_value}`, `%{pilot}`).

- [ ] **Step 1 : Locales**

`config/locales/models/champs/champs.fr.yml`, sous `"champs/referentiel_de_polynesie_champ": attributes: value:` ajouter :

```yaml
              filter_pilot_blank: "ne peut pas être renseigné avant « %{pilot} »"
              filter_mismatch: "(« %{row_value} ») ne correspond pas à « %{pilot_value} ». Modifiez ce champ ou « %{pilot} »."
```

`config/locales/models/champs/champs.en.yml`, même emplacement :

```yaml
              filter_pilot_blank: "cannot be filled before “%{pilot}”"
              filter_mismatch: "(“%{row_value}”) does not match “%{pilot_value}”. Change this field or “%{pilot}”."
```

- [ ] **Step 2 : Écrire les tests qui échouent**

Dans `spec/models/champs/referentiel_de_polynesie_champ_spec.rb`, après le `describe 'validation DLNUF au dépôt (second rempart)'`, ajouter :

```ruby
  describe 'validation cascade au dépôt (second rempart)' do
    let(:referentiel) { create(:baserow_referentiel) }
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
      ])
    end
    let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
    let(:dossier) { create(:dossier, procedure:) }
    let(:champ) { dossier.project_champ(rdp_tdc) }
    let(:row_category) { 'Semences' }

    subject { champ.validate(:champs_public_value) }

    before do
      allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).and_return(nil)
      rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
      dossier.project_champ(pilot_tdc).update!(value: 'Semences')
      champ.update_columns(external_id: '24:1', value: 'Blé', data: { 'Nom' => 'Blé', 'Catégorie' => row_category })
      dossier.reload
    end

    context 'quand la ligne correspond au pilote' do
      it { is_expected.to be_truthy }
    end

    context 'quand la ligne correspond à la casse près' do
      let(:row_category) { 'semences' }
      it { is_expected.to be_truthy }
    end

    context 'quand le pilote a changé après la sélection' do
      before { dossier.project_champ(pilot_tdc).update!(value: 'Plants') && dossier.reload }

      it 'ajoute une erreur bloquante nommant les deux valeurs et le pilote' do
        expect(subject).to be_falsey
        expect(champ.errors[:value].join).to include('« Semences »', '« Plants »', '« Type de produit »')
      end
    end

    context 'quand le pilote est vide alors que le référentiel est renseigné' do
      before { dossier.project_champ(pilot_tdc).update!(value: nil) && dossier.reload }

      it 'ajoute une erreur demandant de renseigner le pilote' do
        expect(subject).to be_falsey
        expect(champ.errors[:value].join).to include('« Type de produit »')
      end
    end

    context 'quand la ligne a été choisie avant la config (colonne absente de data)' do
      before { champ.update_columns(data: { 'Nom' => 'Blé' }) && champ.reload }
      it('n\'invalide pas (antériorité tolérée)') { is_expected.to be_truthy }
    end

    context 'quand la config est invalide (pilote disparu)' do
      before { rdp_tdc.update!(referentiel_filter: rdp_tdc.referentiel_filter.merge('pilot_column_id' => 'type_de_champ/424242')) && dossier.reload }
      it('ne bloque pas l\'usager pour une erreur d\'administration') { is_expected.to be_truthy }
    end

    context 'sans referentiel_filter' do
      before { rdp_tdc.update!(referentiel_filter: nil) && dossier.reload }
      let(:row_category) { 'Plants' }
      it { is_expected.to be_truthy }
    end
  end
```

- [ ] **Step 3 : Vérifier l'échec**

Run: `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb -e 'validation cascade'`
Expected: FAIL — les contextes « pilote a changé » et « pilote vide » attendent une erreur et n'en obtiennent pas.

- [ ] **Step 4 : Implémenter**

Dans `app/models/champs/referentiel_de_polynesie_champ.rb`, juste après la ligne `validate :dlnuf_owner_integrity, …`, ajouter :

```ruby
  # pf: cascade, second rempart (dépôt) — la ligne sélectionnée doit correspondre à la valeur
  # actuelle du champ pilote. Couvre le pilote modifié après sélection et toute soumission forgée.
  validate :referentiel_filter_integrity, if: -> { validate_champ_value? && external_id.present? && !other? && type_de_champ.referentiel_filter? }
```

Et dans la section `private`, après `dlnuf_owner_integrity`, ajouter :

```ruby
  # pf: comparaison LOCALE de row_data[colonne Baserow] avec la valeur du pilote (aucun appel
  # Baserow). Config invalide (pilote disparu) → on ne bloque pas l'usager pour une erreur
  # d'administration : le validateur de publication et le rempart n°1 (#search) couvrent ce cas.
  def referentiel_filter_integrity
    filter = ReferentielDePolynesie::ContextualFilter.for(type_de_champ:, dossier:, row_id:)
    return if filter.invalid?

    if filter.pilot_value.blank?
      errors.add(:value, :filter_pilot_blank, pilot: filter.pilot_libelle)
    elsif !filter.matches_row_data?(normalized_data)
      errors.add(:value, :filter_mismatch,
        row_value: normalized_data&.dig(filter.baserow_field_name),
        pilot_value: filter.pilot_value,
        pilot: filter.pilot_libelle)
    end
  end
```

- [ ] **Step 5 : Vérifier le succès**

Run: `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb`
Expected: PASS (y compris les exemples DLNUF existants).

- [ ] **Step 6 : Lint + commit**

```bash
bundle exec rubocop -a app/models/champs/referentiel_de_polynesie_champ.rb spec/models/champs/referentiel_de_polynesie_champ_spec.rb
git add app/models/champs/referentiel_de_polynesie_champ.rb spec/models/champs/referentiel_de_polynesie_champ_spec.rb config/locales/models/champs/champs.fr.yml config/locales/models/champs/champs.en.yml
git commit -m "feat(referentiel): validation locale anti-stale du filtre contextuel au dépôt

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6 : Re-rendu Turbo du référentiel quand son pilote change

**Files:**
- Modify: `app/models/champ.rb` (après `all_dependent_formula_champs`, ~ligne 391)
- Modify: `app/controllers/concerns/turbo_champs_concern.rb:8-24`
- Test: `spec/models/champ_spec.rb` (nouveau `describe`), `spec/controllers/concerns/turbo_champs_concern_spec.rb` s'il existe, sinon couverture via la spec système (Task 10)

**Interfaces:**
- Produces: `Champ#dependent_referentiel_filter_champs` → Array<Champ> des `referentiel_de_polynesie` dont `pilot_column_id` cible ce champ (`type_de_champ/<stable_id>` exact ou suivi de `-`/`.` pour les colonnes dérivées), restreints à la même ligne quand ce champ est dans un bloc.
- Consumes: `TypeDeChamp#referentiel_filter` (Task 1).

- [ ] **Step 1 : Écrire le test qui échoue**

Dans `spec/models/champ_spec.rb`, ajouter à la fin du `describe Champ do` :

```ruby
  describe '#dependent_referentiel_filter_champs (cascade référentiel)' do
    let(:referentiel) { create(:baserow_referentiel) }
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
        { type: :referentiel_de_polynesie, libelle: 'Autre référentiel', referentiel: },
        {
          type: :repetition, libelle: 'Lignes', children: [
            { type: :drop_down_list, libelle: 'Type ligne', options: ['A', 'B'] },
            { type: :referentiel_de_polynesie, libelle: 'Produit ligne', referentiel: },
          ],
        },
      ])
    end
    let(:revision) { procedure.draft_revision }
    let(:pilot_tdc) { revision.types_de_champ_public[0] }
    let(:rdp_tdc) { revision.types_de_champ_public[1] }
    let(:repetition_tdc) { revision.types_de_champ_public[3] }
    let(:line_pilot_tdc) { revision.children_of(repetition_tdc).first }
    let(:line_rdp_tdc) { revision.children_of(repetition_tdc).second }
    let(:dossier) { create(:dossier, procedure:) }

    before do
      rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
      line_rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{line_pilot_tdc.stable_id}" })
    end

    it 'retourne les référentiels pilotés par ce champ, pas les autres' do
      dependents = dossier.project_champ(pilot_tdc).dependent_referentiel_filter_champs
      expect(dependents.map(&:libelle)).to eq(['Produit'])
    end

    it 'dans un bloc, ne retourne que le référentiel de la même ligne' do
      row1 = dossier.repetition_row_ids(repetition_tdc).first || dossier.repetition_add_row(repetition_tdc, updated_by: 'test')
      row2 = dossier.repetition_add_row(repetition_tdc, updated_by: 'test')
      dossier.reload
      dependents = dossier.project_champ(line_pilot_tdc, row_id: row1).dependent_referentiel_filter_champs
      expect(dependents.map { [_1.libelle, _1.row_id] }).to eq([['Produit ligne', row1]])
      expect(row2).to be_present
    end

    it 'retourne [] pour un champ qui ne pilote rien' do
      expect(dossier.project_champ(rdp_tdc).dependent_referentiel_filter_champs).to eq([])
    end
  end
```

- [ ] **Step 2 : Vérifier l'échec**

Run: `bundle exec rspec spec/models/champ_spec.rb -e 'dependent_referentiel_filter_champs'`
Expected: FAIL — `NoMethodError`.

- [ ] **Step 3 : Implémenter**

Dans `app/models/champ.rb`, après la méthode `all_dependent_formula_champs` (avant `private`), ajouter :

```ruby
  # pf: cascade référentiel — champs referentiel_de_polynesie dont ce champ est le pilote
  # (options['referentiel_filter']['pilot_column_id'] = "type_de_champ/<stable_id>", éventuellement
  # suivi d'un chemin dérivé "-$.x" ou ".path"). Dans un bloc, seuls ceux de la même ligne ;
  # un pilote hors bloc rafraîchit toutes les lignes. Utilisé par TurboChampsConcern pour
  # re-rendre le référentiel (message d'état vide + périmètre) quand son pilote change.
  def dependent_referentiel_filter_champs
    pattern = /\Atype_de_champ\/#{stable_id}(\z|[-.])/
    dependent_sids = dossier.revision.types_de_champ.filter_map do |tdc|
      next unless tdc.referentiel_filter?

      tdc.stable_id if Hash(tdc.referentiel_filter)['pilot_column_id'].to_s.match?(pattern)
    end
    return [] if dependent_sids.empty?

    (dossier.project_champs_public_all + dossier.project_champs_private_all).filter do |champ|
      champ.stable_id.in?(dependent_sids) && (row_id.nil? || champ.row_id.nil? || champ.row_id == row_id)
    end
  end
```

Dans `app/controllers/concerns/turbo_champs_concern.rb`, après la ligne `to_update += updated_champs.flat_map(&:all_dependent_formula_champs).uniq`, ajouter :

```ruby
    # pf: cascade référentiel — re-rendre les référentiels dont le pilote vient de changer
    to_update += updated_champs.flat_map(&:dependent_referentiel_filter_champs).uniq(&:public_id)
```

- [ ] **Step 4 : Vérifier le succès**

Run: `bundle exec rspec spec/models/champ_spec.rb -e 'dependent_referentiel_filter_champs' spec/controllers/users/dossiers_controller_spec.rb -e 'update'`
Expected: PASS (la spec du contrôleur usager ne doit pas régresser).

- [ ] **Step 5 : Lint + commit**

```bash
bundle exec rubocop -a app/models/champ.rb app/controllers/concerns/turbo_champs_concern.rb spec/models/champ_spec.rb
git add app/models/champ.rb app/controllers/concerns/turbo_champs_concern.rb spec/models/champ_spec.rb
git commit -m "feat(referentiel): re-rendu Turbo des référentiels dont le pilote change

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7 : Composant éditable — `stable_id`/`row_id` dans le loader, liste au focus, message d'état vide

**Files:**
- Modify: `app/components/editable_champ/referentiel_de_polynesie_component.rb`
- Test: `spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb` (créer si absent)

**Interfaces:**
- Consumes: `ReferentielDePolynesie::ContextualFilter` (Task 3), `TypeDeChamp#referentiel_filter?` (Task 1).
- Produces: props React `loader` incluant `stable_id` et `row_id` (si présent) quand le filtre est configuré ; `minimumInputLength: 0` ; `emptyLabel` = `ContextualFilter#empty_label` ; **pas** de `hideWhenEmpty` pour la cascade.

- [ ] **Step 1 : Écrire les tests qui échouent**

Créer (ou compléter) `spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb` :

```ruby
# frozen_string_literal: true

describe EditableChamp::ReferentielDePolynesieComponent, type: :component do
  let(:referentiel) { create(:baserow_referentiel) }
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, mandatory: false },
    ])
  end
  let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
  let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.project_champ(rdp_tdc) }
  let(:form) { ActionView::Helpers::FormBuilder.new(:dossier, dossier, vc_test_controller.view_context, {}) }
  let(:component) { described_class.new(form:, champ:) }

  before { allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).and_return(nil) }

  context 'sans filtre contextuel' do
    it 'garde le comportement catalogue (saisie de 2 caractères, pas de stable_id)' do
      props = component.react_props
      expect(props[:minimumInputLength]).to eq(2)
      expect(props[:loader]).not_to include('stable_id')
      expect(props).not_to have_key(:emptyLabel)
    end
  end

  context 'avec filtre contextuel' do
    before do
      rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
      dossier.reload
    end

    it 'transmet stable_id au loader, liste au focus, ne masque jamais le champ' do
      props = component.react_props
      expect(props[:loader]).to include("stable_id=#{rdp_tdc.stable_id}")
      expect(props[:loader]).not_to include('row_id')
      expect(props[:minimumInputLength]).to eq(0)
      expect(props[:hideWhenEmpty]).to be_nil
    end

    it 'affiche « Renseignez d\'abord » quand le pilote est vide' do
      expect(component.react_props[:emptyLabel]).to eq("Renseignez d'abord « Type de produit »")
    end

    it 'affiche « Aucun résultat pour » quand le pilote est renseigné' do
      dossier.project_champ(pilot_tdc).update!(value: 'Plants')
      dossier.reload
      expect(described_class.new(form:, champ: dossier.project_champ(rdp_tdc)).react_props[:emptyLabel]).to eq('Aucun résultat pour « Plants »')
    end
  end
end
```

(Si le dépôt possède déjà un helper de construction de `form` pour les composants de champs, par exemple dans `spec/components/editable_champ/*_spec.rb`, réutiliser exactement ce patron à la place du `FormBuilder` ci-dessus.)

- [ ] **Step 2 : Vérifier l'échec**

Run: `bundle exec rspec spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb`
Expected: FAIL — `minimumInputLength` vaut 2, pas de `stable_id`, pas d'`emptyLabel`.

- [ ] **Step 3 : Implémenter**

Remplacer `react_props` et la section privée de `app/components/editable_champ/referentiel_de_polynesie_component.rb` :

```ruby
  def react_props
    table = @champ.table_id
    # pf: dossier_id — permet au serveur de résoudre le scope DLNUF (mail du titulaire) et le
    # filtre contextuel sans jamais les lire depuis le client ; ignoré pour les tables catalogue
    props = react_input_opts(id: @champ.focusable_input_id,
      class: 'fr-mt-1w',
      name: @form.field_name(:external_id),
      selectedKey: @champ.selected,
      items: @champ.selected_items,
      loader: data_sources_rdp_search_path(table:, drop_down_other: @champ.drop_down_other?, dossier_id: @champ.dossier_id, **contextual_loader_params),
      limit: 20,
      minimumInputLength: (dlnuf? || contextual_filter?) ? 0 : 2,
      data: { table_id: @champ.table_id })

    if dlnuf?
      # pf: DLNUF — « mes données » n'est pas une recherche : lister au focus, auto-remplir
      # si une seule ligne, et ne JAMAIS échoer le mail dans les messages
      props[:autoSelectSingle] = true
      props[:emptyLabel] = I18n.t('shared.champs.referentiel_de_polynesie.dlnuf_empty')
      # pf: DLNUF — champ optionnel sans donnée : masquer le champ entier (zéro friction) ;
      # obligatoire : rester affiché avec le message, le requis bloque le dépôt de toute façon
      props[:hideWhenEmpty] = !@champ.mandatory?
    end

    if contextual_filter?
      # pf: cascade — le périmètre est petit : lister au focus. JAMAIS de masquage (une erreur
      # de mapping Baserow doit rester visible) ; deux messages selon l'état du pilote.
      props[:emptyLabel] = contextual_filter.empty_label
    end
    props
  end

  private

  # pf: détection du mode DLNUF (cache court côté API). En cas d'échec Baserow ou de config
  # invalide, on retombe sur l'ergonomie catalogue — la sécurité reste côté serveur (#search).
  def dlnuf?
    return @dlnuf if defined?(@dlnuf)

    config = ReferentielDePolynesie::API.dlnuf_config(@champ.table_id)
    @dlnuf = config.present? && config != :invalid
  rescue StandardError
    @dlnuf = false
  end

  # pf: cascade — filtre contextuel résolu côté serveur pour le message d'état vide
  def contextual_filter
    return @contextual_filter if defined?(@contextual_filter)

    @contextual_filter = type_de_champ.referentiel_filter? ? ReferentielDePolynesie::ContextualFilter.for(type_de_champ:, dossier: @champ.dossier, row_id: @champ.row_id) : nil
  end

  def contextual_filter?
    contextual_filter.present? && contextual_filter.configured?
  end

  def contextual_loader_params
    return {} unless contextual_filter?

    { stable_id: @champ.stable_id, row_id: @champ.row_id }.compact
  end
```

- [ ] **Step 4 : Vérifier le succès**

Run: `bundle exec rspec spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb spec/system/users/referentiel_dlnuf_spec.rb`
Expected: PASS (la spec système DLNUF ne doit pas régresser ; headless).

- [ ] **Step 5 : Lint + commit**

```bash
bundle exec rubocop -a app/components/editable_champ/referentiel_de_polynesie_component.rb spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb
git add app/components/editable_champ/referentiel_de_polynesie_component.rb spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb
git commit -m "feat(referentiel): composant filtré — stable_id/row_id, liste au focus, état vide

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8 : Éditeur administrateur — case « Restreindre… » et deux listes

**Files:**
- Modify: `app/models/procedure_revision_type_de_champ.rb` (après `available_columns_for_formula`)
- Modify: `app/components/types_de_champ_editor/champ_component.rb` (méthodes publiques après `ai_prompt_for_formula`)
- Modify: `app/components/types_de_champ_editor/champ_component/champ_component.html.haml:373-378` (bloc `drop_down_other` du référentiel de Polynésie)
- Modify: `app/controllers/administrateurs/types_de_champ_controller.rb:280-323` (`INSTANCE_PARAMS`, `type_de_champ_update_params`)
- Test: `spec/models/procedure_revision_type_de_champ_spec.rb`, `spec/components/types_de_champ_editor/champ_component_spec.rb`, `spec/controllers/administrateurs/types_de_champ_controller_spec.rb`

**Interfaces:**
- Produces: `ProcedureRevisionTypeDeChamp#pilot_columns_for_referentiel_filter` → Array<Column> (types `:text`/`:enum`, coordonnées supérieures : racine avant / même ligne avant / publiques pour une annotation), dédoublonnées par `column_id` ; champs de formulaire `type_de_champ[referentiel_filter_form][enabled|baserow_field_id|pilot_column_id]`.
- Consumes: `TypeDeChamp#referentiel_filter_form=` (Task 1), `ReferentielDePolynesie::API.table_fields` (Task 2), `ContextualFilter::FILTERABLE_BASEROW_TYPES` / `PILOT_COLUMN_TYPES` (Task 3).

- [ ] **Step 1 : Test du catalogue des pilotes (échec)**

Dans `spec/models/procedure_revision_type_de_champ_spec.rb`, ajouter à la fin du `describe` principal :

```ruby
  describe '#pilot_columns_for_referentiel_filter (cascade référentiel)' do
    let(:referentiel) { create(:baserow_referentiel) }
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
        { type: :date, libelle: 'Date' },
        { type: :text, libelle: 'Commentaire' },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
        { type: :drop_down_list, libelle: 'Après', options: ['x'] },
        {
          type: :repetition, libelle: 'Lignes', children: [
            { type: :drop_down_list, libelle: 'Type ligne', options: ['A'] },
            { type: :referentiel_de_polynesie, libelle: 'Produit ligne', referentiel: },
            { type: :text, libelle: 'Après ligne' },
          ],
        },
        {
          type: :repetition, libelle: 'Autre bloc', children: [
            { type: :drop_down_list, libelle: 'Type autre', options: ['B'] },
          ],
        },
      ])
    end
    let(:revision) { procedure.draft_revision }

    it 'à la racine : champs texte/choix placés avant, pas la date ni les champs suivants' do
      coordinate = revision.coordinate_for(revision.types_de_champ_public[3])
      expect(coordinate.pilot_columns_for_referentiel_filter.map(&:label)).to eq(['Type de produit', 'Commentaire'])
    end

    it 'dans un bloc : frères précédents de la même ligne + racine avant le bloc, pas l\'autre bloc' do
      repetition = revision.types_de_champ_public[5]
      line_rdp = revision.children_of(repetition).second
      coordinate = revision.coordinate_for(line_rdp)
      labels = coordinate.pilot_columns_for_referentiel_filter.map(&:label)
      expect(labels).to include('Type ligne', 'Type de produit', 'Commentaire', 'Après')
      expect(labels).not_to include('Après ligne', 'Type autre', 'Date', 'Produit')
    end
  end
```

Run: `bundle exec rspec spec/models/procedure_revision_type_de_champ_spec.rb -e 'pilot_columns'`
Expected: FAIL — `NoMethodError`.

- [ ] **Step 2 : Implémenter le catalogue**

Dans `app/models/procedure_revision_type_de_champ.rb`, après `available_columns_for_formula`, ajouter :

```ruby
  # pf: cascade référentiel — colonnes pouvant piloter le filtre d'un referentiel_de_polynesie :
  # champs texte/choix des coordonnées supérieures (frères précédents de la même ligne, racine
  # avant le bloc, publics pour une annotation). Pas de bloc répétable, pas d'autre bloc.
  # Source de vérité partagée par l'éditeur (liste B) et ReferentielFilterValidator.
  def pilot_columns_for_referentiel_filter
    upper_coordinates
      .map(&:type_de_champ)
      .filter { _1.fillable? && !_1.repetition? && _1.stable_id != type_de_champ.stable_id }
      .flat_map { _1.columns(procedure:) }
      .filter { _1.type.in?(ReferentielDePolynesie::ContextualFilter::PILOT_COLUMN_TYPES) }
      .uniq(&:column_id)
  end
```

Run: `bundle exec rspec spec/models/procedure_revision_type_de_champ_spec.rb -e 'pilot_columns'`
Expected: PASS. (Si le premier exemple renvoie aussi des colonnes système, c'est que `upper_coordinates` n'en contient pas : le filtre `type_de_champ` suffit. Si l'ordre diffère, adapter l'expectation avec `match_array`.)

- [ ] **Step 3 : Test du composant éditeur (échec)**

Dans `spec/components/types_de_champ_editor/champ_component_spec.rb`, à l'intérieur de `describe 'render'`, ajouter :

```ruby
    describe 'tdc referentiel_de_polynesie — filtre contextuel' do
      let(:referentiel) { create(:baserow_referentiel) }
      let(:procedure) do
        create(:procedure, types_de_champ_public: [
          { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
          { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
        ])
      end
      let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.second }
      let(:component) { described_class.new(coordinate:, upper_coordinates: coordinate.upper_coordinates) }
      let(:fields) do
        {
          1 => { name: 'Nom', type: 'text', select_options: [] },
          12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }] },
          20 => { name: 'Fichier', type: 'file', select_options: [] },
        }
      end

      before { allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields) }

      it 'affiche la case décochée et les listes masquées par défaut' do
        render_inline(component)
        expect(page).to have_unchecked_field('Restreindre les lignes proposées selon un autre champ du formulaire')
        expect(page).to have_css('[data-hide-target-target="toHide"].fr-hidden')
        expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Nom', 'Catégorie'])
        expect(page).not_to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Fichier'])
        expect(page).to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', with_options: ['Type de produit'])
      end

      it 'affiche la case cochée et les listes visibles quand un filtre est configuré' do
        coordinate.type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{procedure.draft_revision.types_de_champ_public.first.stable_id}" })
        render_inline(component)
        expect(page).to have_checked_field('Restreindre les lignes proposées selon un autre champ du formulaire')
        expect(page).to have_css('[data-hide-target-target="toHide"]:not(.fr-hidden)')
        expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
      end

      it 'garde la colonne en cache et prévient quand Baserow est injoignable' do
        allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(nil)
        coordinate.type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/1' })
        render_inline(component)
        expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
        expect(page).to have_text('Colonnes indisponibles pour le moment')
      end
    end
```

Run: `bundle exec rspec spec/components/types_de_champ_editor/champ_component_spec.rb -e 'filtre contextuel'`
Expected: FAIL — case et listes absentes.

- [ ] **Step 4 : Implémenter le composant éditeur**

Dans `app/components/types_de_champ_editor/champ_component.rb`, après `ai_prompt_for_formula`, ajouter :

```ruby
  # pf: cascade référentiel — état et options des deux listes de l'éditeur
  def referentiel_filter_enabled?
    type_de_champ.referentiel_filter?
  end

  def referentiel_filter_value(key)
    Hash(type_de_champ.referentiel_filter)[key.to_s]
  end

  # pf: liste A — colonnes Baserow filtrables ; repli sur la colonne en cache si Baserow est injoignable
  def referentiel_filter_baserow_options
    return @referentiel_filter_baserow_options if defined?(@referentiel_filter_baserow_options)

    fields = begin
      ReferentielDePolynesie::API.table_fields(type_de_champ.table_id)
    rescue StandardError
      nil
    end
    @referentiel_filter_baserow_fields_unavailable = fields.nil?

    options = Hash(fields).filter_map do |id, field|
      [field[:name], id] if field[:type].in?(ReferentielDePolynesie::ContextualFilter::FILTERABLE_BASEROW_TYPES)
    end
    if options.empty? && referentiel_filter_value(:baserow_field_id).present?
      options = [[referentiel_filter_value(:baserow_field_name), referentiel_filter_value(:baserow_field_id).to_i]]
    end
    @referentiel_filter_baserow_options = options
  end

  def referentiel_filter_baserow_fields_unavailable?
    referentiel_filter_baserow_options
    @referentiel_filter_baserow_fields_unavailable
  end

  # pf: liste B — champs pilotes admissibles (cf. ProcedureRevisionTypeDeChamp)
  def referentiel_filter_pilot_options
    coordinate.pilot_columns_for_referentiel_filter.map { [_1.label, _1.column_id] }
  end
```

Dans `app/components/types_de_champ_editor/champ_component/champ_component.html.haml`, juste après le bloc (lignes ~373-378) :

```haml
          - if type_de_champ.referentiel_de_polynesie?
            .cell.flex.align-center.fr-mt-1w
              = form.check_box :drop_down_other, class: "small-margin small", id: dom_id(type_de_champ, :drop_down_other)
              = form.label :drop_down_other, for: dom_id(type_de_champ, :drop_down_other) do
                Proposer une option « autre » avec un texte libre
```

ajouter, **au même niveau d'indentation que ce `- if`** :

```haml
          -# pf: cascade — restreindre les lignes proposées selon un autre champ du formulaire (lot A)
          - if type_de_champ.referentiel_de_polynesie? && type_de_champ.table_id.present?
            .cell.fr-mt-2w{ data: { controller: 'hide-target' } }
              .fr-toggle
                = check_box_tag 'type_de_champ[referentiel_filter_form][enabled]', '1', referentiel_filter_enabled?,
                  id: dom_id(type_de_champ, :referentiel_filter_enabled),
                  class: 'fr-toggle__input',
                  data: { 'hide-target-target': 'source' }
                = label_tag dom_id(type_de_champ, :referentiel_filter_enabled), 'Restreindre les lignes proposées selon un autre champ du formulaire', class: 'fr-toggle__label fr-label'
              .cell.flex.flex-gap.fr-mt-1w{ class: class_names('fr-hidden': !referentiel_filter_enabled?), data: { 'hide-target-target': 'toHide' } }
                .flex-grow
                  = label_tag dom_id(type_de_champ, :referentiel_filter_baserow_field_id), 'Colonne du référentiel à filtrer', class: 'fr-label'
                  = select_tag 'type_de_champ[referentiel_filter_form][baserow_field_id]',
                    options_for_select(referentiel_filter_baserow_options, referentiel_filter_value(:baserow_field_id)),
                    include_blank: 'Choisir une colonne',
                    id: dom_id(type_de_champ, :referentiel_filter_baserow_field_id),
                    class: 'fr-select small-margin small width-100'
                  - if referentiel_filter_baserow_fields_unavailable?
                    %p.fr-hint-text.fr-mb-0 Colonnes indisponibles pour le moment
                .flex-grow
                  = label_tag dom_id(type_de_champ, :referentiel_filter_pilot_column_id), 'Champ du formulaire qui pilote le filtre', class: 'fr-label'
                  = select_tag 'type_de_champ[referentiel_filter_form][pilot_column_id]',
                    options_for_select(referentiel_filter_pilot_options, referentiel_filter_value(:pilot_column_id)),
                    include_blank: 'Choisir un champ',
                    id: dom_id(type_de_champ, :referentiel_filter_pilot_column_id),
                    class: 'fr-select small-margin small width-100'
                  %p.fr-hint-text.fr-mb-0 Seuls les champs texte ou à choix unique placés avant ce champ sont proposés.
```

Run: `bundle exec rspec spec/components/types_de_champ_editor/champ_component_spec.rb`
Expected: PASS.

- [ ] **Step 5 : Test du contrôleur admin (échec)**

Dans `spec/controllers/administrateurs/types_de_champ_controller_spec.rb`, dans `describe '#update'`, ajouter :

```ruby
    context 'filtre contextuel d\'un referentiel_de_polynesie' do
      let(:referentiel) { create(:baserow_referentiel) }
      let(:procedure) do
        create(:procedure, administrateur: admin, types_de_champ_public: [
          { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
          { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
        ])
      end
      let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
      let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
      let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [] } } }

      before { allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields) }

      it 'enregistre la config quand la case est cochée et les deux listes renseignées' do
        put :update, params: { procedure_id: procedure.id, stable_id: rdp_tdc.stable_id, type_de_champ: { referentiel_filter_form: { enabled: '1', baserow_field_id: '12', pilot_column_id: "type_de_champ/#{pilot_tdc.stable_id}" } } }, format: :turbo_stream
        expect(rdp_tdc.reload.referentiel_filter).to eq('baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}")
      end

      it 'efface la config quand la case est décochée' do
        rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
        put :update, params: { procedure_id: procedure.id, stable_id: rdp_tdc.stable_id, type_de_champ: { referentiel_filter_form: { baserow_field_id: '12', pilot_column_id: "type_de_champ/#{pilot_tdc.stable_id}" } } }, format: :turbo_stream
        expect(rdp_tdc.reload.referentiel_filter).to be_nil
      end
    end
```

(Aligner `admin`, le `before { sign_in … }` et le format de la requête sur les exemples `#update` déjà présents dans ce fichier : reprendre exactement leur `default_params` et leur mode d'appel.)

Run: `bundle exec rspec spec/controllers/administrateurs/types_de_champ_controller_spec.rb -e 'filtre contextuel'`
Expected: FAIL — `referentiel_filter` reste nil (paramètre non permis).

- [ ] **Step 6 : Permettre le paramètre**

Dans `app/controllers/administrateurs/types_de_champ_controller.rb` :

Remplacer :

```ruby
    INSTANCE_PARAMS = TypeDeChamp::INSTANCE_OPTIONS.map { |tdc| tdc != :accredited_users ? tdc : :accredited_user_string }
```

par :

```ruby
    # pf: referentiel_filter est un Hash écrit via referentiel_filter_form (case + deux listes),
    # jamais assigné directement depuis le formulaire
    INSTANCE_PARAMS = TypeDeChamp::INSTANCE_OPTIONS
      .reject { _1 == :referentiel_filter }
      .map { |tdc| tdc != :accredited_users ? tdc : :accredited_user_string }
```

Et dans `type_de_champ_update_params`, avant `editable_options: [`, ajouter :

```ruby
        referentiel_filter_form: [:enabled, :baserow_field_id, :pilot_column_id],
```

Run: `bundle exec rspec spec/controllers/administrateurs/types_de_champ_controller_spec.rb`
Expected: PASS.

- [ ] **Step 7 : Lint + commit**

```bash
bundle exec rubocop -a app/models/procedure_revision_type_de_champ.rb app/components/types_de_champ_editor/champ_component.rb app/controllers/administrateurs/types_de_champ_controller.rb spec/models/procedure_revision_type_de_champ_spec.rb spec/components/types_de_champ_editor/champ_component_spec.rb spec/controllers/administrateurs/types_de_champ_controller_spec.rb
bundle exec haml-lint app/components/types_de_champ_editor/champ_component/champ_component.html.haml
git add app/models/procedure_revision_type_de_champ.rb app/components/types_de_champ_editor/ app/controllers/administrateurs/types_de_champ_controller.rb spec/models/procedure_revision_type_de_champ_spec.rb spec/components/types_de_champ_editor/champ_component_spec.rb spec/controllers/administrateurs/types_de_champ_controller_spec.rb
git commit -m "feat(referentiel): éditeur admin du filtre contextuel (case + colonne Baserow + champ pilote)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9 : Validateur de publication `TypesDeChamp::ReferentielFilterValidator`

**Files:**
- Create: `app/validators/types_de_champ/referentiel_filter_validator.rb`
- Modify: `app/models/procedure.rb:233-254` (deux blocs `validates :draft_types_de_champ_*`)
- Modify: `config/locales/models/procedure/fr.yml`, `config/locales/models/procedure/en.yml`
- Test: `spec/validators/types_de_champ/referentiel_filter_validator_spec.rb`

**Interfaces:**
- Consumes: `ProcedureRevisionTypeDeChamp#pilot_columns_for_referentiel_filter` (Task 8), `TypeDeChamp#referentiel_filter?` (Task 1).
- Produces: erreur `procedure.errors[:draft_types_de_champ_public|private]` avec clé `invalid_referentiel_filter` et option `type_de_champ:` (consommée par `Procedure::ErrorsSummary`).

- [ ] **Step 1 : Locales**

Dans `config/locales/models/procedure/fr.yml`, sous `draft_types_de_champ_public:` **et** sous `draft_types_de_champ_private:`, ajouter :

```yaml
              invalid_referentiel_filter: "a un filtre qui référence un champ supprimé, déplacé ou d'un type incompatible"
```

Dans `config/locales/models/procedure/en.yml`, même emplacement (deux fois) :

```yaml
              invalid_referentiel_filter: "has a filter referencing a deleted, moved or incompatible field"
```

- [ ] **Step 2 : Écrire les tests qui échouent**

Créer `spec/validators/types_de_champ/referentiel_filter_validator_spec.rb` :

```ruby
# frozen_string_literal: true

RSpec.describe TypesDeChamp::ReferentielFilterValidator do
  let(:referentiel) { create(:baserow_referentiel) }
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
    ])
  end
  let(:revision) { procedure.draft_revision }
  let(:pilot_tdc) { revision.types_de_champ_public.first }
  let(:rdp_tdc) { revision.types_de_champ_public.second }

  subject { procedure.validate(:types_de_champ_public_editor) }

  def configure_filter(pilot_column_id)
    rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => pilot_column_id })
    procedure.reload
  end

  it 'accepte un pilote admissible' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    expect { subject }.not_to change { procedure.errors.count }
  end

  it 'signale un pilote supprimé, en nommant le référentiel' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    revision.remove_type_de_champ(pilot_tdc.stable_id)
    procedure.reload
    subject
    error = procedure.errors.find { _1.type == :invalid_referentiel_filter } || procedure.errors.first
    expect(procedure.errors[:draft_types_de_champ_public].join).to include('supprimé, déplacé')
    expect(error.options[:type_de_champ]).to eq(rdp_tdc)
  end

  it 'signale un pilote déplacé après le référentiel' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    revision.move_type_de_champ(pilot_tdc.stable_id, 1)
    procedure.reload
    expect { subject }.to change { procedure.errors.count }.by(1)
  end

  it 'signale un pilote changé en un type non filtrable' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    pilot_tdc.update!(type_champ: TypeDeChamp.type_champs.fetch(:date))
    procedure.reload
    expect { subject }.to change { procedure.errors.count }.by(1)
  end

  it 'ignore les référentiels sans filtre' do
    expect { subject }.not_to change { procedure.errors.count }
  end
end
```

- [ ] **Step 3 : Vérifier l'échec**

Run: `bundle exec rspec spec/validators/types_de_champ/referentiel_filter_validator_spec.rb`
Expected: FAIL — `NameError` sur le validateur, puis aucune erreur ajoutée.

- [ ] **Step 4 : Implémenter**

Créer `app/validators/types_de_champ/referentiel_filter_validator.rb` :

```ruby
# frozen_string_literal: true

# pf: cascade référentiel — un referentiel_de_polynesie filtré doit pointer un pilote encore
# admissible (présent, placé avant, à la racine ou dans la même ligne de bloc, de type texte/choix).
# Même régime que ConditionValidator : la suppression du pilote est autorisée, l'erreur apparaît
# dans l'éditeur (ErrorsSummary + champ) et bloque la publication jusqu'à correction.
class TypesDeChamp::ReferentielFilterValidator < ActiveModel::EachValidator
  def validate_each(procedure, collection, tdcs)
    return if tdcs.empty?

    revision = procedure.draft_revision
    tdcs_with_children(procedure, tdcs).each do |tdc|
      next unless tdc.referentiel_filter?

      coordinate = revision.coordinate_for(tdc)
      next if coordinate.nil?

      allowed_ids = coordinate.pilot_columns_for_referentiel_filter.map(&:column_id)
      next if allowed_ids.include?(Hash(tdc.referentiel_filter)['pilot_column_id'].to_s)

      procedure.errors.add(
        collection,
        procedure.errors.generate_message(collection, :invalid_referentiel_filter, { value: tdc.libelle }),
        type_de_champ: tdc
      )
    end
  end

  private

  def tdcs_with_children(procedure, tdcs)
    tdcs.to_a.flat_map { _1.repetition? ? procedure.draft_revision.children_of(_1) : _1 }
  end
end
```

Dans `app/models/procedure.rb`, dans les deux blocs `validates :draft_types_de_champ_public, …` et `validates :draft_types_de_champ_private, …`, ajouter après `'types_de_champ/referentiel_ready': true,` :

```ruby
    'types_de_champ/referentiel_filter': true, # pf: cascade référentiel
```

- [ ] **Step 5 : Vérifier le succès**

Run: `bundle exec rspec spec/validators/types_de_champ/referentiel_filter_validator_spec.rb spec/models/procedure_spec.rb -e 'publish'`
Expected: PASS. Si `procedure.errors.find { _1.type == … }` ne marche pas selon la version d'ActiveModel, utiliser `procedure.errors.to_a` et vérifier le message seul.

- [ ] **Step 6 : Lint + commit**

```bash
bundle exec rubocop -a app/validators/types_de_champ/referentiel_filter_validator.rb app/models/procedure.rb spec/validators/types_de_champ/referentiel_filter_validator_spec.rb
git add app/validators/types_de_champ/referentiel_filter_validator.rb app/models/procedure.rb spec/validators/types_de_champ/referentiel_filter_validator_spec.rb config/locales/models/procedure/fr.yml config/locales/models/procedure/en.yml
git commit -m "feat(referentiel): validateur de publication du filtre contextuel

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10 : Spec système — permis d'importation (Semences / Plants)

**Files:**
- Create: `spec/system/users/referentiel_cascade_spec.rb`

**Interfaces:**
- Consumes: tout ce qui précède. Stubs : `ReferentielDePolynesie::API.dlnuf_config` → nil, `.table_fields('24')`, `.search_with_data('24', anything, drop_down_other: anything, scopes: [...])`.

- [ ] **Step 1 : Écrire la spec**

Créer `spec/system/users/referentiel_cascade_spec.rb` :

```ruby
# frozen_string_literal: true

describe 'Référentiel de Polynésie — cascade (filtre contextuel)', js: true do
  let(:password) { SECURE_PASSWORD }
  let(:user) { create(:user, password:) }
  let(:user_dossier) { user.dossiers.first }
  let(:referentiel) { create(:baserow_referentiel) } # baserow://24
  let(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'], mandatory: true },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, mandatory: true },
      {
        type: :repetition, libelle: 'Lignes', mandatory: false, children: [
          { type: :drop_down_list, libelle: 'Type ligne', options: ['Semences', 'Plants'] },
          { type: :referentiel_de_polynesie, libelle: 'Produit ligne', referentiel: },
        ],
      },
    ])
  end
  let(:revision) { procedure.active_revision }
  let(:pilot_tdc) { revision.types_de_champ_public[0] }
  let(:rdp_tdc) { revision.types_de_champ_public[1] }
  let(:repetition_tdc) { revision.types_de_champ_public[2] }
  let(:line_pilot_tdc) { revision.children_of(repetition_tdc).first }
  let(:line_rdp_tdc) { revision.children_of(repetition_tdc).second }
  let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }, { id: 101, value: 'Plants' }] } } }
  let(:semences_scope) { [{ field_id: 12, type: 'single_select_equal', value: 100 }] }
  let(:plants_scope) { [{ field_id: 12, type: 'single_select_equal', value: 101 }] }
  let(:semences) { [{ label: 'Blé', value: '24:1', row_data: { 'Nom' => 'Blé', 'Catégorie' => 'Semences' } }] }
  let(:plants) { [{ label: 'Rosier', value: '24:2', row_data: { 'Nom' => 'Rosier', 'Catégorie' => 'Plants' } }] }

  before do
    [rdp_tdc, line_rdp_tdc].zip([pilot_tdc, line_pilot_tdc]).each do |rdp, pilot|
      rdp.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot.stable_id}" })
    end
    allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).and_return(nil)
    allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields)
    allow(ReferentielDePolynesie::API).to receive(:search_with_data).with('24', anything, drop_down_other: anything, scopes: semences_scope).and_return(semences)
    allow(ReferentielDePolynesie::API).to receive(:search_with_data).with('24', anything, drop_down_other: anything, scopes: plants_scope).and_return(plants)
  end

  scenario 'le pilote restreint la liste, le changer ne vide pas la sélection mais bloque le dépôt' do
    log_in(user, procedure)
    fill_individual

    within('.editable-champ-referentiel_de_polynesie', match: :first) do
      expect(page).to have_text("Renseignez d'abord « Type de produit »")
    end

    select 'Semences', from: 'Type de produit'
    wait_for_autosave

    find_field('Produit', match: :first).click
    expect(page).to have_css('.fr-menu__item', text: 'Blé')
    expect(page).to have_no_css('.fr-menu__item', text: 'Rosier')
    find('.fr-menu__item', text: 'Blé').click
    wait_for_autosave
    wait_until { champ_value_for('Produit') == 'Blé' }

    select 'Plants', from: 'Type de produit'
    wait_for_autosave
    # pf: non-destructif — la sélection reste
    expect(champ_value_for('Produit')).to eq('Blé')

    click_on 'Déposer le dossier'
    expect(page).to have_text('ne correspond pas à « Plants »')
    expect(user_dossier.reload).to be_brouillon

    select 'Semences', from: 'Type de produit'
    wait_for_autosave
    click_on 'Déposer le dossier'
    expect(page).to have_current_path(merci_dossier_path(user_dossier))
  end

  scenario 'dans un bloc répétable, chaque ligne suit son propre pilote' do
    log_in(user, procedure)
    fill_individual
    select 'Semences', from: 'Type de produit'
    wait_for_autosave

    click_on 'Ajouter un élément pour « Lignes »'
    wait_for_autosave
    click_on 'Ajouter un élément pour « Lignes »'
    wait_for_autosave

    rows = page.all('.repetition .row', minimum: 2)
    within(rows[0]) do
      select 'Semences', from: 'Type ligne'
    end
    wait_for_autosave
    within(rows[1]) do
      select 'Plants', from: 'Type ligne'
    end
    wait_for_autosave

    within(rows[0]) do
      find_field('Produit ligne').click
      expect(page).to have_css('.fr-menu__item', text: 'Blé')
      expect(page).to have_no_css('.fr-menu__item', text: 'Rosier')
      find('.fr-menu__item', text: 'Blé').click
    end
    wait_for_autosave
    within(rows[1]) do
      find_field('Produit ligne').click
      expect(page).to have_css('.fr-menu__item', text: 'Rosier')
      expect(page).to have_no_css('.fr-menu__item', text: 'Blé')
    end
  end

  private

  def log_in(user, procedure)
    login_as user, scope: :user
    visit "/commencer/#{procedure.path}"
    click_on 'Commencer la démarche'
    expect(page).to have_content('Votre identité')
    expect(page).to have_current_path(identite_dossier_path(user_dossier))
  end

  def fill_individual
    fill_in('Prénom', with: 'prenom', visible: true)
    fill_in('Nom', with: 'Nom', visible: true)
    within '#identite-form' do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))
  end

  def champ_value_for(libelle)
    user_dossier.reload.project_champs_public.find { _1.libelle == libelle }&.reload&.value
  end
end
```

Notes pour l'implémenteur :
- Le libellé du bouton d'ajout de ligne et le sélecteur `.repetition .row` doivent être relevés dans `spec/system/users/formula_repetition_aggregate_spec.rb` (même mécanique) et alignés si différents.
- Le libellé du bouton de dépôt est celui utilisé par `spec/system/users/dossier_creation_spec.rb` (« Déposer le dossier »). Le vérifier.
- Le message de dépôt bloqué est celui de `filter_mismatch` (Task 5) : il contient « ne correspond pas à « Plants » ».

- [ ] **Step 2 : Exécuter (headless)**

Run: `NO_HEADLESS= bundle exec rspec spec/system/users/referentiel_cascade_spec.rb`
Expected: PASS, 2 scénarios. En cas d'échec sur le second scénario uniquement à cause d'un sélecteur de ligne, corriger le sélecteur, pas la fonctionnalité ; si le message « Renseignez d'abord » n'apparaît pas, vérifier que `isEmptyScope` du `ComboBox` se déclenche bien avec `minimumInputLength: 0` (comportement identique au DLNUF obligatoire, déjà couvert par `referentiel_dlnuf_spec.rb`).

- [ ] **Step 3 : Commit**

```bash
bundle exec rubocop -a spec/system/users/referentiel_cascade_spec.rb
git add spec/system/users/referentiel_cascade_spec.rb
git commit -m "test(referentiel): scénarios système de la cascade (permis d'importation)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11 : Non-régression, lint global, documentation

**Files:**
- Modify: `french_polynesia.md` (section référentiel de Polynésie : ajouter un paragraphe « Filtre contextuel (cascade) »)
- Modify: `docs/superpowers/specs/2026-07-21-devis-referentiel-dlnuf-cascade-prefill.md` (statut du lot A → « ✅ Livré, branche feature/referentiel-cascade »)

- [ ] **Step 1 : Suites ciblées**

Run:

```bash
bundle exec rspec spec/lib/referentiel_de_polynesie/ spec/models/champs/referentiel_de_polynesie_champ_spec.rb spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb spec/models/champ_spec.rb spec/models/procedure_revision_type_de_champ_spec.rb spec/controllers/data_sources/ spec/controllers/administrateurs/types_de_champ_controller_spec.rb spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb spec/components/types_de_champ_editor/champ_component_spec.rb spec/validators/types_de_champ/ spec/models/procedure_spec.rb spec/controllers/users/dossiers_controller_spec.rb
NO_HEADLESS= bundle exec rspec spec/system/users/referentiel_dlnuf_spec.rb spec/system/users/referentiel_cascade_spec.rb spec/system/users/formula_repetition_aggregate_spec.rb
```

Expected: 0 failures. Toute régression se corrige avant de continuer ; noter dans le rapport tout échec préexistant prouvé indépendant du diff (`git stash` interdit : vérifier sur `origin/devpf` dans un autre worktree si besoin).

- [ ] **Step 2 : Lint global du diff**

```bash
git diff --name-only origin/devpf...HEAD -- '*.rb' | xargs bundle exec rubocop
git diff --name-only origin/devpf...HEAD -- '*.haml' | xargs bundle exec haml-lint
bundle exec i18n-tasks missing --locales fr
bundle exec i18n-tasks unused --locale en
```

Expected: aucune offense, aucune clé manquante.

- [ ] **Step 3 : Documentation**

Dans `french_polynesia.md`, dans la section consacrée au champ « Référentiel de Polynésie », ajouter :

```markdown
#### Filtre contextuel (cascade)

Un champ référentiel peut être restreint aux lignes Baserow dont une colonne égale la valeur
d'un autre champ du formulaire (le « pilote ») : choisir « Semences » dans « Type de produit »
ne propose que des semences dans « Produit ». Configuration dans l'éditeur, derrière la case
« Restreindre les lignes proposées selon un autre champ du formulaire » (colonne Baserow +
champ pilote, texte ou choix unique, placé avant, à la racine ou dans la même ligne de bloc).

- Résolution côté serveur uniquement (`ReferentielDePolynesie::ContextualFilter`, endpoint
  `DataSources::ReferentielDePolynesieController#search` avec `dossier_id`, `stable_id`, `row_id`).
- Fail-closed : pilote vide, config invalide ou option Baserow introuvable → liste vide.
- Jamais de masquage du champ ; deux messages d'état vide (« Renseignez d'abord … » /
  « Aucun résultat pour … »), rafraîchis quand le pilote change (`TurboChampsConcern`).
- Validation locale au dépôt sans appel Baserow (`referentiel_filter_integrity`) ; le changement
  du pilote après sélection ne réinitialise rien mais bloque le dépôt.
- Pilote supprimé / déplacé / changé de type : signalé par `TypesDeChamp::ReferentielFilterValidator`,
  publication bloquée (même régime que les conditions).

Spec : `docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md`.
```

Dans le devis, colonne Statut du lot A : remplacer « 🔧 En cours — … » par « ✅ Livré — branche `feature/referentiel-cascade` (plan `2026-09-14-referentiel-cascade.md`) ».

- [ ] **Step 4 : Commit final et PR**

```bash
git add french_polynesia.md docs/superpowers/specs/2026-07-21-devis-referentiel-dlnuf-cascade-prefill.md
git commit -m "docs(referentiel): documente le filtre contextuel (cascade) et le statut du lot A

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin feature/referentiel-cascade
```

Ouvrir la PR vers `devpf` (convention `feature/*`) avec, dans la description : résumé fonctionnel, invariants de sécurité (§ Global Constraints), **prérequis de recette** (une table Baserow de test avec une colonne `single_select` « Catégorie » et un formulaire « Type de produit » + « Produit »), et la ligne `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## Self-review (fait à la rédaction)

- **Couverture spec** : §1 config + éditeur → Tasks 1, 8 ; §2 validateur → Task 9 ; §3 résolution/sécurité (`stable_id`, `row_id`, opérateurs, fail-closed, `scopes:`, `q` vide) → Tasks 2, 3, 4 ; §4 état vide + rafraîchissement → Tasks 6, 7 ; §5 validation dépôt → Task 5 ; plan de test système → Task 10 ; documentation → Task 11. Pas d'item de spec sans tâche.
- **Écart tranché ici et reporté dans la spec** : pilotes `:enums` exclus de la v1 (`PILOT_COLUMN_TYPES = [:text, :enum]`).
- **Cohérence des noms** : `referentiel_filter` / `referentiel_filter?` / `referentiel_filter_form=` (Task 1) utilisés tels quels en 3, 5, 6, 7, 8, 9 ; `scopes:` (Task 2) en 4 et 10 ; `ContextualFilter.for(type_de_champ:, dossier:, row_id:)` et ses méthodes (Task 3) en 4, 5, 7 ; `table_fields` (Task 2) en 1, 4, 7, 8, 10 ; `pilot_columns_for_referentiel_filter` (Task 8) en 9 ; `dependent_referentiel_filter_champs` (Task 6) dans `TurboChampsConcern`.
- **Placeholders** : aucun « TODO/TBD » ; chaque étape de code est écrite. Les seules adaptations laissées à l'implémenteur sont des alignements sur des patrons existants du dépôt (helper de `form` en spec de composant, `default_params` du contrôleur admin, libellés de boutons en système), explicitement nommés.
