# Référentiel de Polynésie — « Dites-le-nous une fois » (Socle + Lot B) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un champ `referentiel_de_polynesie` dont la table Baserow est marquée « Dites-le-nous une fois » (colonne « Champ propriétaire » dans la table méta) ne propose à l'usager que **ses propres lignes** (scope = mail du titulaire du dossier, résolu côté serveur), liste ses données au focus sans saisie, s'auto-remplit quand une seule ligne existe, et refuse au dépôt une ligne qui n'appartient pas au titulaire.

**Architecture:** Le mode DLNUF est intrinsèque à la donnée, donc détecté dans la **table méta Baserow** (nouvelle colonne nullable « Champ propriétaire » = id du champ e-mail, même mécanisme que « Champ de recherche »). Le scope n'est **jamais** lu depuis le client : le composant transmet `dossier_id` au endpoint `#search`, le serveur vérifie l'accès via `policy_scope(Dossier)` (403 sinon) puis résout `dossier.user.email`. Le filtre `equal` sur le champ propriétaire est injecté en `AND` dans les filtres Baserow, toujours appliqué quel que soit `q`. Deux remparts : filtre serveur à la sélection + validation locale au dépôt (comparaison `row_data[champ propriétaire]` vs mail titulaire, sans appel Baserow de ligne). Fail-closed partout : id propriétaire mort → 422 « configuration invalide » + alerte Sentry, jamais de repli en catalogue ouvert.

**Tech Stack:** Rails 7.0 / Ruby 3.3, Typhoeus (Baserow REST), Pundit (`DossierPolicy::Scope`), React (react-aria-components `RemoteComboBox`), RSpec (+ Capybara/Playwright headless).

