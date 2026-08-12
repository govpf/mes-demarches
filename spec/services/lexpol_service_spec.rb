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

    context "avec les colonnes d'export" do
      let(:dossier) { create(:dossier, :en_instruction, procedure: procedure) }

      it 'inclut les colonnes depuis dossier_columns_for_export' do
        variables = service.build_variables

        expect(variables).to have_key('État du dossier')
        expect(variables['État du dossier']).to be_present
      end

      it 'inclut les colonnes depuis usager_columns_for_export' do
        variables = service.build_variables

        dossier_key = variables.keys.find { |k| k.include?('dossier') && k.include?('N') }
        expect(dossier_key).to be_present
        expect(variables[dossier_key]).to eq(dossier.id.to_s)
      end

      it 'formate correctement les dates pour les colonnes avec valeur' do
        variables = service.build_variables

        date_columns = variables.keys.filter { |k| k.include?('instruction') }
        expect(date_columns).not_to be_empty
      end

      # pf: l'heure de dépôt n'a rien à faire d'office dans un arrêté. La
      # variable standard ne porte plus que la date, dans un format que le
      # formateur Lexpol sait convertir en toutes lettres.
      context 'pour un horodatage système' do
        let(:dossier) { create(:dossier, :en_instruction, procedure: procedure) }

        before { dossier.update!(depose_at: Time.zone.local(2026, 4, 1, 0, 3)) }

        it 'transmet la date seule en jj/mm/aaaa' do
          variables = service.build_variables

          expect(variables['Date de dépôt']).to eq('01/04/2026')
        end

        it "expose l'heure dans une variable dédiée" do
          variables = service.build_variables

          expect(variables['Date de dépôt (heure)']).to eq('00:03')
        end

        it "propage la date et l'heure aux alias legacy" do
          variables = service.build_variables

          expect(variables['Dossier déposé le']).to eq('01/04/2026')
          expect(variables['Dossier déposé le (heure)']).to eq('00:03')
        end
      end

      context 'pour une procédure entreprise' do
        let(:procedure) { create(:procedure, :published) }
        let!(:lexpol_type_de_champ) { create(:type_de_champ_lexpol, procedure: procedure) }
        let(:dossier) { create(:dossier, :en_instruction, :with_entreprise, procedure: procedure) }
        let(:lexpol_champ) { dossier.champs.find { |c| c.type_de_champ == lexpol_type_de_champ } }

        it 'inclut les colonnes entreprise' do
          variables = service.build_variables

          expect(variables).to have_key('Entreprise raison sociale')
        end
      end
    end

    context 'avec un champ datetime' do
      let!(:datetime_tdc) do
        create(:type_de_champ_datetime, libelle: 'Créneau souhaité', procedure: procedure)
      end

      before do
        procedure.draft_revision.add_type_de_champ(datetime_tdc)
        dossier.reload
        champ = dossier.champs.find { |c| c.type_de_champ == datetime_tdc }
        champ.update!(value: '2026-04-01T14:30:00-10:00')
        dossier.reload
      end

      it 'transmet la date seule dans la variable standard' do
        variables = service.build_variables

        expect(variables['Créneau souhaité']).to eq('01/04/2026')
      end

      it "expose l'heure dans une variable dédiée" do
        variables = service.build_variables

        expect(variables['Créneau souhaité (heure)']).to eq('14:30')
      end
    end

    context 'variables legacy pour compatibilité' do
      let(:procedure) { create(:procedure, :published, :for_individual) }
      let!(:lexpol_type_de_champ) { create(:type_de_champ_lexpol, procedure: procedure) }
      let(:dossier) { create(:dossier, :en_instruction, procedure: procedure) }
      let(:lexpol_champ) { dossier.champs.find { |c| c.type_de_champ == lexpol_type_de_champ } }
      let(:apilexpol) { instance_double(APILexpol) }
      let(:service) { described_class.new(champ: lexpol_champ, dossier: dossier, apilexpol: apilexpol) }

      it 'inclut "Dossier instruit par" quand il y a des instructeurs' do
        instructeur = create(:instructeur)
        dossier.followers_instructeurs << instructeur
        dossier.reload

        variables = service.build_variables

        expect(variables).to have_key('Dossier instruit par')
        expect(variables['Dossier instruit par']).to eq(instructeur.email)
      end

      it 'n\'inclut pas "Dossier instruit par" quand il n\'y a pas d\'instructeur' do
        variables = service.build_variables

        expect(variables).not_to have_key('Dossier instruit par')
      end

      context 'pour une procédure individuelle' do
        it 'inclut "Mandataire" quand prénom et nom sont présents' do
          dossier.update!(
            mandataire_first_name: 'Jean',
            mandataire_last_name: 'Dupont'
          )

          variables = service.build_variables

          expect(variables).to have_key('Mandataire')
          expect(variables['Mandataire']).to eq('Jean Dupont')
        end

        it 'n\'inclut pas "Mandataire" quand les champs sont vides' do
          variables = service.build_variables

          expect(variables).not_to have_key('Mandataire')
        end
      end

      context 'pour une procédure entreprise' do
        let(:procedure) { create(:procedure, :published) }
        let!(:lexpol_type_de_champ) { create(:type_de_champ_lexpol, procedure: procedure) }
        let(:dossier) { create(:dossier, :en_instruction, :with_entreprise, procedure: procedure) }

        it 'n\'inclut pas "Mandataire" (réservé aux individus)' do
          variables = service.build_variables

          expect(variables).not_to have_key('Mandataire')
        end
      end
    end
  end

  describe '.lexpol_variables' do
    let(:draft_procedure) { create(:procedure, :for_individual) }
    let!(:draft_lexpol_tdc) { create(:type_de_champ_lexpol, procedure: draft_procedure) }

    it "inclut les variables depuis les colonnes d'export" do
      variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)

      expect(variables).to include('État du dossier')
      expect(variables).to include('Adresse électronique')
      expect(variables).to include('Civilité')
      expect(variables).to include('Nom')
      expect(variables).to include('Prénom')
    end

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

    context 'avec un champ datetime' do
      let!(:datetime_tdc) do
        create(:type_de_champ_datetime, libelle: 'Créneau souhaité', procedure: draft_procedure)
      end

      it 'inclut la variable standard et sa variable (heure)' do
        variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)

        expect(variables).to include('Créneau souhaité')
        expect(variables).to include('Créneau souhaité (heure)')
      end
    end

    it "inclut la variable (heure) des colonnes d'horodatage" do
      variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)

      expect(variables).to include('Date de dépôt')
      expect(variables).to include('Date de dépôt (heure)')
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

    it 'inclut les variables legacy pour compatibilité' do
      variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)

      expect(variables).to include('Mandataire')
      expect(variables).to include('Dossier instruit par')
    end

    context 'avec des champs à exclure' do
      let!(:excluded_tdcs) do
        [
          create(:type_de_champ_piece_justificative, libelle: 'Pièce jointe', procedure: draft_procedure),
          create(:type_de_champ_titre_identite, libelle: 'Titre d\'identité', procedure: draft_procedure),
          create(:type_de_champ_header_section, libelle: 'Section', procedure: draft_procedure),
          create(:type_de_champ_explication, libelle: 'Explication', procedure: draft_procedure),
        ]
      end

      it 'exclut les types sans valeur transférable' do
        variables = described_class.lexpol_variables(draft_lexpol_tdc, draft_procedure)
        expect(variables).not_to include('Pièce jointe', 'Titre d\'identité', 'Section', 'Explication')
      end
    end
  end

  describe '.normalize_variable_name' do
    it 'remplace les espaces insécables par des espaces normaux' do
      expect(described_class.normalize_variable_name("Nº\u00A0dossier")).to eq('Nº dossier')
    end
  end
end
