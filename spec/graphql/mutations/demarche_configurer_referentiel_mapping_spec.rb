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
  # pf: API.engine retourne la CLASSE BaserowAPI (pas une instance) — utiliser class_double
  let(:engine) { class_double(ReferentielDePolynesie::BaserowAPI) }
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

    it 'configure le mapping et retourne le stable_id' do
      expect(data[:demarcheConfigurerReferentielMapping][:errors]).to be_nil
      expect(data[:demarcheConfigurerReferentielMapping][:champStableId]).to eq(tdc.stable_id.to_s)
      mapping = tdc.reload.safe_referentiel_mapping
      expect(mapping['$.RaisonSociale']['prefill_stable_id']).to eq(cible.stable_id.to_s)
      expect(mapping['$.RaisonSociale']['prefill']).to eq('1')
    end
  end

  context 'cible incompatible (referentiel_de_polynesie ne peut pas être cible)' do
    let(:variables) do
      { input: { demarche: { number: procedure.id }, stableId: tdc.stable_id.to_s,
                 colonnes: [{ colonne: 'RaisonSociale', prefillStableId: tdc.stable_id.to_s }] } }
    end

    it 'retourne une erreur sans persister' do
      expect(data[:demarcheConfigurerReferentielMapping][:champStableId]).to be_nil
      expect(data[:demarcheConfigurerReferentielMapping][:errors]).to be_present
    end
  end
end