**Spec:** `docs/superpowers/specs/2026-07-21-devis-referentiel-dlnuf-cascade-prefill.md` (devis figé — lots Socle + B ; le lot A cascade et le lot C prefill PJ feront l'objet de plans séparés). Spec source complémentaire : `docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md`.

## Global Constraints

- **Invariants de sécurité du devis (§5)** : valeur de scope jamais lue depuis le client ; clé DLNUF = mail du titulaire (`dossier.user.email`), jamais l'utilisateur connecté, jamais DN/SIRET ; fail-closed si champ propriétaire manquant/mort (jamais de repli catalogue) ; deux remparts (sélection + dépôt).
- **Écart assumé vs devis** : le devis parle de transmettre `champ_id` au endpoint. On transmet **`dossier_id`** à la place : un champ peut être `new_record` (pas d'id) au premier rendu du brouillon, et le lot B n'a besoin que du titulaire. Le lot A (cascade) ajoutera `stable_id` plus tard.
- **Item du Socle différé au lot A** : « opérateur Baserow par type de colonne » — inutile pour B (le champ propriétaire est de type e-mail/texte → opérateur `equal` fixe) ; le lot A l'introduira pour les colonnes pilotes `single_select`/`multiple_select`/`link_row`.
- Messages UI : **jamais d'écho du mail** (« Aucune donnée enregistrée à votre nom », pas « Aucun résultat pour xxx@yyy.pf »).
- Tous les textes UI français utilisent l'apostrophe française `'` (U+2019), y compris dans les expectations de tests.
- Toute spécificité PF est marquée `# pf:` (Ruby) / `// pf:` (TS/TSX), en particulier dans les fichiers partagés avec upstream (`ComboBox.tsx`, `hooks.ts`, `props.ts`).
- Branche de travail : `feature/referentiel-dlnuf` (convention CI : `feature/*` → PR vers devpf).
- **Prérequis ops (hors code, à documenter dans la PR)** : ajouter la colonne nullable « Champ propriétaire » dans la table méta Baserow (`API_BASEROW_CONFIG_TABLE`), contenant l'id numérique du champ e-mail de la table cible. La synchro externe dossier → Baserow (alimentation des mails, normalisés en minuscules) est hors périmètre.
- Commandes de test : `bundle exec rspec <fichier>` ; lint : `bundle exec rubocop -a <fichiers>`.

---

### Task 0 : Créer la branche

- [ ] **Step 1 : Créer la branche depuis devpf**

```bash
git checkout devpf && git pull origin devpf && git checkout -b feature/referentiel-dlnuf
```

---

### Task 1 : `BaserowAPI.dlnuf_config` — lecture du « Champ propriétaire »

**Files:**
- Modify: `app/lib/referentiel_de_polynesie/baserow_api.rb`
- Test: `spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`

**Interfaces:**
- Produces: `ReferentielDePolynesie::BaserowAPI.dlnuf_config(domain_id)` →
  - `nil` : table catalogue (pas de colonne « Champ propriétaire » renseignée, ou config introuvable) ;
  - `{ field_id: Integer, field_name: String, field_type: String }` : mode DLNUF valide ;
  - `:invalid` : id renseigné mais champ introuvable dans la table (fail-closed).

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`, ajouter un bloc `describe '.dlnuf_config'`. Réutiliser les `let` existants du fichier (`domain_id`, `table_id`, `base_url`, `config_response`, `fields_response`) et le style de stub Typhoeus existant :

```ruby
  describe '.dlnuf_config' do
    subject { described_class.dlnuf_config(domain_id) }

    let(:owner_field_id) { nil }
    let(:dlnuf_config_response) { config_response.merge('Champ propriétaire' => owner_field_id) }
    let(:dlnuf_fields_response) { fields_response + [{ 'id' => 9, 'name' => 'Email', 'type' => 'email' }] }

    before do
      stub_config = instance_double(Typhoeus::Response, success?: true, body: dlnuf_config_response.to_json)
      allow(Typhoeus).to receive(:get)
        .with("#{base_url}/api/database/rows/table/1/#{domain_id}/", anything)
        .and_return(stub_config)

      stub_fields = instance_double(Typhoeus::Response, success?: true, body: dlnuf_fields_response.to_json)
      allow(Typhoeus).to receive(:get)
        .with("#{base_url}/api/database/fields/table/#{table_id}/", anything)
        .and_return(stub_fields)
    end

    context 'sans colonne « Champ propriétaire » renseignée (catalogue)' do
      let(:owner_field_id) { nil }

      it { is_expected.to be_nil }

      it 'ne lit pas le modèle de la table' do
        subject
        expect(Typhoeus).not_to have_received(:get)
          .with("#{base_url}/api/database/fields/table/#{table_id}/", anything)
      end
    end

    context 'avec un champ propriétaire valide' do
      let(:owner_field_id) { 9 }

      it { is_expected.to eq({ field_id: 9, field_name: 'Email', field_type: 'email' }) }
    end

    context 'avec un id de champ propriétaire mort (champ supprimé)' do
      let(:owner_field_id) { 999 }

      it 'retourne :invalid (fail-closed, jamais nil qui déclasserait en catalogue)' do
        expect(subject).to eq(:invalid)
      end
    end

    context 'avec un champ propriétaire dont le type ne ressemble pas à un mail' do
      let(:owner_field_id) { 9 }
      let(:dlnuf_fields_response) { fields_response + [{ 'id' => 9, 'name' => 'Quantité', 'type' => 'number' }] }

      it 'retourne quand même la config mais loggue un avertissement de diagnostic' do
        expect(Rails.logger).to receive(:warn).with(/champ propriétaire/i)
        expect(subject).to eq({ field_id: 9, field_name: 'Quantité', field_type: 'number' })
      end
    end

    context 'quand la config est introuvable' do
      before do
        stub_error = instance_double(Typhoeus::Response, success?: false, body: 'not found')
        allow(Typhoeus).to receive(:get)
          .with("#{base_url}/api/database/rows/table/1/#{domain_id}/", anything)
          .and_return(stub_error)
      end

      it { is_expected.to be_nil }
    end
  end
```

- [ ] **Step 2 : Vérifier que les tests échouent**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/baserow_api_spec.rb -e dlnuf_config`
Expected: FAIL avec `undefined method 'dlnuf_config'`

- [ ] **Step 3 : Implémenter `dlnuf_config`**

Dans `app/lib/referentiel_de_polynesie/baserow_api.rb`, ajouter après la méthode `config` (ligne ~104) :

```ruby
    # pf: types Baserow plausibles pour un champ e-mail propriétaire (diagnostic, pas un blocage)
    EMAIL_LIKE_TYPES = ['email', 'text', 'formula'].freeze

    # pf: DLNUF (« Dites-le-nous une fois ») — lit la colonne « Champ propriétaire » de la table
    # méta. Invariant : id renseigné ⟺ mode DLNUF ; vide ⟺ catalogue.
    # Fail-closed : id renseigné mais champ introuvable → :invalid. Ne JAMAIS retomber sur nil
    # dans ce cas : des données personnelles seraient déclassées en liste publique.
    def dlnuf_config(domain_id)
      config = config(domain_id)
      return nil unless config

      owner_field_id = config['Champ propriétaire']
      return nil if owner_field_id.blank?

      field = fields(config)&.dig(owner_field_id.to_i)
      return :invalid if field.nil?

      unless field[:type].in?(EMAIL_LIKE_TYPES)
        Rails.logger.warn("ReferentielDePolynesie: le champ propriétaire #{owner_field_id} (référentiel #{domain_id}) est de type #{field[:type]}, pas un e-mail")
      end

      { field_id: owner_field_id.to_i, field_name: field[:name], field_type: field[:type] }
    end
```

Note : `EMAIL_LIKE_TYPES` doit être défini au niveau de la classe (hors du bloc `class << self`), juste après `TIMEOUT`.

- [ ] **Step 4 : Vérifier que les tests passent**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`
Expected: PASS (nouveaux tests + tous les tests existants du fichier)

- [ ] **Step 5 : Commit**

```bash
git add app/lib/referentiel_de_polynesie/baserow_api.rb spec/lib/referentiel_de_polynesie/baserow_api_spec.rb
git commit -m "feat(dlnuf): lecture du champ propriétaire dans la table méta Baserow (fail-closed si id mort)"
```

---

### Task 2 : `BaserowAPI.search_with_data` — filtre de scope, `q` vide autorisé

**Files:**
- Modify: `app/lib/referentiel_de_polynesie/baserow_api.rb` (`search_with_data` ligne ~54, `build_search_filters` ligne ~177, suppression de `build_single_word_filter`/`build_multi_word_filters`)
- Test: `spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`

**Interfaces:**
- Produces: `search_with_data(domain_id, term, drop_down_other: false, scope: nil)` où `scope = { field_id: Integer, value: String }` → filtre Baserow `equal` toujours appliqué en `AND` ; `term` peut être `nil`/vide quand `scope` est présent. Sans scope et sans terme → `[]` (défense en profondeur : ne jamais renvoyer la table entière).

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans le `describe '.search_with_data'` existant de `spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`, ajouter :

```ruby
    context 'avec un scope DLNUF' do
      let(:scope) { { field_id: 9, value: 'titulaire@exemple.pf' } }

      def sent_filters
        sent = nil
        expect(Typhoeus).to have_received(:get)
          .with("#{base_url}/api/database/rows/table/#{table_id}/", anything) do |_url, options|
            sent = JSON.parse(options[:params]['filters'])
          end
        sent
      end

      it 'applique toujours le filtre propriétaire en AND avec le terme' do
        described_class.search_with_data(domain_id, term, scope:)
        filters = sent_filters
        expect(filters['filter_type']).to eq('AND')
        expect(filters['filters']).to include({ 'field' => 9, 'type' => 'equal', 'value' => 'titulaire@exemple.pf' })
        expect(filters['filters']).to include({ 'field' => search_field_id, 'type' => 'contains', 'value' => term })
      end

      it 'accepte un terme vide : seul le filtre propriétaire est envoyé' do
        described_class.search_with_data(domain_id, '', scope:)
        filters = sent_filters
        expect(filters['filters']).to eq([{ 'field' => 9, 'type' => 'equal', 'value' => 'titulaire@exemple.pf' }])
      end
    end

    context 'sans scope et sans terme' do
      it 'retourne [] sans appeler la table (ne jamais renvoyer la table entière)' do
        expect(described_class.search_with_data(domain_id, '')).to eq([])
        expect(Typhoeus).not_to have_received(:get)
          .with("#{base_url}/api/database/rows/table/#{table_id}/", anything)
      end
    end
```

Note : le `before` existant du `describe` stubbe déjà l'appel `rows/table/#{table_id}` avec `baserow_results` — vérifier qu'il utilise `allow(Typhoeus).to receive(:get)` (nécessaire pour `have_received`).

- [ ] **Step 2 : Vérifier que les tests échouent**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/baserow_api_spec.rb -e search_with_data`
Expected: FAIL (`unknown keyword: :scope`)

- [ ] **Step 3 : Implémenter**

Dans `search_with_data`, changer la signature et le calcul des params :

```ruby
    def search_with_data(domain_id, term, drop_down_other: false, scope: nil)
      config = config(domain_id)
      return [] unless config

      search_field_id = config['Champ de recherche']
      model = fields(config)

      params = build_search_filters(search_field_id, term, scope:)
      # pf: ni terme ni scope → ne jamais renvoyer la table entière (défense en profondeur)
      return [] if params.blank?

      url = rows_url(config['Table'])
      response = Typhoeus.get(url, headers: database_headers(config['Token']), params:, timeout: TIMEOUT)
      # ... (suite inchangée)
```

Remplacer `build_search_filters` + `build_single_word_filter` + `build_multi_word_filters` par :

```ruby
    def build_search_filters(search_field, term, scope: nil)
      filters = extract_search_words(term).map do |word|
        { "field" => search_field.to_i, "type" => "contains", "value" => word }
      end
      # pf: DLNUF — le filtre propriétaire est TOUJOURS appliqué quand un scope est présent ;
      # q ne fait que réduire à l'intérieur du périmètre (la sécurité tient quel que soit q)
      if scope.present?
        filters << { "field" => scope[:field_id], "type" => "equal", "value" => scope[:value] }
      end
      return {} if filters.empty?

      { "filters" => JSON.generate({ "filter_type" => "AND", "filters" => filters }) }
    end
```

Attention : `search` (méthode legacy ligne ~7) appelle aussi `build_search_filters(search_field, term)` — la nouvelle signature est rétro-compatible (`scope:` optionnel), ne pas la modifier.

- [ ] **Step 4 : Vérifier que les tests passent**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/baserow_api_spec.rb`
Expected: PASS (y compris les tests existants de recherche multi-mots)

- [ ] **Step 5 : Commit**

```bash
git add app/lib/referentiel_de_polynesie/baserow_api.rb spec/lib/referentiel_de_polynesie/baserow_api_spec.rb
git commit -m "feat(dlnuf): filtre de scope propriétaire dans la recherche Baserow, q vide autorisé si scopé"
```

---

### Task 3 : `ReferentielDePolynesie::API` — délégation + cache court

**Files:**
- Modify: `app/lib/referentiel_de_polynesie/api.rb`
- Test: `spec/lib/referentiel_de_polynesie/api_spec.rb` (nouveau fichier)

**Interfaces:**
- Consumes: `BaserowAPI.dlnuf_config` (Task 1), `BaserowAPI.search_with_data(scope:)` (Task 2)
- Produces: `ReferentielDePolynesie::API.dlnuf_config(domain_id)` (mêmes retours que Task 1, mis en cache 5 minutes — le devis §7 tolère une « fenêtre courte de scope obsolète ») ; `API.search_with_data(domain_id, term, drop_down_other:, scope:)` (pass-through). Consommé par le controller (Task 4), la validation champ (Task 5), le rempart exact_match (Task 6) et le composant (Task 8).

- [ ] **Step 1 : Écrire les tests qui échouent**

Créer `spec/lib/referentiel_de_polynesie/api_spec.rb` :

```ruby
# frozen_string_literal: true

require 'rails_helper'

describe ReferentielDePolynesie::API do
  before do
    ENV['API_BASEROW_URL'] = 'https://baserow.example.com'
    described_class.instance_variable_set(:@engine, nil)
  end

  after do
    ENV.delete('API_BASEROW_URL')
    described_class.instance_variable_set(:@engine, nil)
  end

  describe '.dlnuf_config' do
    let(:config) { { field_id: 9, field_name: 'Email', field_type: 'email' } }

    it 'délègue au moteur et met le résultat en cache' do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:dlnuf_config).with('24').and_return(config)
      expect(described_class.dlnuf_config('24')).to eq(config)
    end

    it 'met aussi en cache le mode catalogue (nil) via un sentinel', caching: true do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:dlnuf_config).with('24').and_return(nil)
      2.times { expect(described_class.dlnuf_config('24')).to be_nil }
      expect(ReferentielDePolynesie::BaserowAPI).to have_received(:dlnuf_config).once
    end

    it 'retourne nil sans moteur configuré' do
      ENV.delete('API_BASEROW_URL')
      described_class.instance_variable_set(:@engine, nil)
      expect(described_class.dlnuf_config('24')).to be_nil
    end

    it 'retourne nil pour un domain_id invalide' do
      expect(described_class.dlnuf_config('abc')).to be_nil
    end
  end

  describe '.search_with_data' do
    it 'transmet le scope au moteur' do
      scope = { field_id: 9, value: 'a@b.pf' }
      expect(ReferentielDePolynesie::BaserowAPI).to receive(:search_with_data)
        .with('24', 'q', drop_down_other: false, scope:)
        .and_return([])
      described_class.search_with_data('24', 'q', drop_down_other: false, scope:)
    end
  end
end
```

Note : si le tag `caching: true` n'existe pas dans ce projet (`grep -rn "caching: true" spec/` pour vérifier), remplacer ce test par un stub explicite de `Rails.cache` avec `ActiveSupport::Cache::MemoryStore.new` via `allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)`.

- [ ] **Step 2 : Vérifier que les tests échouent**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/api_spec.rb`
Expected: FAIL avec `undefined method 'dlnuf_config'`

- [ ] **Step 3 : Implémenter**

Dans `app/lib/referentiel_de_polynesie/api.rb` :

```ruby
    # pf: DLNUF — config « champ propriétaire » avec cache court. TTL 5 min : compromis entre
    # charge Baserow (1 appel config + 1 appel fields par table) et fenêtre de scope obsolète
    # après un changement de la colonne « Champ propriétaire » (toléré, cf. devis §7).
    DLNUF_CONFIG_TTL = 5.minutes

    def dlnuf_config(domain_id)
      return nil if domain_id.to_i <= 0 || engine.nil?

      cached = Rails.cache.fetch("referentiel_de_polynesie/dlnuf_config/#{domain_id}", expires_in: DLNUF_CONFIG_TTL) do
        engine.dlnuf_config(domain_id) || :none # pf: sentinel — Rails.cache ne mémorise pas nil
      end
      cached == :none ? nil : cached
    end
```

Et modifier `search_with_data` :

```ruby
    def search_with_data(domain_id, term, drop_down_other: false, scope: nil)
      return [] if domain_id.to_i <= 0
      engine&.search_with_data(domain_id, term, drop_down_other:, scope:) || []
    end
```

- [ ] **Step 4 : Vérifier que les tests passent**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/api_spec.rb`
Expected: PASS

- [ ] **Step 5 : Commit**

```bash
git add app/lib/referentiel_de_polynesie/api.rb spec/lib/referentiel_de_polynesie/api_spec.rb
git commit -m "feat(dlnuf): API.dlnuf_config avec cache court + pass-through du scope"
```

---

### Task 4 : Controller `#search` — `dossier_id`, autorisation 403, mode DLNUF, fail-closed

**Files:**
- Modify: `app/controllers/data_sources/referentiel_de_polynesie_controller.rb`
- Test: `spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`

**Interfaces:**
- Consumes: `API.dlnuf_config`, `API.search_with_data(scope:)` (Task 3), `DossierPolicy::Scope` (existant — couvre propriétaire + invités), `message_encryptor_service` (ApplicationController:145).
- Produces: `GET data_sources/referentiel_de_polynesie/:table/search?q=&dossier_id=&drop_down_other=` —
  - table catalogue : comportement actuel inchangé (`q` requis → 400 sinon) ;
  - table DLNUF : `q` optionnel, `dossier_id` requis et contrôlé (403 sinon), scope = mail titulaire ;
  - config DLNUF invalide : 422 `{ message: 'Configuration du référentiel invalide' }` + Sentry.

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`, ajouter au `describe 'GET #search'` (le `before { sign_in(user) }` global existe déjà). Ajouter d'abord en tête du describe un stub par défaut « catalogue » pour que les tests existants restent verts :

```ruby
    before do
      allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).and_return(nil)
    end
```

Puis les nouveaux contextes :

```ruby
    context 'sur une table « Dites-le-nous une fois »' do
      let(:dlnuf) { { field_id: 9, field_name: 'Email', field_type: 'email' } }
      let(:dossier) { create(:dossier, user:) }

      before do
        allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with(domain_id).and_return(dlnuf)
      end

      it 'accepte q vide et scope la recherche sur le mail du titulaire' do
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, nil, drop_down_other: nil, scope: { field_id: 9, value: user.email.downcase })
          .and_return([{ label: 'Ma ligne', value: '24:1', row_data: }])

        get :search, params: { table: domain_id, dossier_id: dossier.id }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.first['label']).to eq('Ma ligne')
      end

      it 'scope sur le mail du TITULAIRE quand un invité cherche' do
        invite_user = create(:user)
        create(:invite, dossier:, user: invite_user, email: invite_user.email)
        sign_in(invite_user)

        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, nil, drop_down_other: nil, scope: { field_id: 9, value: user.email.downcase })
          .and_return([])

        get :search, params: { table: domain_id, dossier_id: dossier.id }
        expect(response).to have_http_status(:ok)
      end

      it 'refuse (403) le dossier d\'un autre usager' do
        autre_dossier = create(:dossier)
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, dossier_id: autre_dossier.id, q: 'x' }
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuse (403) sans dossier_id — jamais de repli en catalogue ouvert' do
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, q: 'x' }
        expect(response).to have_http_status(:forbidden)
      end

      it 'q libre ne désactive jamais le scope' do
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, 'injection', drop_down_other: nil, scope: { field_id: 9, value: user.email.downcase })
          .and_return([])

        get :search, params: { table: domain_id, dossier_id: dossier.id, q: 'injection' }
        expect(response).to have_http_status(:ok)
      end

      it 'retourne [] si le dossier n\'a pas de titulaire avec mail (fail-closed silencieux)' do
        allow_any_instance_of(Dossier).to receive(:user).and_return(nil)
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, dossier_id: dossier.id }
        expect(response.parsed_body).to eq([])
      end
    end

    context 'quand la config DLNUF est invalide (champ propriétaire mort)' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with(domain_id).and_return(:invalid)
      end

      it 'refuse d\'exposer (422) et alerte Sentry, sans appeler la recherche' do
        expect(Sentry).to receive(:capture_message).with(/champ propriétaire invalide/, anything)
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, q: term }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eq('Configuration du référentiel invalide')
      end
    end
