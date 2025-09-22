# frozen_string_literal: true

describe DossierProjectionService do
  describe '#project' do
    subject { described_class.project(dossiers_ids, columns) }

    let(:procedure) { create(:procedure, types_de_champ_public:) }
    let(:types_de_champ_public) do
      [
        { type: :text, libelle: 'texte' },
        { type: :integer_number, libelle: 'nombre entier' }
      ]
    end
    let(:dossiers) { create_list(:dossier, 3, procedure:) }
    let(:dossiers_ids) { dossiers.take(2).map(&:id) }
    let(:text_column) { procedure.find_column(label: 'texte') }
    let(:columns) { [text_column] }

    it do
      dossiers = subject

      expect(dossiers.size).to eq(2)

      before do
        dossier.project_champs_public.first.update(code_postal: '63290', external_id: '63102')
      end

      let(:result) { subject }

      it 'returns champ value' do
        expect(result.length).to eq(1)
        expect(result[0].dossier.id).to eq(dossier.id)
        expect(result[0].columns[0]).to eq('Châteldon (63290)')
      end
    end

    context 'attributes by attributes' do
      let(:procedure) { create(:procedure) }
      let(:columns) { [procedure.find_column(label:)] }
      let(:dossiers_ids) { [dossier.id] }

      subject { super()[0].columns[0] }

      context 'for self table' do
        context 'for created_at column' do
          let(:label) { 'Date de création' }
          let(:dossier) { Timecop.freeze(Time.zone.local(1992, 3, 22)) { create(:dossier, procedure:) } }

          it { is_expected.to eq('22/03/1992') }
        end

        context 'for en_construction_at column' do
          let(:label) { 'Date de passage en construction' }
          let(:dossier) { create(:dossier, :en_construction, en_construction_at: Time.zone.local(2018, 10, 17), procedure:) }

          it { is_expected.to eq('17/10/2018') }
        end

        context 'for depose_at column' do
          let(:label) { 'Date de dépôt' }
          let(:dossier) { create(:dossier, :en_construction, depose_at: Time.zone.local(2018, 10, 17), procedure:) }

          it { is_expected.to eq('17/10/2018') }
        end

        context 'for updated_at column' do
          let(:label) { 'Date du dernier évènement' }
          let(:dossier) { create(:dossier, procedure:) }

          before { dossier.touch(time: Time.zone.local(2018, 9, 25)) }

          it { is_expected.to eq('25/09/2018') }
        end
      end

      context 'for user table' do
        let(:label) { 'Demandeur' }

        let(:dossier) { create(:dossier, user: create(:user, email: 'bla@yopmail.com'), procedure:) }

        it { is_expected.to eq('bla@yopmail.com') }
      end

      context 'for individual table' do
        let(:procedure) { create(:procedure, :for_individual, :with_type_de_champ, :with_type_de_champ_private) }
        let(:dossier) { create(:dossier, procedure:, individual: build(:individual, nom: 'Martin', prenom: 'Jacques', gender: 'M.')) }

        context 'for prenom column' do
          let(:label) { 'Prénom' }

          it { is_expected.to eq('Jacques') }
        end

        context 'for nom column' do
          let(:label) { 'Nom' }

          it { is_expected.to eq('Martin') }
        end

        context 'for gender column' do
          let(:label) { 'Civilité' }

          it { is_expected.to eq('M.') }
        end
      end

      context 'for etablissement table' do
        let(:label) { 'Établissement code postal' }

        let!(:dossier) { create(:dossier, procedure:, etablissement: create(:etablissement, code_postal: '75008')) }

        it { is_expected.to eq('75008') }
      end

      context 'for groupe_instructeur table' do
        let(:label) { 'Groupe instructeur' }

        let!(:dossier) { create(:dossier, procedure:) }

        it { is_expected.to eq('défaut') }
      end

      context 'for followers_instructeurs table' do
        let(:label) { 'Instructeurs' }

        let(:dossier) { create(:dossier, procedure:) }
        let!(:follow1) { create(:follow, dossier: dossier, instructeur: create(:instructeur, email: 'b@host.fr')) }
        let!(:follow2) { create(:follow, dossier: dossier, instructeur: create(:instructeur, email: 'a@host.fr')) }
        let!(:follow3) { create(:follow, dossier: dossier, instructeur: create(:instructeur, email: 'c@host.fr')) }

        it { is_expected.to eq "a@host.fr, b@host.fr, c@host.fr" }
      end

      context 'for type_de_champ table' do
        let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :text }]) }
        let(:dossier) { create(:dossier, procedure:) }
        let(:label) { dossier.procedure.active_revision.types_de_champ_public.first.libelle }

        before do
          dossier.project_champs_public.first.update(value: 'kale')
        end

        it { is_expected.to eq('kale') }
      end

      context 'for type_de_champ_private table' do
        let(:procedure) { create(:procedure, types_de_champ_private: [{ type: :text }]) }
        let(:dossier) { create(:dossier, procedure:) }
        let(:label) { dossier.procedure.active_revision.types_de_champ_private.first.libelle }

        before { dossier.project_champs_private.first.update(value: 'quinoa') }

        it { is_expected.to eq('quinoa') }
      end

      context 'for type_de_champ table and value to.s' do
        let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :yes_no }]) }
        let(:dossier) { create(:dossier, procedure:) }
        let(:label) { dossier.procedure.active_revision.types_de_champ_public.first.libelle }

        before { dossier.project_champs_public.first.update(value: 'true') }

        it { is_expected.to eq('Oui') }
      end

      context 'for type_de_champ table and value to.s which needs data field' do
        let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :address }]) }
        let(:dossier) { create(:dossier, procedure:) }
        let(:label) { dossier.procedure.active_revision.types_de_champ_public.first.libelle }

        before { dossier.project_champs_public.first.update(value: '18 a la bonne rue', data: { 'label' => '18 a la bonne rue', 'departement' => 'd' }) }

        it { is_expected.to eq('18 a la bonne rue') }
      end

      context 'for type_de_champ table: type_de_champ pays which needs external_id field' do
        let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :pays }]) }
        let(:dossier) { create(:dossier, procedure:) }
        let(:label) { dossier.procedure.active_revision.types_de_champ_public.first.libelle }

        around do |example|
          I18n.with_locale(:fr) do
            example.run
          end
        end

        context 'when external id is set' do
          before do
            dossier.project_champs_public.first.update(external_id: 'GB')
          end

          it { is_expected.to eq('Royaume-Uni') }
        end

        context 'when no external id is set' do
          before do
            dossier.project_champs_public.first.update(value: "qu'il est beau mon pays")
          end

          it { is_expected.to eq("") }
        end
      end

      xcontext 'for a json column' do # PF: Le numéro Tahiti (siret) n'a pas de colonne département.
        let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :siret, libelle: 'siret' }]) }
        let(:dossier) { create(:dossier, procedure:) }
        let(:label) { "SIRET – Département" }

        before do
          dossier.project_champs_public.first.update(value_json: { 'department_code': '38' })
        end

        it { is_expected.to eq('38') }
      end
    end
  end
end
