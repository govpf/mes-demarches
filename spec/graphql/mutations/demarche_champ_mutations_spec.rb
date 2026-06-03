# frozen_string_literal: true

RSpec.describe 'Mutations MCP construction de champs', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) { create(:procedure, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: true } }
  let(:variables) { {} }

  subject { API::V2::Schema.execute(query, variables:, context:) }

  let(:data) { subject['data'].deep_symbolize_keys }

  describe 'demarcheAjouterChamp' do
    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheAjouterChampInput!) {
        demarcheAjouterChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:variables) do
      { input: { demarche: { number: procedure.id }, typeChamp: 'email', libelle: 'Courriel' } }
    end

    it 'ajoute le champ au brouillon' do
      expect(data[:demarcheAjouterChamp][:errors]).to be_nil
      new_tdc = procedure.draft_revision.reload.types_de_champ.find { _1.libelle == 'Courriel' }
      expect(new_tdc).to be_present
      expect(data[:demarcheAjouterChamp][:champStableId]).to eq(new_tdc.stable_id.to_s)
    end

    context 'insertion dans une répétition via parent_stable_id' do
      let(:procedure) do
        create(:procedure, administrateurs: [admin],
          types_de_champ_public: [{ type: :repetition, libelle: 'Lignes', children: [{ type: :text, libelle: 'Existant' }] }])
      end
      let(:repetition_stable_id) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Lignes' }.stable_id.to_s }
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'text', libelle: 'Quantité', parentStableId: repetition_stable_id } }
      end

      it 'insère le champ enfant dans la répétition' do
        expect(data[:demarcheAjouterChamp][:errors]).to be_nil
        new_tdc = procedure.draft_revision.reload.types_de_champ.find { _1.libelle == 'Quantité' }
        expect(new_tdc).to be_present
        coordinate = procedure.draft_revision.revision_types_de_champ.find { _1.stable_id == new_tdc.stable_id }
        expect(coordinate.child?).to be(true)
      end
    end

    context 'parent_stable_id inexistant' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'text', libelle: 'X', parentStableId: '999999' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheAjouterChamp][:champStableId]).to be_nil
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include("n'existe pas")
      end
    end

    context 'apres_stable_id inexistant' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'text', libelle: 'X', apresStableId: '999999' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheAjouterChamp][:champStableId]).to be_nil
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include("n'existe pas")
      end
    end

    context 'type inconnu' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'pas_un_type', libelle: 'X' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheAjouterChamp][:champStableId]).to be_nil
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('Type de champ inconnu')
      end
    end

    context 'démarche non autorisée pour le token' do
      let(:other_procedure) { create(:procedure) }
      let(:variables) do
        { input: { demarche: { number: other_procedure.id }, typeChamp: 'text', libelle: 'X' } }
      end

      it 'retourne une erreur d autorisation' do
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('accès')
      end
    end

    context 'token en lecture seule' do
      let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }

      it 'refuse la mutation' do
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('lecture')
      end
    end
  end

  describe 'demarcheDeplacerChamp' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :text, libelle: 'Premier' },
        { type: :text, libelle: 'Second' },
      ])
    end
    let(:premier) { procedure.draft_revision.types_de_champ.first }
    let(:second) { procedure.draft_revision.types_de_champ.second }

    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheDeplacerChampInput!) {
        demarcheDeplacerChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:variables) do
      { input: { demarche: { number: procedure.id }, stableId: premier.stable_id.to_s, apresStableId: second.stable_id.to_s } }
    end

    it 'place le premier champ après le second' do
      expect(data[:demarcheDeplacerChamp][:errors]).to be_nil
      libelles = procedure.draft_revision.reload.types_de_champ.map(&:libelle)
      expect(libelles).to eq(['Second', 'Premier'])
    end

    context 'champ de destination inexistant' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: premier.stable_id.to_s, apresStableId: '999999' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheDeplacerChamp][:errors].first[:message]).to include('destination')
      end
    end
  end

  describe 'demarcheSupprimerChamp' do
    let(:procedure) { create(:procedure, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
    let(:stable_id) { procedure.draft_revision.types_de_champ.first.stable_id }
    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheSupprimerChampInput!) {
        demarcheSupprimerChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:variables) do
      { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s } }
    end

    it 'supprime le champ du brouillon' do
      expect(data[:demarcheSupprimerChamp][:errors]).to be_nil
      expect(data[:demarcheSupprimerChamp][:champStableId]).to eq(stable_id.to_s)
      expect(procedure.draft_revision.reload.types_de_champ).to be_empty
    end

    context 'champ inexistant' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: '999999' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheSupprimerChamp][:errors].first[:message]).to include("n'existe pas")
      end
    end
  end

  describe 'demarcheDefinirCondition' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :integer_number, libelle: 'Âge' },
        { type: :text, libelle: 'Détail' },
      ])
    end
    let(:source) { procedure.draft_revision.types_de_champ.first }
    let(:cible)  { procedure.draft_revision.types_de_champ.second }

    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheDefinirConditionInput!) {
        demarcheDefinirCondition(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end

    def cible_condition
      procedure.draft_revision.reload.types_de_champ.find { _1.stable_id == cible.stable_id }.condition
    end

    context 'condition numérique simple' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: source.stable_id.to_s, operateur: 'superieur_ou_egal', valeur: '18' }] } }
      end

      it 'pose la condition' do
        expect(data[:demarcheDefinirCondition][:errors]).to be_nil
        expect(data[:demarcheDefinirCondition][:champStableId]).to eq(cible.stable_id.to_s)
        condition = cible_condition
        expect(condition).to be_a(Logic::GreaterThanEq)
        expect(condition.left).to be_a(Logic::ChampValue)
        expect(condition.left.stable_id).to eq(source.stable_id)
        expect(condition.right).to be_a(Logic::Constant)
        expect(condition.right.value).to eq(18)
      end
    end

    context 'combinateur OU avec deux termes' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s, combinateur: 'OU',
                   termes: [
                     { champSourceStableId: source.stable_id.to_s, operateur: 'superieur', valeur: '18' },
                     { champSourceStableId: source.stable_id.to_s, operateur: 'inferieur', valeur: '5' },
                   ] } }
      end

      it 'construit un Logic::Or à deux opérandes' do
        expect(data[:demarcheDefinirCondition][:errors]).to be_nil
        condition = cible_condition
        expect(condition).to be_a(Logic::Or)
        expect(condition.operands.size).to eq(2)
      end
    end

    context 'liste de termes vide' do
      before do
        cible.update!(condition: Logic::GreaterThanEq.new(Logic::ChampValue.new(source.stable_id), Logic::Constant.new(1)))
      end
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s, termes: [] } }
      end

      it 'retire la condition' do
        expect(data[:demarcheDefinirCondition][:errors]).to be_nil
        expect(cible_condition).to be_nil
      end
    end

    context 'opérateur inconnu' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: source.stable_id.to_s, operateur: 'entre', valeur: '18' }] } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheDefinirCondition][:champStableId]).to be_nil
        expect(data[:demarcheDefinirCondition][:errors].first[:message]).to include('Opérateur inconnu')
      end
    end

    context 'opérateur incompatible (champ source = la cible texte, non amont)' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: cible.stable_id.to_s, operateur: 'superieur', valeur: '3' }] } }
      end

      it 'retourne une erreur (pas un 500)' do
        expect(data[:demarcheDefinirCondition][:champStableId]).to be_nil
        expect(data[:demarcheDefinirCondition][:errors]).to be_present
      end
    end

    context 'champ source non situé en amont' do
      let(:procedure) do
        create(:procedure, administrateurs: [admin], types_de_champ_public: [
          { type: :text, libelle: 'Cible' },
          { type: :integer_number, libelle: 'AprèsSource' },
        ])
      end
      let(:cible)  { procedure.draft_revision.types_de_champ.first }
      let(:apres)  { procedure.draft_revision.types_de_champ.second }
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: apres.stable_id.to_s, operateur: 'superieur', valeur: '1' }] } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheDefinirCondition][:champStableId]).to be_nil
        expect(data[:demarcheDefinirCondition][:errors]).to be_present
      end
    end

    context 'combinateur invalide' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s, combinateur: 'XOR',
                   termes: [
                     { champSourceStableId: source.stable_id.to_s, operateur: 'superieur', valeur: '18' },
                     { champSourceStableId: source.stable_id.to_s, operateur: 'inferieur', valeur: '5' },
                   ] } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheDefinirCondition][:champStableId]).to be_nil
        expect(data[:demarcheDefinirCondition][:errors].first[:message]).to include('combinateur')
      end
    end
  end

  describe 'demarcheModifierChamp' do
    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheModifierChampInput!) {
        demarcheModifierChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:stable_id) { procedure.draft_revision.types_de_champ.first.stable_id }

    context 'modification du libellé' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, libelle: 'Nom complet' } }
      end

      it 'met à jour le libellé' do
        expect(data[:demarcheModifierChamp][:errors]).to be_nil
        expect(procedure.draft_revision.reload.types_de_champ.first.libelle).to eq('Nom complet')
      end
    end

    context 'changement de type INCOMPATIBLE sur un champ déjà publié' do
      # text → date n'est pas dans ACCEPTED_TYPES["text"], donc interdit
      let(:procedure) { create(:procedure, :published, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, typeChamp: 'date' } }
      end

      it 'est refusé' do
        expect(data[:demarcheModifierChamp][:champStableId]).to be_nil
        expect(data[:demarcheModifierChamp][:errors].first[:message]).to include('compatible')
      end
    end

    context 'changement de type COMPATIBLE sur un champ déjà publié' do
      # text → textarea est dans ACCEPTED_TYPES["text"] (dérivé de Columns::ChampColumn::CAST)
      let(:procedure) { create(:procedure, :published, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, typeChamp: 'textarea' } }
      end

      it 'est autorisé (réutilise ACCEPTED_TYPES)' do
        expect(data[:demarcheModifierChamp][:errors]).to be_nil
        expect(procedure.draft_revision.reload.types_de_champ.first.type_champ).to eq('textarea')
      end
    end

    context 'changement de type sur un champ seulement en brouillon' do
      # Aucune restriction : le champ n'est pas encore publié, aucun dossier existant à migrer
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, typeChamp: 'date' } }
      end

      it 'est autorisé (aucun dossier à migrer)' do
        expect(data[:demarcheModifierChamp][:errors]).to be_nil
        expect(procedure.draft_revision.reload.types_de_champ.first.type_champ).to eq('date')
      end
    end
  end
end
