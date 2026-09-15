# frozen_string_literal: true

RSpec.describe 'Query demarcheChamps', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) do
    create(:procedure, administrateurs: [admin], types_de_champ_public: [
      { type: :text, libelle: 'Nom' },
      { type: :integer_number, libelle: 'Âge' },
    ])
  end
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  let(:query) do
    <<-GRAPHQL
    query($demarche: FindDemarcheInput!) {
      demarcheChamps(demarche: $demarche) {
        stableId
        typeChamp
        libelle
        obligatoire
        prive
        parentStableId
        position
        aCondition
      }
    }
    GRAPHQL
  end
  let(:variables) { { demarche: { number: procedure.id } } }

  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'].deep_symbolize_keys }

  it 'retourne les champs du brouillon avec leur stable_id' do
    champs = data[:demarcheChamps]
    expect(champs.map { _1[:libelle] }).to eq(['Nom', 'Âge'])
    expect(champs.map { _1[:typeChamp] }).to eq(['text', 'integer_number'])
    expect(champs.first[:stableId]).to eq(procedure.draft_revision.types_de_champ.first.stable_id.to_s)
    expect(champs.first[:aCondition]).to eq(false)
    expect(champs.first[:position]).to eq(0)
    expect(champs.first[:parentStableId]).to be_nil
  end

  context 'démarche non autorisée pour le token' do
    let(:other) { create(:procedure) }
    let(:variables) { { demarche: { number: other.id } } }

    it 'remonte une erreur' do
      expect(subject['errors']).to be_present
    end
  end

  context 'champ avec options' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :drop_down_list, libelle: 'Civilité' },
      ])
    end

    before do
      tdc = procedure.draft_revision.types_de_champ.first
      tdc.update!(options: { 'drop_down_options' => ['M.', 'Mme'], 'drop_down_other' => '1' })
    end

    let(:query) do
      <<-GRAPHQL
      query($demarche: FindDemarcheInput!) {
        demarcheChamps(demarche: $demarche) { stableId typeChamp libelle options }
      }
      GRAPHQL
    end

    it 'expose les options du champ' do
      champ = data[:demarcheChamps].first
      expect(champ[:options]).to include(drop_down_options: ['M.', 'Mme'], drop_down_other: '1')
    end
  end

  context 'champ formule : formule_expression convertie en libellés' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :integer_number, libelle: 'Quantité' },
        { type: :formule, libelle: 'Total' },
      ])
    end

    before do
      revision = procedure.draft_revision
      quantite_stable_id = revision.types_de_champ.find { _1.libelle == 'Quantité' }.stable_id
      tdc_total = revision.types_de_champ.find { _1.libelle == 'Total' }
      tdc_total.update!(options: tdc_total.options.merge('formule_expression' => "{tdc#{quantite_stable_id}} * 2"))
    end

    let(:query) do
      <<-GRAPHQL
      query($demarche: FindDemarcheInput!) {
        demarcheChamps(demarche: $demarche) { libelle typeChamp options }
      }
      GRAPHQL
    end

    it 'expose formule_expression avec les libellés (pas les tokens internes)' do
      total = data[:demarcheChamps].find { _1[:libelle] == 'Total' }
      expect(total[:options][:formule_expression]).to eq('{Quantité} * 2')
    end
  end

  context 'champ enfant dans une répétition' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :repetition, libelle: 'Lignes', children: [{ type: :text, libelle: 'Ligne' }] },
      ])
    end

    it 'expose le parentStableId de l enfant' do
      champs = data[:demarcheChamps]
      repetition = champs.find { _1[:libelle] == 'Lignes' }
      enfant = champs.find { _1[:libelle] == 'Ligne' }
      expect(repetition).to be_present
      expect(enfant).to be_present
      expect(enfant[:parentStableId]).to eq(repetition[:stableId])
    end
  end

  describe 'condition d affichage' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :integer_number, libelle: 'Âge' },
        { type: :yes_no, libelle: 'Majeur' },
        { type: :text, libelle: 'Détail' },
      ])
    end
    let(:age)    { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Âge' } }
    let(:majeur) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Majeur' } }
    let(:detail) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Détail' } }

    let(:query) do
      <<-GRAPHQL
      query($demarche: FindDemarcheInput!) {
        demarcheChamps(demarche: $demarche) {
          libelle
          aCondition
          condition { combinateur termes { champSourceStableId champSourceLibelle operateur valeur } }
        }
      }
      GRAPHQL
    end
    let(:detail_data) { data[:demarcheChamps].find { _1[:libelle] == 'Détail' } }

    context 'sans condition' do
      it 'renvoie null' do
        expect(detail_data[:aCondition]).to eq(false)
        expect(detail_data[:condition]).to be_nil
      end
    end

    context 'condition à un seul terme numérique' do
      before do
        detail.update!(condition: Logic::GreaterThanEq.new(Logic::ChampValue.new(age.stable_id), Logic::Constant.new(18)))
      end

      it 'renvoie le terme au format de la mutation demarcheDefinirCondition' do
        expect(detail_data[:aCondition]).to eq(true)
        expect(detail_data[:condition]).to eq(
          combinateur: 'ET',
          termes: [{ champSourceStableId: age.stable_id.to_s, champSourceLibelle: 'Âge', operateur: 'superieur_ou_egal', valeur: '18' }]
        )
      end
    end

    context 'condition OU à deux termes dont un booléen' do
      before do
        detail.update!(condition: Logic::Or.new([
          Logic::GreaterThan.new(Logic::ChampValue.new(age.stable_id), Logic::Constant.new(65)),
          Logic::Eq.new(Logic::ChampValue.new(majeur.stable_id), Logic::Constant.new(true)),
        ]))
      end

      it 'renvoie le combinateur OU et les deux termes' do
        expect(detail_data[:condition][:combinateur]).to eq('OU')
        expect(detail_data[:condition][:termes]).to eq([
          { champSourceStableId: age.stable_id.to_s, champSourceLibelle: 'Âge', operateur: 'superieur', valeur: '65' },
          { champSourceStableId: majeur.stable_id.to_s, champSourceLibelle: 'Majeur', operateur: 'egal', valeur: 'true' },
        ])
      end
    end

    context 'terme vide laissé par l éditeur' do
      before do
        detail.update!(condition: Logic::And.new([
          Logic::Eq.new(Logic::ChampValue.new(majeur.stable_id), Logic::Constant.new(false)),
          Logic::EmptyOperator.new(Logic::Empty.new, Logic::Empty.new),
        ]))
      end

      it 'ignore le terme vide' do
        expect(detail_data[:condition][:termes].map { _1[:operateur] }).to eq(['egal'])
        expect(detail_data[:condition][:termes].first[:valeur]).to eq('false')
      end
    end

    context 'champ source supprimé de la révision' do
      before do
        detail.update!(condition: Logic::GreaterThan.new(Logic::ChampValue.new(999_999), Logic::Constant.new(1)))
      end

      it 'renvoie le terme avec un libellé source null' do
        terme = detail_data[:condition][:termes].first
        expect(terme[:champSourceStableId]).to eq('999999')
        expect(terme[:champSourceLibelle]).to be_nil
      end
    end
  end
end
