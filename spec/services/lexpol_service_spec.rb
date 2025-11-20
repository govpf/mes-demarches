# frozen_string_literal: true

describe LexpolService do
  let(:procedure) { create(:procedure, :published, :for_individual) }
  let!(:lexpol_type_de_champ) { create(:type_de_champ_lexpol, procedure: procedure) }
  let(:dossier) { create(:dossier, procedure: procedure) }
  let(:lexpol_champ) { dossier.champs.find { |c| c.type_de_champ == lexpol_type_de_champ } }
  let(:apilexpol) { instance_double(APILexpol) }
  let(:service) { described_class.new(champ: lexpol_champ, dossier: dossier, apilexpol: apilexpol) }

  describe '#build_variables' do
    context 'avec un champ MultipleDropDownListChamp' do
      let(:multiple_drop_down_tdc) do
        create(:type_de_champ_multiple_drop_down_list,
               libelle: 'Catégories',
               drop_down_options: ['Option A', 'Option B', 'Option C'],
               procedure: procedure)
      end

      before do
        procedure.draft_revision.add_type_de_champ(multiple_drop_down_tdc)
        dossier.reload
      end

      context 'avec des valeurs sélectionnées' do
        let(:champ) do
          dossier.champs.find { |c| c.type_de_champ == multiple_drop_down_tdc }
        end

        before do
          champ.value = '["Option A","Option B","Option C"]'
          champ.save!
        end

        it 'génère la variable standard' do
          variables = service.build_variables
          expect(variables['Catégories']).to eq('Option A, Option B et Option C')
        end

        it 'génère la variable avec suffixe (liste)' do
          variables = service.build_variables
          expect(variables['Catégories (liste)']).to eq('<ul><li>Option A ;</li><li>Option B ;</li><li>Option C.</li></ul>')
        end
      end

      context 'avec un champ vide' do
        let(:champ) do
          dossier.champs.find { |c| c.type_de_champ == multiple_drop_down_tdc }
        end

        before do
          champ.value = '[]'
          champ.save!
        end

        it 'génère la variable standard vide' do
          variables = service.build_variables
          expect(variables['Catégories']).to eq('')
        end

        it 'génère la variable (liste) vide' do
          variables = service.build_variables
          expect(variables['Catégories (liste)']).to eq('')
        end
      end
    end
  end

  describe '.lexpol_variables' do
    let(:draft_procedure) { create(:procedure, :for_individual) }
    let!(:draft_lexpol_tdc) { create(:type_de_champ_lexpol, procedure: draft_procedure) }

    context 'avec un champ MultipleDropDownListChamp' do
      let!(:multiple_drop_down_tdc) do
        create(:type_de_champ_multiple_drop_down_list,
               libelle: 'Catégories',
               drop_down_options: ['Option A', 'Option B'],
               procedure: draft_procedure)
      end

      it 'inclut la variable standard' do
        variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)
        expect(variables).to include('Catégories')
      end

      it 'inclut la variable avec suffixe (liste)' do
        variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)
        expect(variables).to include('Catégories (liste)')
      end
    end

    context 'avec un champ non-multiple' do
      let!(:text_tdc) do
        create(:type_de_champ_text,
               libelle: 'Nom',
               procedure: draft_procedure)
      end

      it 'inclut uniquement la variable standard' do
        variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)
        expect(variables).to include('Nom')
        expect(variables).not_to include('Nom (liste)')
      end
    end
  end
end