```

Vérifier que la factory `:invite` existe (`spec/factories/invite.rb`) ; sinon créer l'invite avec `Invite.create!(dossier:, user: invite_user, email: invite_user.email)`.

- [ ] **Step 2 : Vérifier que les tests échouent**

Run: `bundle exec rspec spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`
Expected: FAIL sur les nouveaux contextes (les anciens restent verts grâce au stub `dlnuf_config → nil`)

- [ ] **Step 3 : Implémenter le controller**

Remplacer intégralement `app/controllers/data_sources/referentiel_de_polynesie_controller.rb` :

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
      render json: { message: 'Configuration du référentiel invalide' }, status: :unprocessable_entity
    elsif dlnuf.present?
      dossier = authorized_dossier
      return if performed?

      # pf: DLNUF — scope = mail du TITULAIRE (dossier.user), pas l'utilisateur connecté :
      # un invité doit préremplir avec les données du titulaire. Jamais lu depuis le client.
      email = dossier.user&.email&.downcase
      if email.blank?
        render json: [] # pf: fail-closed silencieux (dossier orphelin prefillé, etc.)
      else
        results = ReferentielDePolynesie::API.search_with_data(
          table, @params[:q], drop_down_other:, scope: { field_id: dlnuf[:field_id], value: email }
        )
        render json: encrypted_results(results)
      end
    elsif table.blank? || @params[:q].blank?
      render json: { message: "table & q parameters are required" }, status: :bad_request
    else
      results = ReferentielDePolynesie::API.search_with_data(table, @params[:q], drop_down_other:)
      render json: encrypted_results(results)
    end
  end

  private

  # pf: autorisation DLNUF — le dossier doit être accessible à current_user (propriétaire ou
  # invité, via DossierPolicy::Scope). 403 sinon, y compris quand dossier_id est absent.
  def authorized_dossier
    dossier = policy_scope(Dossier).find_by(id: @params[:dossier_id])
    render json: { message: 'Accès refusé' }, status: :forbidden if dossier.nil?
    dossier
  end

  def encrypted_results(results)
    results.map do |r|
      data = r[:row_data].present? ? message_encryptor_service.encrypt_and_sign(r[:row_data].to_json, purpose: :storage, expires_in: 1.hour) : ""
      r.slice(:label, :value).merge(data:)
    end
  end

  def search_params = params.permit(:table, :q, :drop_down_other, :dossier_id)
end
```

