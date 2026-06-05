# Plan C — Configuration du mapping référentiel (Baserow/PF) via le MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre à Claude (via le MCP) de **lire** les colonnes Baserow d'un champ `referentiel_de_polynesie` + son mapping actuel, et de **configurer** ce mapping (pré-remplir un champ cible / rapatrier vers usager/instructeur), source Baserow supposée déjà posée (`table_id`).

**Architecture :** Backend mes-demarches = 1 query PF (`referentielChampConfig`) + 1 mutation PF (`demarcheConfigurerReferentielMapping`), réutilisant `ReferentielDePolynesie::API.engine.fields`, la constante `Referentiels::ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP` (couplage unique, pinné par un spec canari) et le pattern de persistance `referentiel_mapping = safe_referentiel_mapping.deep_merge(...)`. L'éligibilité des cibles (ordre + scope public/privé) est **réécrite en code PF isolé** via des primitifs `coordinate.*` stables. MCP = 2 outils typés.

**Tech Stack :** Rails 7 / graphql-ruby / RSpec (Baserow stubbé) ; TypeScript / zod / vitest.

**Réf. spec :** `docs/superpowers/specs/2026-06-03-mcp-referentiel-mapping-design.md` (validée).

**Pré-requis :** base `Mutations::DemarcheChampMutation` + `find_authorized_procedure` + `Types::OptionsBlob` + `app/graphql/resolvers/mcp/` (tous présents). Branche `feature/mcp-construction-formulaires` (mes-demarches) / `main` (mcp-mes-demarches).

---

## Structure du mapping (rappel, vérifié)

`type_de_champ.options[:referentiel_mapping]` = `{ "$.<Colonne>" => { type, libelle, prefill:"0/1", prefill_stable_id, display_usager:"0/1", display_instructeur:"0/1", example_value } }`.

- Colonnes dispo = `ReferentielDePolynesie::API.engine.fields(engine.config(table_id))` → `{ id => { name:, type: } }`. Type interne via `BaserowAPI.baserow_type_to_mapping_type(field_metadata)`. **On expose TOUTES les colonnes** (la config usager/instructeur Baserow est legacy/ignorée).
- Persistance (comme le controller) : `type_de_champ.update(referentiel_mapping: type_de_champ.safe_referentiel_mapping.deep_merge(nouvelles_entrees))`.
- Compat de type : `MAPPING_TYPE_TO_TYPE_DE_CHAMP[mapping_type.to_sym]` → liste de `type_champ` autorisés.

---

## File Structure

**mes-demarches :**
- Create: `app/graphql/types/mcp/referentiel_colonne_type.rb`, `app/graphql/types/mcp/referentiel_champ_config_type.rb`
- Create: `app/graphql/resolvers/mcp/referentiel_champ_config.rb`
- Create: `app/graphql/mutations/demarche_configurer_referentiel_mapping.rb`
- Create: `app/services/mcp/referentiel_mapping_service.rb` (logique éligibilité + build + prune, isolée, testable)
- Modify: `app/graphql/types/query_type.rb`, `app/graphql/types/mutation_type.rb`
- Create: `spec/services/mcp/referentiel_mapping_service_spec.rb`, `spec/graphql/queries/referentiel_champ_config_spec.rb`, `spec/graphql/mutations/demarche_configurer_referentiel_mapping_spec.rb`, `spec/components/referentiels/mapping_type_constant_canary_spec.rb`
- Modify (régénéré): `app/graphql/schema.graphql`, `app/graphql/schema.json`

**mcp-mes-demarches :**
- Modify: `src/tools.ts`, `src/tools.test.ts`, `schema.graphql`

---

## Task 1 : Service PF d'éligibilité + spec canari sur la constante

