# frozen_string_literal: true

describe DossierLabel do
  let(:procedure) { create(:procedure, :with_labels) }
  let(:dossier) { create(:dossier, procedure:) }

  describe 'label_belongs_to_dossier_procedure' do
    context 'when the label belongs to the dossier procedure' do
      let(:label) { procedure.labels.first }

      it 'is valid' do
        expect(DossierLabel.new(dossier:, label:)).to be_valid
      end
    end

    context 'when the label belongs to another procedure' do
      let(:label) { create(:procedure, :with_labels).labels.first }

      it 'is invalid' do
        expect(DossierLabel.new(dossier:, label:)).not_to be_valid
      end
    end
  end
end