- [ ] **Step 4 : Vérifier que les tests passent**

Run: `bundle exec rspec spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb`
Expected: PASS (nouveaux + anciens)

- [ ] **Step 5 : Commit**

```bash
git add app/controllers/data_sources/referentiel_de_polynesie_controller.rb spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb
git commit -m "feat(dlnuf): endpoint search scopé sur le mail du titulaire (403, fail-closed, q vide)"
```

---

### Task 5 : Validation locale au dépôt (second rempart)

**Files:**
- Modify: `app/models/champs/referentiel_de_polynesie_champ.rb`
- Modify: `config/locales/models/champs/champs.fr.yml` et `config/locales/models/champs/champs.en.yml`
- Test: `spec/models/champs/referentiel_de_polynesie_champ_spec.rb`

**Interfaces:**
- Consumes: `API.dlnuf_config` (Task 3), `normalized_data` (existant, referentiel_de_polynesie_champ.rb:137), `validate_champ_value?` (ChampValidateConcern), `table_id` (délégué au type de champ).
- Produces: validation `dlnuf_owner_integrity` sur contexte `:champs_public_value` / `:champs_private_value` — erreur `:not_dlnuf_owner` sur `:value` si la ligne sélectionnée n'appartient pas au titulaire.

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `spec/models/champs/referentiel_de_polynesie_champ_spec.rb`, ajouter (idiome de `spec/models/champs/drop_down_list_champ_spec.rb:15` : `champ.validate(:champs_public_value)`) :