**But :** isoler la logique métier (colonnes Baserow, compat de type, éligibilité ordre+scope, build d'entrées, prune) dans un service testable, et pinner la constante upstream.

**Files:**
- Create: `app/services/mcp/referentiel_mapping_service.rb`
- Create: `spec/services/mcp/referentiel_mapping_service_spec.rb`
- Create: `spec/components/referentiels/mapping_type_constant_canary_spec.rb`

- [ ] **Step 1 : Spec canari sur la constante upstream**

Créer `spec/components/referentiels/mapping_type_constant_canary_spec.rb` :
```ruby
# frozen_string_literal: true

# pf: canari — le MCP (Mcp::ReferentielMappingService) réutilise cette constante publique
# pour valider la compatibilité de type des cibles de pré-remplissage. Si un bump upstream
# la renomme/déplace/modifie, ce test casse → on adapte le service (blast radius localisé).
RSpec.describe 'Canari MAPPING_TYPE_TO_TYPE_DE_CHAMP' do
  subject { Referentiels::ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP }

  it 'existe et expose les familles de types attendues' do
    expect(subject).to be_a(Hash)
    expect(subject.keys).to include(:string, :integer_number, :decimal_number, :boolean, :date)
    expect(subject[:integer_number]).to include('integer_number')
    expect(subject[:boolean]).to include('yes_no', 'checkbox')
    expect(subject[:string]).to include('text')
  end
end
```

- [ ] **Step 2 : Spec du service (écrire avant)**

Créer `spec/services/mcp/referentiel_mapping_service_spec.rb`. On stube Baserow au niveau `ReferentielDePolynesie::API.engine`. Procédure : un `referentiel_de_polynesie` (avec `table_id`) suivi de champs cibles.

```ruby
# frozen_string_literal: true

RSpec.describe Mcp::ReferentielMappingService do
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :referentiel_de_polynesie, libelle: 'Entreprise', table_id: '24' },
      { type: :text, libelle: 'Raison sociale cible' },
      { type: :integer_number, libelle: 'Effectif cible' },
    ])
  end
  let(:draft) { procedure.draft_revision }
  let(:referentiel_tdc) { draft.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' } }
  let(:cible_texte) { draft.types_de_champ.find { _1.libelle == 'Raison sociale cible' } }
  let(:cible_nombre) { draft.types_de_champ.find { _1.libelle == 'Effectif cible' } }

  # Baserow renvoie 2 colonnes
  let(:baserow_fields) { { 1 => { name: 'RaisonSociale', type: 'text' }, 2 => { name: 'Effectif', type: 'number', number_decimal_places: 0 } } }
  let(:engine) { instance_double(ReferentielDePolynesie::BaserowAPI) }

  before do
    allow(ReferentielDePolynesie::API).to receive(:engine).and_return(engine)
    allow(engine).to receive(:config).with('24').and_return({ 'Table' => '24', 'Token' => 't' })
    allow(engine).to receive(:fields).and_return(baserow_fields)
    allow(engine).to receive(:baserow_type_to_mapping_type) { |f| ReferentielDePolynesie::BaserowAPI.new.baserow_type_to_mapping_type(f) }
  end

  subject(:service) { described_class.new(referentiel_tdc) }

  describe '#colonnes' do
    it 'liste les colonnes Baserow avec leur type de mapping' do
      cols = service.colonnes
      expect(cols).to contain_exactly(
        { nom: 'RaisonSociale', type_mapping: 'string' },
        { nom: 'Effectif', type_mapping: 'integer_number' }
      )
    end

    it 'lève si Baserow est injoignable' do
      allow(ReferentielDePolynesie::API).to receive(:engine).and_return(nil)
      expect { service.colonnes }.to raise_error(Mcp::ReferentielMappingService::BaserowIndisponible)
    end
  end

  describe '#configurer!' do
    it 'pose un prefill vers une cible compatible et située après' do
      service.configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: cible_texte.stable_id.to_s }])
      mapping = referentiel_tdc.reload.safe_referentiel_mapping
      expect(mapping['$.RaisonSociale']['prefill']).to eq('1')
      expect(mapping['$.RaisonSociale']['prefill_stable_id']).to eq(cible_texte.stable_id.to_s)
      expect(mapping['$.RaisonSociale']['type']).to eq('string')
    end

    it 'pose un rapatriement usager/instructeur' do
      service.configurer!([{ colonne: 'Effectif', display_usager: true, display_instructeur: true }])
      mapping = referentiel_tdc.reload.safe_referentiel_mapping
      expect(mapping['$.Effectif']).to include('display_usager' => '1', 'display_instructeur' => '1')
    end

    it 'refuse une colonne inconnue de Baserow' do
      expect { service.configurer!([{ colonne: 'Inexistante', display_usager: true }]) }
        .to raise_error(Mcp::ReferentielMappingService::ColonneInconnue, /Inexistante/)
    end

    it 'refuse un prefill vers une cible de type incompatible' do
      # RaisonSociale (string) -> cible_nombre (integer_number) : incompatible
      expect { service.configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: cible_nombre.stable_id.to_s }]) }
        .to raise_error(Mcp::ReferentielMappingService::CibleInvalide, /compatible/)
    end

    it 'refuse un prefill vers un champ situé AVANT le référentiel' do
      # créer une procédure où la cible précède le référentiel
      proc2 = create(:procedure, types_de_champ_public: [
        { type: :text, libelle: 'Avant' },
        { type: :referentiel_de_polynesie, libelle: 'Ref', table_id: '24' },
      ])
      ref = proc2.draft_revision.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' }
      avant = proc2.draft_revision.types_de_champ.find { _1.libelle == 'Avant' }
      expect { described_class.new(ref).configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: avant.stable_id.to_s }]) }
        .to raise_error(Mcp::ReferentielMappingService::CibleInvalide)
    end

    it 'nettoie les entrées dont la colonne a disparu de Baserow' do
      referentiel_tdc.update!(referentiel_mapping: { '$.ColonneDisparue' => { 'type' => 'string', 'display_usager' => '1' } })
      service.configurer!([{ colonne: 'RaisonSociale', display_usager: true }])
      mapping = referentiel_tdc.reload.safe_referentiel_mapping
      expect(mapping).not_to have_key('$.ColonneDisparue')
      expect(mapping).to have_key('$.RaisonSociale')
    end
  end
end
```

- [ ] **Step 3 : Lancer, vérifier l'échec** : `bundle exec rspec spec/services/mcp/referentiel_mapping_service_spec.rb` → FAIL (service absent).

- [ ] **Step 4 : Implémenter le service**

Créer `app/services/mcp/referentiel_mapping_service.rb` :
```ruby
# frozen_string_literal: true

# pf: logique de configuration du mapping d'un champ referentiel_de_polynesie pour le MCP.
# Colonnes via Baserow (source supposée posée), validation d'éligibilité des cibles de
# pré-remplissage (réutilise la constante MAPPING_TYPE_TO_TYPE_DE_CHAMP + primitifs de
# coordonnée stables), build des entrées et nettoyage des colonnes disparues.
module Mcp
  class ReferentielMappingService
    class BaserowIndisponible < StandardError; end
    class ColonneInconnue < StandardError; end
    class CibleInvalide < StandardError; end

    def initialize(type_de_champ)
      @tdc = type_de_champ
      @draft = type_de_champ.revisions.last
    end

    # [{ nom:, type_mapping: }]
    def colonnes
      baserow_fields.map { |_id, f| { nom: f[:name] || f['name'], type_mapping: mapping_type_for(f) } }
    end

    def mapping_actuel
      @tdc.safe_referentiel_mapping
    end

    # colonnes_config: [{ colonne:, prefill_stable_id?, display_usager?, display_instructeur?, libelle? }]
    def configurer!(colonnes_config)
      cols_by_name = baserow_fields.values.index_by { |f| f[:name] || f['name'] }

      nouvelles = colonnes_config.each_with_object({}) do |cfg, acc|
        nom = cfg[:colonne].to_s
        field = cols_by_name[nom]
        raise ColonneInconnue, "Colonne « #{nom} » absente du référentiel Baserow." if field.nil?

        type_mapping = mapping_type_for(field)
        entry = { 'type' => type_mapping, 'libelle' => (cfg[:libelle].presence || nom) }

        if cfg[:prefill_stable_id].present?
          valider_cible!(cfg[:prefill_stable_id].to_s, type_mapping)
          entry['prefill'] = '1'
          entry['prefill_stable_id'] = cfg[:prefill_stable_id].to_s
        else
          entry['prefill'] = '0'
          entry['display_usager'] = cfg[:display_usager] ? '1' : '0'
          entry['display_instructeur'] = cfg[:display_instructeur] ? '1' : '0'
        end

        acc["$.#{nom}"] = entry
      end

      cleaned = prune_disparues(@tdc.safe_referentiel_mapping, cols_by_name.keys)
      @tdc.update!(referentiel_mapping: cleaned.deep_merge(nouvelles))
      @tdc
    end

    private

    def baserow_fields
      engine = ReferentielDePolynesie::API.engine
      raise BaserowIndisponible, 'Baserow n\'est pas configuré.' if engine.nil?

      config = engine.config(@tdc.table_id)
      raise BaserowIndisponible, "Référentiel Baserow introuvable (table_id=#{@tdc.table_id})." if config.nil?

      fields = engine.fields(config)
      raise BaserowIndisponible, 'Impossible de récupérer les colonnes du référentiel Baserow.' if fields.nil?

      fields
    end

    def mapping_type_for(field)
      ReferentielDePolynesie::BaserowAPI.new.baserow_type_to_mapping_type(field)
    end

    def prune_disparues(mapping, noms_existants)
      cles_valides = noms_existants.map { |n| "$.#{n}" }
      mapping.reject { |jsonpath, _| jsonpath.start_with?('$.') && cles_valides.exclude?(jsonpath) }
    end

    # pf: éligibilité = type compatible (constante upstream) + cible située après le référentiel
    # dans le bon scope (public→public-après|privé ; privé→privé-après). Primitifs coordinate.* stables.
    def valider_cible!(stable_id, type_mapping)
      cible = eligible_target_tdcs.find { _1.stable_id.to_s == stable_id }
      raise CibleInvalide, "Le champ cible (#{stable_id}) doit être situé après le référentiel et de visibilité compatible." if cible.nil?

      allowed = Referentiels::ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP[type_mapping.to_sym] || []
      unless allowed.include?(cible.type_champ)
        raise CibleInvalide, "Le type « #{cible.type_champ} » du champ cible n'est pas compatible avec la colonne (#{type_mapping}). Types compatibles : #{allowed.join(', ')}."
      end
    end

    def eligible_target_tdcs
      coordinate = @draft.coordinate_for(@tdc)
      coords =
        if @tdc.public?
          roots_after(coordinate, @draft.revision_types_de_champ.filter { _1.public? && _1.root? }) +
            @draft.revision_types_de_champ.filter { _1.private? && _1.root? }
        else
          roots_after(coordinate, @draft.revision_types_de_champ.filter { _1.private? && _1.root? })
        end
      coords.map(&:type_de_champ).reject { _1.stable_id == @tdc.stable_id }
    end

    def roots_after(coordinate, scoped_root_coordinates)
      scoped_root_coordinates.filter { _1.position > coordinate.position }
    end
  end
end
```

> **Note MVP :** les cibles éligibles sont les champs **racine** (non imbriqués) situés après le référentiel dans le bon scope. Le cas « formule/prefill dans une répétition » (siblings de la même ligne) est hors MVP — à ajouter si besoin (cf. `ReferentielPrefillComponent#siblings_after_current`).

- [ ] **Step 5 : Lancer, vérifier que ça passe** : `bundle exec rspec spec/services/mcp/referentiel_mapping_service_spec.rb spec/components/referentiels/mapping_type_constant_canary_spec.rb` → vert. Ajuster les assertions si le shape réel des `fields` (clés symbol vs string) diffère — `baserow_type_to_mapping_type` gère les deux ; aligner le stub.

- [ ] **Step 6 : Rubocop + commit**
```bash
bundle exec rubocop app/services/mcp/referentiel_mapping_service.rb
git add app/services/mcp/referentiel_mapping_service.rb spec/services/mcp/referentiel_mapping_service_spec.rb spec/components/referentiels/mapping_type_constant_canary_spec.rb
git commit -m "feat(mcp): service de config du mapping référentiel (éligibilité + prune) + canari constante"
```

---

## Task 2 : Query GraphQL `referentielChampConfig` (lecture)

**Files:**
- Create: `app/graphql/types/mcp/referentiel_colonne_type.rb`, `app/graphql/types/mcp/referentiel_champ_config_type.rb`
- Create: `app/graphql/resolvers/mcp/referentiel_champ_config.rb`
- Modify: `app/graphql/types/query_type.rb`
- Test: `spec/graphql/queries/referentiel_champ_config_spec.rb`

- [ ] **Step 1 : Test (écrire avant)** — `spec/graphql/queries/referentiel_champ_config_spec.rb` : crée un `referentiel_de_polynesie` (table_id), stube l'engine Baserow (comme Task 1), exécute la query et vérifie `tableId`, `colonnes` (nom + typeMapping), `mappingActuel`. Ajouter un cas Baserow indisponible (`engine` nil) → `errors` présent.

```ruby
# frozen_string_literal: true

RSpec.describe 'Query referentielChampConfig', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) { create(:procedure, administrateurs: [admin], types_de_champ_public: [{ type: :referentiel_de_polynesie, libelle: 'Entreprise', table_id: '24' }]) }
  let(:tdc) { procedure.draft_revision.types_de_champ.first }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  let(:engine) { instance_double(ReferentielDePolynesie::BaserowAPI) }
  let(:query) do
    <<-GRAPHQL
    query($demarche: FindDemarcheInput!, $stableId: String!) {
      referentielChampConfig(demarche: $demarche, stableId: $stableId) {
        tableId
        colonnes { nom typeMapping }
        mappingActuel
      }
    }
    GRAPHQL
  end
  let(:variables) { { demarche: { number: procedure.id }, stableId: tdc.stable_id.to_s } }
  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'] }

  before do
    allow(ReferentielDePolynesie::API).to receive(:engine).and_return(engine)
    allow(engine).to receive(:config).and_return({ 'Table' => '24', 'Token' => 't' })
    allow(engine).to receive(:fields).and_return({ 1 => { name: 'RaisonSociale', type: 'text' } })
  end

  it 'retourne table_id + colonnes Baserow' do
    cfg = data['referentielChampConfig']
    expect(cfg['tableId']).to eq('24')
    expect(cfg['colonnes']).to include({ 'nom' => 'RaisonSociale', 'typeMapping' => 'string' })
  end

  context 'Baserow indisponible' do
    before { allow(ReferentielDePolynesie::API).to receive(:engine).and_return(nil) }
    it 'remonte une erreur' do
      expect(subject['errors']).to be_present
    end
  end
end
```

- [ ] **Step 2 : Lancer, vérifier l'échec.**

- [ ] **Step 3 : Types de sortie**

`app/graphql/types/mcp/referentiel_colonne_type.rb` :
```ruby
# frozen_string_literal: true

module Types
  module Mcp
    class ReferentielColonneType < Types::BaseObject
      graphql_name 'McpReferentielColonne'
      field :nom, String, null: false
      field :type_mapping, String, "Type interne (string, integer_number, decimal_number, boolean, date, array).", null: false
    end
  end
end
```

`app/graphql/types/mcp/referentiel_champ_config_type.rb` :
```ruby
# frozen_string_literal: true

module Types
  module Mcp
    class ReferentielChampConfigType < Types::BaseObject
      graphql_name 'McpReferentielChampConfig'
      field :table_id, String, null: true
      field :colonnes, [Types::Mcp::ReferentielColonneType], null: false
      field :mapping_actuel, Types::OptionsBlob, "Mapping courant (par colonne).", null: false
    end
  end
end
```

- [ ] **Step 4 : Resolver**

`app/graphql/resolvers/mcp/referentiel_champ_config.rb` :
```ruby
# frozen_string_literal: true

module Resolvers
  module Mcp
    class ReferentielChampConfig < GraphQL::Schema::Resolver
      type Types::Mcp::ReferentielChampConfigType, null: false

      argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true
      argument :stable_id, String, "stable_id du champ référentiel.", required: true

      def resolve(demarche:, stable_id:)
        number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
        procedure = Procedure.find_by(id: number)
        raise GraphQL::ExecutionError, "La démarche \"#{number}\" n'existe pas." if procedure.nil?
        raise GraphQL::ExecutionError, "Vous n'avez pas accès à la démarche \"#{number}\"." unless context.authorized_demarche?(procedure)

        coordinate, tdc = procedure.draft_revision.coordinate_and_tdc(stable_id)
        raise GraphQL::ExecutionError, "Le champ \"#{stable_id}\" n'existe pas." if coordinate.nil?
        raise GraphQL::ExecutionError, "Le champ \"#{tdc.libelle}\" n'est pas un référentiel de Polynésie." unless tdc.type_champ == 'referentiel_de_polynesie'

        service = ::Mcp::ReferentielMappingService.new(tdc)
        { table_id: tdc.table_id, colonnes: service.colonnes, mapping_actuel: service.mapping_actuel }
      rescue ::Mcp::ReferentielMappingService::BaserowIndisponible => e
        raise GraphQL::ExecutionError, e.message
      end
    end
  end
end
```

- [ ] **Step 5 : Enregistrer** dans `app/graphql/types/query_type.rb` (sous `# pf:`) :
```ruby
    field :referentiel_champ_config, resolver: Resolvers::Mcp::ReferentielChampConfig, description: "Colonnes Baserow + mapping courant d'un champ référentiel (pour le MCP)."
```

- [ ] **Step 6 : Vert + rubocop + commit**
```bash
bundle exec rspec spec/graphql/queries/referentiel_champ_config_spec.rb
bundle exec rubocop app/graphql/types/mcp/referentiel_colonne_type.rb app/graphql/types/mcp/referentiel_champ_config_type.rb app/graphql/resolvers/mcp/referentiel_champ_config.rb
git add app/graphql/types/mcp/referentiel_colonne_type.rb app/graphql/types/mcp/referentiel_champ_config_type.rb app/graphql/resolvers/mcp/referentiel_champ_config.rb app/graphql/types/query_type.rb spec/graphql/queries/referentiel_champ_config_spec.rb
git commit -m "feat(graphql): query referentielChampConfig (colonnes Baserow + mapping) pour le MCP"
```

---

## Task 3 : Mutation `demarcheConfigurerReferentielMapping` (écriture)

**Files:**
- Create: `app/graphql/mutations/demarche_configurer_referentiel_mapping.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Test: `spec/graphql/mutations/demarche_configurer_referentiel_mapping_spec.rb`

- [ ] **Step 1 : Test (écrire avant)** — crée le référentiel + cibles, stube l'engine Baserow, appelle la mutation avec `colonnes: [{ colonne, prefillStableId? | displayUsager/displayInstructeur }]`, vérifie le mapping persisté et un cas d'erreur (cible incompatible → `errors`).

```ruby
# frozen_string_literal: true

RSpec.describe Mutations::DemarcheConfigurerReferentielMapping, type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) do
    create(:procedure, administrateurs: [admin], types_de_champ_public: [
      { type: :referentiel_de_polynesie, libelle: 'Entreprise', table_id: '24' },
      { type: :text, libelle: 'Raison sociale' },
    ])
  end
  let(:tdc) { procedure.draft_revision.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' } }
  let(:cible) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Raison sociale' } }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: true } }
  let(:engine) { instance_double(ReferentielDePolynesie::BaserowAPI) }
  let(:query) do
    <<-GRAPHQL
    mutation($input: DemarcheConfigurerReferentielMappingInput!) {
      demarcheConfigurerReferentielMapping(input: $input) { champStableId errors { message } }
    }
    GRAPHQL
  end
  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'].deep_symbolize_keys }

  before do
    allow(ReferentielDePolynesie::API).to receive(:engine).and_return(engine)
    allow(engine).to receive(:config).and_return({ 'Table' => '24', 'Token' => 't' })
    allow(engine).to receive(:fields).and_return({ 1 => { name: 'RaisonSociale', type: 'text' } })
  end

  context 'prefill valide' do
    let(:variables) do
      { input: { demarche: { number: procedure.id }, stableId: tdc.stable_id.to_s,
                 colonnes: [{ colonne: 'RaisonSociale', prefillStableId: cible.stable_id.to_s }] } }
    end
    it 'configure le mapping' do
      expect(data[:demarcheConfigurerReferentielMapping][:errors]).to be_nil
      mapping = tdc.reload.safe_referentiel_mapping
      expect(mapping['$.RaisonSociale']['prefill_stable_id']).to eq(cible.stable_id.to_s)
    end
  end

  context 'cible incompatible' do
    let(:variables) do
      { input: { demarche: { number: procedure.id }, stableId: tdc.stable_id.to_s,
                 colonnes: [{ colonne: 'RaisonSociale', prefillStableId: tdc.stable_id.to_s }] } }
    end
    it 'retourne une erreur' do
      expect(data[:demarcheConfigurerReferentielMapping][:champStableId]).to be_nil
      expect(data[:demarcheConfigurerReferentielMapping][:errors]).to be_present
    end
  end
end
```

- [ ] **Step 2 : Lancer, vérifier l'échec.**

- [ ] **Step 3 : Input + mutation**

`app/graphql/mutations/demarche_configurer_referentiel_mapping.rb` :
```ruby
# frozen_string_literal: true

# pf: configure le mapping d'un champ referentiel_de_polynesie (prefill / rapatriement) via le MCP.
module Mutations
  class DemarcheConfigurerReferentielMapping < Mutations::DemarcheChampMutation
    class ColonneInput < Types::BaseInputObject
      graphql_name 'McpReferentielColonneInput'
      argument :colonne, String, "Nom de la colonne Baserow.", required: true
      argument :prefill_stable_id, String, "Si fourni : pré-remplit ce champ.", required: false
      argument :display_usager, Boolean, required: false
      argument :display_instructeur, Boolean, required: false
      argument :libelle, String, required: false
    end

    description "Configurer le mapping d'un champ référentiel (pré-remplir / rapatrier)."

    argument :stable_id, String, "stable_id du champ référentiel.", required: true
    argument :colonnes, [ColonneInput], required: true

    def resolve(demarche:, stable_id:, colonnes:)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      coordinate, tdc = procedure.draft_revision.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if coordinate.nil?
      return { errors: ["Le champ \"#{tdc.libelle}\" n'est pas un référentiel de Polynésie."] } unless tdc.type_champ == 'referentiel_de_polynesie'

      ::Mcp::ReferentielMappingService.new(tdc).configurer!(colonnes.map(&:to_h))
      { champ_stable_id: stable_id.to_s }
    rescue ::Mcp::ReferentielMappingService::BaserowIndisponible,
           ::Mcp::ReferentielMappingService::ColonneInconnue,
           ::Mcp::ReferentielMappingService::CibleInvalide => e
      { errors: [e.message] }
    end
  end
end
```

> Vérifier que `colonnes.map(&:to_h)` produit des clés symboles (`:colonne`, `:prefill_stable_id`, `:display_usager`, `:display_instructeur`, `:libelle`) attendues par le service ; adapter (`deep_symbolize_keys`) si nécessaire.

- [ ] **Step 4 : Enregistrer** dans `mutation_type.rb` (sous le groupe `# pf:`) :
```ruby
    field :demarche_configurer_referentiel_mapping, mutation: Mutations::DemarcheConfigurerReferentielMapping
```

- [ ] **Step 5 : Vert + rubocop + commit**
```bash
bundle exec rspec spec/graphql/mutations/demarche_configurer_referentiel_mapping_spec.rb
bundle exec rubocop app/graphql/mutations/demarche_configurer_referentiel_mapping.rb
git add app/graphql/mutations/demarche_configurer_referentiel_mapping.rb app/graphql/types/mutation_type.rb spec/graphql/mutations/demarche_configurer_referentiel_mapping_spec.rb
git commit -m "feat(graphql): mutation demarcheConfigurerReferentielMapping (prefill/rapatrier) pour le MCP"
```

---

## Task 4 : Dump schéma + copie

- [ ] **Step 1 :** `bundle exec rspec spec/graphql/queries/referentiel_champ_config_spec.rb spec/graphql/mutations/demarche_configurer_referentiel_mapping_spec.rb spec/services/mcp/referentiel_mapping_service_spec.rb` → tous verts.
- [ ] **Step 2 :** `bin/rails graphql:schema:dump`
- [ ] **Step 3 :** `grep -E "referentielChampConfig|McpReferentielChampConfig|demarcheConfigurerReferentielMapping|McpReferentielColonne" app/graphql/schema.graphql` → présents.
- [ ] **Step 4 :** confirmer SDL additif (`git diff <base> -- app/graphql/schema.graphql | grep -c '^-[^-]'` = 0).
- [ ] **Step 5 :** `cp app/graphql/schema.graphql /home/clautier/Rubymine/mcp-mes-demarches/schema.graphql`
- [ ] **Step 6 :** commit `app/graphql/schema.graphql app/graphql/schema.json` — « chore(graphql): dump schéma avec config mapping référentiel ».

---

## Task 5 : Outils MCP (`mcp-mes-demarches`)

**Files:** Modify `src/tools.ts`, `src/tools.test.ts`, `schema.graphql`.

- [ ] **Step 1 : Tests (écrire avant)** dans `src/tools.test.ts` :
  - la liste passe à **10 outils** (ajouter `lire_referentiel_champ`, `configurer_referentiel_mapping`).
  - `lire_referentiel_champ` interroge `referentielChampConfig` avec `{ demarche:{number}, stableId }` et renvoie le JSON.
  - `configurer_referentiel_mapping` envoie `input.colonnes` avec le bon shape.

```ts
  it('lire_referentiel_champ interroge referentielChampConfig', async () => {
    const gql = vi.fn().mockResolvedValue({ referentielChampConfig: { tableId: '24', colonnes: [{ nom: 'RaisonSociale', typeMapping: 'string' }], mappingActuel: {} } });
    const res = await byName('lire_referentiel_champ').run({ gql }, { demarcheNumber: 2, stableId: '7' });
    const [, variables] = gql.mock.calls[0];
    expect(variables).toEqual({ demarche: { number: 2 }, stableId: '7' });
    expect(res.content[0].text).toContain('RaisonSociale');
  });

  it('configurer_referentiel_mapping transmet les colonnes', async () => {
    const gql = vi.fn().mockResolvedValue({ demarcheConfigurerReferentielMapping: { champStableId: '7', errors: null } });
    await byName('configurer_referentiel_mapping').run({ gql }, {
      demarcheNumber: 2, stableId: '7',
      colonnes: [{ colonne: 'RaisonSociale', prefillStableId: '8' }]
    });
    const [, variables] = gql.mock.calls[0];
    expect(variables.input.colonnes[0]).toEqual({ colonne: 'RaisonSociale', prefillStableId: '8' });
  });
```

- [ ] **Step 2 : Lancer, vérifier l'échec.**

- [ ] **Step 3 : Ajouter les 2 outils dans `src/tools.ts`** :
```ts
  {
    name: 'lire_referentiel_champ',
    description: "Pour un champ référentiel (referentiel_de_polynesie) : liste les colonnes Baserow disponibles (nom + type) et le mapping actuel (pré-remplissage / rapatriement). À appeler avant de configurer le mapping. Erreur si Baserow est injoignable.",
    inputSchema: { demarcheNumber: z.number().int(), stableId: z.string().describe('stable_id du champ référentiel.') },
    run: async ({ gql }, { demarcheNumber, stableId }) => {
      const query = `query($demarche: FindDemarcheInput!, $stableId: String!){ referentielChampConfig(demarche: $demarche, stableId: $stableId){ tableId colonnes { nom typeMapping } mappingActuel } }`;
      const data = await gql(query, { demarche: { number: demarcheNumber }, stableId });
      return { content: [{ type: 'text', text: JSON.stringify(data.referentielChampConfig, null, 2) }] };
    }
  },
  {
    name: 'configurer_referentiel_mapping',
    description: "Configure le mapping d'un champ référentiel : pour chaque colonne, soit la pré-remplir vers un champ cible (prefillStableId, situé APRÈS le référentiel, type compatible), soit la rapatrier/afficher (displayUsager/displayInstructeur). Appelle d'abord lire_referentiel_champ pour connaître les colonnes.",
    inputSchema: {
      demarcheNumber: z.number().int(),
      stableId: z.string(),
      colonnes: z.array(z.object({
        colonne: z.string().describe('Nom de la colonne Baserow.'),
        prefillStableId: z.string().optional().describe('Si fourni : pré-remplit ce champ cible.'),
        displayUsager: z.boolean().optional().describe('Rapatrier/afficher à l\'usager.'),
        displayInstructeur: z.boolean().optional().describe('Rapatrier/afficher à l\'instructeur.'),
        libelle: z.string().optional()
      }))
    },
    run: async ({ gql }, a) => {
      const query = `mutation($input: DemarcheConfigurerReferentielMappingInput!){ demarcheConfigurerReferentielMapping(input: $input) { champStableId errors { message } } }`;
      const data = await gql(query, { input: { demarche: { number: a.demarcheNumber }, stableId: a.stableId, colonnes: a.colonnes } });
      return mutationResult(data.demarcheConfigurerReferentielMapping);
    }
  }
```
(Réutilise le helper `mutationResult` existant.)

- [ ] **Step 4 : Vert + typecheck + build + commit**
```bash
npm test && npm run typecheck && npm run build
git add src/tools.ts src/tools.test.ts schema.graphql
git commit -m "feat: outils MCP lire_referentiel_champ + configurer_referentiel_mapping"
```

---

## Self-Review (à l'écriture)

- **Couverture spec :** lecture (colonnes + mapping) = Task 2 ; écriture (prefill/rapatrier) = Task 3 ; éligibilité (constante+canari, ordre/scope isolé) + prune + blocage Baserow = Task 1 (service testé) ; MCP = Task 5. Conforme à la spec validée.
- **Placeholders :** aucun ; quelques « confirmer le shape » signalés (clés symbol/string des `fields`, `to_h` des inputs).
- **Couplage upstream :** unique = `MAPPING_TYPE_TO_TYPE_DE_CHAMP` (constante publique) pinnée par un **spec canari** ; le reste = primitifs `coordinate.*` stables réécrits en PF isolé. Aucun `send`, aucun refactor.
- **Tests :** Baserow stubbé via `ReferentielDePolynesie::API.engine` (pas de réseau) ; la propagation prefill (`propagate_prefill`) reste testée upstream, non re-testée ici.

## Hors périmètre

Création de la source (`table_id`/Baserow/auth), référentiels API génériques, cibles imbriquées dans une répétition (MVP = cibles racine), validation de la *forme* des valeurs Baserow.
