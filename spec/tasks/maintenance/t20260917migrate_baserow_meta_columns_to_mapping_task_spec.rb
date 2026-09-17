# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe T20260917migrateBaserowMetaColumnsToMappingTask do
    let(:task) { described_class.new }
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :referentiel_de_polynesie, referentiel_mapping: mapping }]) }
    let(:tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:mapping) { nil }
    let(:config) { { 'Table' => '19', 'Champs instructeur' => '1, 2,9382', 'Champs usager' => '1,3' } }
    let(:fields) do
      {
        1 => { name: 'Nom', type: 'text', select_options: [] },
        2 => { name: 'Quantité', type: 'number', select_options: [] },
        3 => { name: 'Île', type: 'single_select', select_options: [] },
      }
    end

    before do
      tdc.update_column(:options, tdc.options.merge('table_id' => '19'))
      allow(ReferentielDePolynesie::API).to receive(:config).with('19').and_return(config)
      allow(ReferentielDePolynesie::API).to receive(:table_fields).with('19').and_return(fields)
    end

    describe '#collection' do
      let!(:autre) { create(:type_de_champ_text) }

      it 'ne retient que les champs référentiel de Polynésie' do
        expect(task.collection).to contain_exactly(tdc)
      end
    end

    describe '#process' do
      context 'sans mapping' do
        it 'crée les entrées des colonnes instructeur, sans affichage usager, en ignorant la colonne périmée' do
          task.process(tdc)
          expect(tdc.reload.referentiel_mapping).to eq(
            '$.Nom' => { 'type' => 'string', 'libelle' => 'Nom', 'prefill' => '0', 'display_usager' => '0', 'display_instructeur' => '1' },
            '$.Quantité' => { 'type' => 'integer_number', 'libelle' => 'Quantité', 'prefill' => '0', 'display_usager' => '0', 'display_instructeur' => '1' }
          )
        end

        it 'est idempotente' do
          task.process(tdc)
          expect(ReferentielDePolynesie::API).not_to receive(:table_fields)
          expect { task.process(tdc.reload) }.not_to change { tdc.reload.referentiel_mapping }
        end
      end

      context 'avec un mapping où rien n’est affiché à l’instructeur' do
        let(:mapping) do
          {
            '$.Nom' => { 'type' => 'string', 'libelle' => 'Nom du produit', 'prefill' => '0', 'display_usager' => '1', 'display_instructeur' => '0' },
            '$.Île' => { 'type' => 'string', 'libelle' => 'Île', 'prefill' => '0', 'display_usager' => '1', 'display_instructeur' => '0' },
          }
        end

        it 'coche l’instructeur sur les colonnes méta en conservant le reste du mapping' do
          task.process(tdc)
          expect(tdc.reload.referentiel_mapping).to eq(
            '$.Nom' => { 'type' => 'string', 'libelle' => 'Nom du produit', 'prefill' => '0', 'display_usager' => '1', 'display_instructeur' => '1' },
            '$.Île' => { 'type' => 'string', 'libelle' => 'Île', 'prefill' => '0', 'display_usager' => '1', 'display_instructeur' => '0' },
            '$.Quantité' => { 'type' => 'integer_number', 'libelle' => 'Quantité', 'prefill' => '0', 'display_usager' => '0', 'display_instructeur' => '1' }
          )
        end
      end

      context 'avec un mapping qui affiche déjà des colonnes à l’instructeur' do
        let(:mapping) { { '$.Île' => { 'type' => 'string', 'libelle' => 'Île', 'prefill' => '0', 'display_instructeur' => '1' } } }

        it 'ne touche à rien et n’appelle pas Baserow' do
          expect(ReferentielDePolynesie::API).not_to receive(:config)
          expect { task.process(tdc) }.not_to change { tdc.reload.referentiel_mapping }
        end
      end

      context 'quand la table méta n’a pas de colonnes instructeur' do
        let(:config) { { 'Table' => '19', 'Champs instructeur' => '' } }

        it 'ne touche à rien' do
          expect { task.process(tdc) }.not_to change { tdc.reload.referentiel_mapping }
        end
      end

      context 'quand Baserow est injoignable' do
        let(:fields) { nil }

        it 'laisse le champ intact pour une relance ultérieure' do
          expect { task.process(tdc) }.not_to change { tdc.reload.referentiel_mapping }
        end
      end
    end
  end
end