```ruby
  describe 'validation DLNUF au dépôt (second rempart)' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :referentiel_de_polynesie, libelle: 'Mes informations', table_id: '24' }]) }
    let(:dossier) { create(:dossier, procedure:) }
    let(:champ) { dossier.champs.first }
    let(:dlnuf) { { field_id: 9, field_name: 'Email', field_type: 'email' } }
    let(:row_email) { dossier.user.email }

    subject { champ.validate(:champs_public_value) }

    before do
      allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with('24').and_return(dlnuf)
      champ.update_columns(external_id: '24:1', value: 'Ma ligne', data: { 'Email' => row_email })
      champ.reload
    end

    context 'quand la ligne appartient au titulaire' do
      it { is_expected.to be_truthy }
    end

    context 'quand le mail diffère par la casse' do
      let(:row_email) { dossier.user.email.upcase }

      it { is_expected.to be_truthy }
    end

    context 'quand la ligne appartient à quelqu\'un d\'autre' do
      let(:row_email) { 'autre@exemple.pf' }

      it 'ajoute une erreur bloquante sur ce champ précis' do
        expect(subject).to be_falsey
        expect(champ.errors[:value].join).to match(/ne correspond plus aux données enregistrées/)
      end
    end

    context 'quand row_data ne contient pas la colonne propriétaire' do
      before do
        champ.update_columns(data: { 'Nom' => 'Ma ligne' })
        champ.reload
      end

      it 'invalide (fail-closed : DLNUF est une feature neuve, pas de données legacy)' do
        expect(subject).to be_falsey
      end
    end

    context 'quand la table est un catalogue (pas de config DLNUF)' do
      let(:dlnuf) { nil }
      let(:row_email) { 'autre@exemple.pf' }

      it { is_expected.to be_truthy }
    end

    context 'quand la config DLNUF est indisponible ou invalide' do
      let(:dlnuf) { :invalid }
      let(:row_email) { 'autre@exemple.pf' }

      it 'ne bloque pas le dépôt (le rempart n°1 reste la protection principale)' do
        expect(subject).to be_truthy
      end
    end

    context 'quand le champ est vide' do
      before do
        champ.update_columns(external_id: nil, value: nil, data: nil)
        champ.reload
      end

      it { is_expected.to be_truthy }
    end
  end
```

- [ ] **Step 2 : Vérifier que les tests échouent**

