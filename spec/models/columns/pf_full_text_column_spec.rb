# frozen_string_literal: true

describe Columns::PfFullTextColumn do
  let(:groupe_instructeur) { create(:groupe_instructeur, instructeurs: [create(:instructeur)]) }
  let(:procedure) do
    create(:procedure,
      groupe_instructeurs: [groupe_instructeur],
      types_de_champ_public: [{ type: :text }],
      types_de_champ_private: [{ type: :text }])
  end
  let!(:dossier) do
    create(:dossier, procedure:, state: :en_construction, user: create(:user, email: 'jean@example.com')).tap do |d|
      d.project_champs_private.first.update!(value: 'note confidentielle')
    end
  end
  let(:column) { Columns::PfFullTextColumn.new(procedure_id: procedure.id) }
  let(:dossiers) { Dossier.where(groupe_instructeur_id: procedure.groupe_instructeurs.ids) }

  before { perform_enqueued_jobs(only: DossierIndexSearchTermsJob) }

  describe '#filtered_ids' do
    it 'matches against public search_terms' do
      expect(column.filtered_ids(dossiers, { value: ['jean'] })).to eq([dossier.id])
    end

    it 'matches against private_search_terms (annotations)' do
      expect(column.filtered_ids(dossiers, { value: ['confidentielle'] })).to eq([dossier.id])
    end

    it 'is a no-op when the value is blank' do
      expect(column.filtered_ids(dossiers, { value: [''] })).to match_array(dossiers.ids)
    end
  end
end
