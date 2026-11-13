# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe T20261106reinitialiserMemorisationDlnufTask do
    let(:task) { described_class.new.tap { _1.table_id = 24 } }
    let!(:memorise) { create(:baserow_referentiel, url: 'baserow://24', autocomplete_configuration: { 'dlnuf_vu_le' => '2026-11-01T00:00:00Z' }) }
    let!(:autre_table) { create(:baserow_referentiel, url: 'baserow://25', autocomplete_configuration: { 'dlnuf_vu_le' => '2026-11-01T00:00:00Z' }) }

    it 'cible les référentiels de la table demandée' do
      expect(task.collection).to contain_exactly(memorise)
    end

    it 'retire la mémorisation de la table, et seulement elle' do
      task.process(memorise)

      expect(Referentiels::BaserowReferentiel.dlnuf_vu?(24)).to be(false)
      expect(Referentiels::BaserowReferentiel.dlnuf_vu?(25)).to be(true)
    end

    it 'exige un table_id' do
      expect(described_class.new).not_to be_valid
    end
  end
end