Run: `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb -e "validation DLNUF"`
Expected: FAIL sur « appartient à quelqu'un d'autre » et « colonne propriétaire absente » (pas d'erreur ajoutée)

- [ ] **Step 3 : Implémenter la validation**

Dans `app/models/champs/referentiel_de_polynesie_champ.rb`, ajouter après la ligne 9 (`def referentiel?` … `end`) la déclaration, et la méthode dans la section `private` existante (ligne ~154) :

```ruby
  # pf: DLNUF, second rempart (dépôt) — la ligne sélectionnée doit appartenir au titulaire.
  # Couvre le transfert de dossier après sélection et toute soumission forgée.
  validate :dlnuf_owner_integrity, if: -> { validate_champ_value? && external_id.present? && !other? }
```

```ruby
  # pf: comparaison LOCALE sur row_data (aucune lecture de ligne Baserow au dépôt).
  # La config méta passe par le cache court de API.dlnuf_config ; si elle est indisponible
  # (:invalid ou Baserow down → nil), on ne bloque pas le dépôt : le rempart n°1 (filtre
  # serveur à la sélection) reste la protection principale.
  def dlnuf_owner_integrity
    config = ReferentielDePolynesie::API.dlnuf_config(table_id)
    return if config.blank? || config == :invalid

    owner_email = dossier.user&.email
    return if owner_email.blank?

    row_email = normalized_data&.dig(config[:field_name])
    unless row_email.to_s.casecmp?(owner_email)
      errors.add(:value, :not_dlnuf_owner)
    end
  end
```

- [ ] **Step 4 : Ajouter les clés i18n**

Dans `config/locales/models/champs/champs.fr.yml`, sous `fr.activerecord.errors.models`, ajouter (respecter l'indentation existante du fichier, clé modèle STI entre guillemets) :

```yaml
        "champs/referentiel_de_polynesie_champ":
          attributes:
            value:
              not_dlnuf_owner: "ne correspond plus aux données enregistrées à votre nom. Sélectionnez à nouveau une valeur."
```

Dans `config/locales/models/champs/champs.en.yml` :

```yaml
        "champs/referentiel_de_polynesie_champ":
          attributes:
            value:
              not_dlnuf_owner: "no longer matches the data registered under your name. Please select a value again."
```

- [ ] **Step 5 : Vérifier que les tests passent**

Run: `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb`
Expected: PASS

- [ ] **Step 6 : Commit**

```bash
git add app/models/champs/referentiel_de_polynesie_champ.rb config/locales/models/champs/ spec/models/champs/referentiel_de_polynesie_champ_spec.rb
git commit -m "feat(dlnuf): validation locale au dépôt — la ligne doit appartenir au titulaire"
```

---

### Task 6 : Rempart exact_match — `fetch_external_data` vérifie le propriétaire

Le mode `exact_match` (saisie libre + job asynchrone) rapatrie une ligne à partir d'un `external_id` contrôlé par l'usager : sans garde, un usager pourrait exfiltrer la ligne d'autrui d'une table DLNUF (les colonnes displayables lui seraient affichées). On refuse le fetch d'une ligne dont le champ propriétaire ne correspond pas au titulaire.

**Files:**
- Modify: `app/models/champs/referentiel_de_polynesie_champ.rb` (`fetch_external_data`, ligne ~72)
- Test: `spec/models/champs/referentiel_de_polynesie_champ_spec.rb`

**Interfaces:**
- Consumes: `API.dlnuf_config` (Task 3), `fetch_external_data_legacy` (existant), `Dry::Monads` Success/Failure (déjà utilisés dans ce fichier).
- Produces: `fetch_external_data` renvoie `Dry::Monads::Failure(retryable: false, reason:, code: 403)` si la ligne rapatriée n'appartient pas au titulaire ou si la config DLNUF est `:invalid`.

- [ ] **Step 1 : Écrire les tests qui échouent**

```ruby
  describe '#fetch_external_data — rempart DLNUF en mode exact_match' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :referentiel_de_polynesie, libelle: 'Mes informations', table_id: '24' }]) }
    let(:dossier) { create(:dossier, procedure:) }
    let(:champ) { dossier.champs.first }
    let(:dlnuf) { { field_id: 9, field_name: 'Email', field_type: 'email' } }
    let(:row) { { 'Nom' => 'Ma ligne', 'Email' => row_email }.with_indifferent_access }

    subject { champ.fetch_external_data }

    before do
      allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with('24').and_return(dlnuf)
      allow(ReferentielDePolynesie::API).to receive(:fetch_row).and_return(row)
      champ.update_columns(external_id: '24:1')
      champ.reload
    end

    context 'quand la ligne appartient au titulaire' do
      let(:row_email) { dossier.user.email }

      it { is_expected.to be_success }
    end

    context 'quand la ligne appartient à quelqu\'un d\'autre (tentative d\'exfiltration)' do
      let(:row_email) { 'autre@exemple.pf' }

      it 'refuse le rapatriement' do
        expect(subject).to be_failure
        expect(subject.failure[:code]).to eq(403)
      end
    end

    context 'quand la config DLNUF est invalide (champ propriétaire mort)' do
      let(:dlnuf) { :invalid }
      let(:row_email) { 'autre@exemple.pf' }

      it 'refuse le rapatriement (fail-closed : exposition de données)' do
        expect(subject).to be_failure
      end
    end

    context 'sur une table catalogue' do
      let(:dlnuf) { nil }
      let(:row_email) { 'autre@exemple.pf' }

      it { is_expected.to be_success }
    end
  end
```

- [ ] **Step 2 : Vérifier que les tests échouent**

Run: `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb -e "rempart DLNUF"`
Expected: FAIL (« exfiltration » et « config invalide » renvoient Success)

- [ ] **Step 3 : Implémenter**

Remplacer la méthode `fetch_external_data` (ligne ~72) et ajouter la garde en `private` :

```ruby
  # pf: fallback legacy si pas encore de referentiel lié
  def fetch_external_data
    result = referentiel.present? ? super : fetch_external_data_legacy
    enforce_dlnuf_ownership(result)
  end
```

```ruby
  # pf: DLNUF — en mode exact_match, external_id est contrôlé par l'usager : refuser de
  # rapatrier (et donc d'afficher) une ligne qui n'appartient pas au titulaire (exfiltration).
  # Fail-closed si la config est :invalid (table marquée DLNUF mais champ propriétaire mort).
  def enforce_dlnuf_ownership(result)
    config = ReferentielDePolynesie::API.dlnuf_config(table_id)
    return result if config.blank?
    return result unless result.respond_to?(:success?) && result.success?

    owner_email = dossier.user&.email
    if config != :invalid && owner_email.present? && result.value![config[:field_name]].to_s.casecmp?(owner_email)
      result
    else
      Dry::Monads::Failure(retryable: false, reason: StandardError.new('DLNUF: ligne non détenue par le titulaire'), code: 403)
    end
  end
```

- [ ] **Step 4 : Vérifier que les tests passent**

Run: `bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb`
Expected: PASS (dont les tests existants de `fetch_external_data` legacy — la garde est transparente pour les tables catalogue car `dlnuf_config` y renvoie nil ; si des tests existants ne stubbent pas `dlnuf_config`, vérifier qu'ils passent quand même : sans `API_BASEROW_URL` le moteur est nil → nil → transparent)

- [ ] **Step 5 : Commit**

```bash
git add app/models/champs/referentiel_de_polynesie_champ.rb spec/models/champs/referentiel_de_polynesie_champ_spec.rb
git commit -m "feat(dlnuf): rempart exact_match — refuse le fetch d'une ligne d'autrui"
```

---

### Task 7 : Frontend — chargement à vide, auto-remplissage, message « aucune donnée »

**Files:**
- Modify: `app/javascript/components/react-aria/hooks.ts` (`createLoader`, ligne ~547)
- Modify: `app/javascript/components/react-aria/props.ts` (`RemoteComboBoxProps`, ligne ~67)
- Modify: `app/javascript/components/ComboBox.tsx` (fonctions `ComboBox` ligne ~37 et `RemoteComboBox` ligne ~294)
- Test: vérification TypeScript + le test système de la Task 9 (pas de suite de tests JS unitaires dédiée dans ce projet pour ces composants)

**Interfaces:**
- Consumes: `useRemoteList` (hooks.ts:358 — expose `items`, `isLoading`, `inputValue`, `onSelectionChange`, `selectedItem`).
- Produces: props React `autoSelectSingle: boolean` et `emptyLabel: string` sur `RemoteComboBox` (consommées par la Task 8) ; `minimumInputLength: 0` déclenche un chargement avec `q` vide.

- [ ] **Step 1 : `createLoader` — autoriser le texte vide quand `minimumInputLength` vaut 0**

Dans `app/javascript/components/react-aria/hooks.ts`, remplacer (ligne ~547) :

```ts
    if (!filterText || filterText.length < minimumInputLength) {
      return { items: [] };
    }
```

par :

```ts
    // pf: DLNUF — minimumInputLength: 0 autorise un chargement avec un texte vide
    // (liste « mes données » au montage / au focus, le scope étant résolu côté serveur)
    if (
      minimumInputLength > 0 &&
      (!filterText || filterText.length < minimumInputLength)
    ) {
      return { items: [] };
    }
```

Note : plus bas dans la même fonction, `url.searchParams.set(param, filterText)` — avec `filterText` potentiellement `undefined`, écrire `url.searchParams.set(param, filterText ?? '')` pour éviter `q=undefined`.

- [ ] **Step 2 : `props.ts` — nouvelles props**

Dans `RemoteComboBoxProps` (ligne ~67), ajouter dans le `s.partial(s.object({ … }))` :

```ts
      // pf: DLNUF — auto-sélection quand le périmètre de l'usager ne contient qu'une ligne
      autoSelectSingle: s.boolean(),
      // pf: DLNUF — message affiché sous le champ quand le périmètre est vide
      emptyLabel: s.string()
```

- [ ] **Step 3 : `ComboBox.tsx` — popover conditionné au focus**

Aujourd'hui `isOpen={shouldShowPopover}` force l'ouverture dès que la liste contient des résultats. Avec un chargement au montage (min 0), le menu s'ouvrirait tout seul à l'affichage de la page. On conditionne l'ouverture forcée au focus de l'input — no-op pour les usages existants (le popover n'était visible qu'en cours de frappe, donc focus). Dans la fonction `ComboBox` (ligne ~37) :

```tsx
  // pf: DLNUF — ne forcer l'ouverture du menu que quand l'input a le focus
  // (le chargement au montage avec minimumInputLength: 0 ouvrait le menu sans interaction)
  const [isFocused, setIsFocused] = useState(false);
```

Sur le composant `<Input …>` (ligne ~81), ajouter :

```tsx
          onFocus={() => setIsFocused(true)}
          onBlur={() => setIsFocused(false)}
```

Et sur `<Popover … isOpen={isOpen}>` (ligne ~103) :

```tsx
      <Popover
        className="fr-ds-combobox__menu fr-menu"
        isOpen={isOpen === undefined ? undefined : isOpen && isFocused}
      >
```

Ajouter `useState` à l'import React ligne 17.

- [ ] **Step 4 : `RemoteComboBox` — auto-sélection et message vide**

Dans `RemoteComboBox` (ligne ~294) : destructurer les nouvelles props (`autoSelectSingle`, `emptyLabel` sortent du `useMemo(() => s.create(...))` comme les autres), puis après l'appel à `useRemoteList` :

```tsx
  // pf: DLNUF — auto-remplir quand le périmètre de l'usager ne contient qu'une seule ligne.
  // Une seule fois par montage, uniquement si le champ est vide (pas de valeur existante).
  const autoSelectedRef = useRef(false);
  useEffect(() => {
    if (
      autoSelectSingle &&
      !autoSelectedRef.current &&
      !selectedItem &&
      comboBoxProps.inputValue == '' &&
      comboBoxProps.items.length == 1
    ) {
      autoSelectedRef.current = true;
      comboBoxProps.onSelectionChange(comboBoxProps.items[0].value);
    }
  }, [autoSelectSingle, selectedItem, comboBoxProps]);
```

Et après le `<ComboBox …>…</ComboBox>` dans le JSX retourné, avant le bloc `{children || name … }` :

```tsx
      {emptyLabel &&
      !error &&
      !selectedItem &&
      !comboBoxProps.isLoading &&
      comboBoxProps.items.length == 0 &&
      comboBoxProps.inputValue == '' ? (
        <p className="fr-hint-text fr-mt-1v">{emptyLabel}</p>
      ) : null}
```

Ajouter `useEffect` aux imports React de `ComboBox.tsx` (ligne 17 — `useRef` y est déjà).

- [ ] **Step 5 : Vérifier la compilation TypeScript et le lint**

Run: `bun run lint:types && bun run lint:js`
Expected: 0 erreur TypeScript, 0 erreur ESLint

- [ ] **Step 6 : Non-régression sur l'autocomplete catalogue existant**

Run: `NO_HEADLESS= bundle exec rspec spec/system/users/brouillon_spec.rb -e "fill referentiel_de_polynesie field"`
Expected: PASS (le scénario existant valide que le focus-gating du popover ne casse pas la sélection à la souris)

- [ ] **Step 7 : Commit**

```bash
git add app/javascript/components/react-aria/hooks.ts app/javascript/components/react-aria/props.ts app/javascript/components/ComboBox.tsx
git commit -m "feat(dlnuf): RemoteComboBox — chargement à vide, auto-sélection ligne unique, message périmètre vide"
```

---

### Task 8 : Composant Ruby — props DLNUF et messages

**Files:**
- Modify: `app/components/editable_champ/referentiel_de_polynesie_component.rb`
- Modify: `config/locales/fr.yml` et `config/locales/en.yml` (sous `shared.champs.referentiel_de_polynesie`, à créer à côté de `shared.champs.drop_down_list`)
- Test: couvert par le test système (Task 9) — pas de spec de composant dédiée dans ce projet pour ce composant

**Interfaces:**
- Consumes: `API.dlnuf_config` (Task 3), props front `autoSelectSingle` / `emptyLabel` / `minimumInputLength` (Task 7), route `data_sources_rdp_search_path` (routes.rb:281 — `dossier_id` passe en query param, pas de changement de route).
- Produces: le loader du champ contient `dossier_id` ; en mode DLNUF, `minimumInputLength: 0`, `autoSelectSingle: true`, `emptyLabel` traduit.

- [ ] **Step 1 : Implémenter le composant**

Remplacer `react_props` dans `app/components/editable_champ/referentiel_de_polynesie_component.rb` :

```ruby
  def react_props
    table = @champ.table_id
    # pf: dossier_id — permet au serveur de résoudre le scope DLNUF (mail du titulaire)
    # sans jamais le lire depuis le client ; ignoré pour les tables catalogue
    props = react_input_opts(id: @champ.focusable_input_id,
      class: 'fr-mt-1w',
      name: @form.field_name(:external_id),
      selectedKey: @champ.selected,
      items: @champ.selected_items,
      loader: data_sources_rdp_search_path(table:, drop_down_other: @champ.drop_down_other?, dossier_id: @champ.dossier_id),
      limit: 20,
      minimumInputLength: dlnuf? ? 0 : 2,
      data: { table_id: @champ.table_id })

    if dlnuf?
      # pf: DLNUF — « mes données » n'est pas une recherche : lister au focus, auto-remplir
      # si une seule ligne, et ne JAMAIS échoer le mail dans les messages
      props[:autoSelectSingle] = true
      props[:emptyLabel] = I18n.t('shared.champs.referentiel_de_polynesie.dlnuf_empty')
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
```

- [ ] **Step 2 : Ajouter les clés i18n**

Dans `config/locales/fr.yml`, localiser `shared: → champs: → drop_down_list:` et ajouter au même niveau que `drop_down_list` :

```yaml
      referentiel_de_polynesie:
        dlnuf_empty: "Aucune donnée enregistrée à votre nom"
```

Dans `config/locales/en.yml`, au même endroit :

```yaml
      referentiel_de_polynesie:
        dlnuf_empty: "No data registered under your name"
```

- [ ] **Step 3 : Vérifier que rien ne casse à froid**

Run: `bundle exec rspec spec/system/users/brouillon_spec.rb -e "fill referentiel_de_polynesie field"`
Expected: PASS (mode catalogue inchangé : sans `API_BASEROW_URL` en test, `dlnuf_config` → nil → `minimumInputLength: 2`)

- [ ] **Step 4 : Commit**

```bash
git add app/components/editable_champ/referentiel_de_polynesie_component.rb config/locales/fr.yml config/locales/en.yml
git commit -m "feat(dlnuf): props du composant — dossier_id, liste au focus, auto-remplissage"
```

---

### Task 9 : Spec système DLNUF (chaîne complète)

**Files:**
- Create: `spec/system/users/referentiel_dlnuf_spec.rb`

**Interfaces:**
- Consumes: toute la chaîne des tasks 1-8 ; helpers copiés de `spec/system/users/brouillon_spec.rb:778-817` (`log_in`, `fill_individual`, `champ_value_for` — méthodes privées de ce fichier, non partagées) ; `wait_for_autosave` (spec/support/system_helpers.rb:175).

- [ ] **Step 1 : Écrire la spec système**

Créer `spec/system/users/referentiel_dlnuf_spec.rb` :

```ruby
# frozen_string_literal: true

require 'system/users/dossier_shared_examples' if File.exist?(Rails.root.join('spec/system/users/dossier_shared_examples.rb'))

describe 'Référentiel de Polynésie — Dites-le-nous une fois', js: true do
  let(:password) { SECURE_PASSWORD }
  let(:user) { create(:user, password:) }
  let(:user_dossier) { user.dossiers.first }
  let(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :referentiel_de_polynesie, libelle: 'Mes informations', mandatory: false, table_id: '24' },
    ])
  end
  let(:dlnuf) { { field_id: 9, field_name: 'Email', field_type: 'email' } }
  let(:scope) { { field_id: 9, value: user.email.downcase } }

  before do
    allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with('24').and_return(dlnuf)
  end

  scenario 'auto-remplissage quand le titulaire a exactement une ligne' do
    allow(ReferentielDePolynesie::API).to receive(:search_with_data)
      .with('24', anything, drop_down_other: anything, scope:)
      .and_return([{ label: 'Association Manuia', value: '24:7', row_data: { 'Nom' => 'Association Manuia', 'Email' => user.email } }])

    log_in(user, procedure)
    fill_individual

    wait_for_autosave
    wait_until { champ_value_for('Mes informations') == 'Association Manuia' }
  end

  scenario 'aucune ligne : message sans écho du mail' do
    allow(ReferentielDePolynesie::API).to receive(:search_with_data)
      .with('24', anything, drop_down_other: anything, scope:)
      .and_return([])

    log_in(user, procedure)
    fill_individual

    expect(page).to have_text('Aucune donnée enregistrée à votre nom')
    expect(page).to have_no_text(user.email)
  end

  scenario 'plusieurs lignes : la liste apparaît au focus, sans saisie' do
    allow(ReferentielDePolynesie::API).to receive(:search_with_data)
      .with('24', anything, drop_down_other: anything, scope:)
      .and_return([
        { label: 'Association Manuia', value: '24:7', row_data: { 'Nom' => 'Association Manuia', 'Email' => user.email } },
        { label: 'Association Here', value: '24:8', row_data: { 'Nom' => 'Association Here', 'Email' => user.email } },
      ])

    log_in(user, procedure)
    fill_individual

    find('.dom-ready')
    find_field('Mes informations').click
    find('.fr-menu__item', text: 'Association Here').click
    wait_for_autosave
    wait_until { champ_value_for('Mes informations') == 'Association Here' }
  end

  private

  def log_in(user, procedure)
    login_as user, scope: :user
    visit "/commencer/#{procedure.path}"
    click_on 'Commencer la démarche'
    expect(page).to have_content("Votre identité")
    expect(page).to have_current_path(identite_dossier_path(user_dossier))
  end

  def fill_individual
    fill_in('Prénom', with: 'prenom', visible: true)
    fill_in('Nom', with: 'Nom', visible: true)
    within "#identite-form" do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))
  end

  def champ_value_for(libelle)
    champs = user_dossier.reload.project_champs_public
    champs.find { |c| c.libelle == libelle }&.reload&.value
  end
end
```

Note : supprimer la première ligne `require … dossier_shared_examples` si le fichier n'existe pas — c'est une précaution, les helpers sont copiés localement. Le premier scénario stubbe `anything` pour le terme car l'auto-chargement envoie `q` vide (`nil` côté controller).

- [ ] **Step 2 : Lancer la spec (toujours en headless — jamais de fenêtre visible)**

Run: `NO_HEADLESS= bundle exec rspec spec/system/users/referentiel_dlnuf_spec.rb`
Expected: PASS (3 scénarios)

Si le scénario 1 échoue sur l'auto-remplissage : vérifier dans la console navigateur (`page.driver.browser` logs) que le loader part bien avec `q=` vide et `dossier_id`, et que `autoSelectSingle` figure dans les props du react-fragment (inspecter le HTML rendu).

- [ ] **Step 3 : Commit**

```bash
git add spec/system/users/referentiel_dlnuf_spec.rb
git commit -m "test(dlnuf): specs système — auto-remplissage, périmètre vide, liste au focus"
```

---

### Task 10 : Validation finale

- [ ] **Step 1 : Lint**

Run: `bundle exec rubocop -a app/lib/referentiel_de_polynesie/ app/controllers/data_sources/referentiel_de_polynesie_controller.rb app/models/champs/referentiel_de_polynesie_champ.rb app/components/editable_champ/referentiel_de_polynesie_component.rb spec/lib/referentiel_de_polynesie/ spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb spec/models/champs/referentiel_de_polynesie_champ_spec.rb spec/system/users/referentiel_dlnuf_spec.rb`
Expected: 0 offense (après auto-correction)

- [ ] **Step 2 : Suite ciblée complète**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/ spec/controllers/data_sources/referentiel_de_polynesie_controller_spec.rb spec/models/champs/referentiel_de_polynesie_champ_spec.rb spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb && NO_HEADLESS= bundle exec rspec spec/system/users/referentiel_dlnuf_spec.rb spec/system/users/brouillon_spec.rb -e referentiel`
Expected: PASS partout

- [ ] **Step 3 : Commit final (corrections lint éventuelles)**

```bash
git add -A && git commit -m "chore(dlnuf): lint" || echo "rien à committer"
```

- [ ] **Step 4 : Rappel avant PR**

Le corps de la PR doit mentionner le **prérequis ops** : créer la colonne « Champ propriétaire » dans la table méta Baserow et y renseigner l'id du champ e-mail pour chaque référentiel DLNUF ; la synchro externe dossier → Baserow (mails normalisés en minuscules) conditionne le bon fonctionnement (devis §6-7). Ne pas merger sans validation manuelle de l'utilisateur (préférence projet).
