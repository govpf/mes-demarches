# frozen_string_literal: true

# pf: ordre de calcul entre niveaux, prouvé à travers l'interface. L'ordre vient
# du graphe de dépendances de la révision (public, chaque bloc déplié à sa place,
# puis privé) et non des positions brutes, qui mélangent les niveaux.
describe 'Ordre de calcul des formules entre niveaux', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  context 'formule-ligne en tête de bloc qui lit une formule racine' do
    let!(:procedure) do
      create(:procedure, :published, :for_individual, types_de_champ_public: [
        { type: :integer_number, libelle: 'Coef' },
        { type: :formule, libelle: 'Taux' },
        {
          type: :repetition, libelle: 'Lignes', mandatory: false, children: [
            { type: :formule, libelle: 'Montant' },
            { type: :integer_number, libelle: 'Prix' },
          ],
        },
      ])
    end
    let(:revision) { procedure.active_revision }
    let(:coef_tdc) { revision.types_de_champ.find { _1.libelle == 'Coef' } }
    let(:taux_tdc) { revision.types_de_champ.find { _1.libelle == 'Taux' } }
    let(:bloc_tdc) { revision.types_de_champ.find { _1.libelle == 'Lignes' } }
    let(:montant_tdc) { revision.types_de_champ.find { _1.libelle == 'Montant' } }
    let!(:dossier) { create(:dossier, :brouillon, :with_individual, procedure:, user:) }
    let!(:row_id) do
      # pf: expressions posées avant de charger le dossier (une révision déjà
      # chargée ne voit pas un update! ultérieur)
      taux_tdc.update!(formule_expression: "{tdc#{coef_tdc.stable_id}} * 2")
      montant_tdc.update!(formule_expression: "{tdc#{taux_tdc.stable_id}} * 10")
      dossier.repetition_add_row(bloc_tdc, updated_by: 'setup')
    end

    before do
      dossier.champ_for_update(montant_tdc, row_id:, updated_by: 'setup').save!
      login_as user, scope: :user
      visit brouillon_dossier_path(dossier)
      find('.dom-ready')
    end

    scenario 'une formule-ligne en tête de bloc suit une formule racine' do
      fill_in('Coef', with: '1')
      wait_for_autosave
      fill_in('Coef', with: '3')
      wait_for_autosave

      wait_until { montant_value == '60' }
      expect(taux_value).to eq('6')
      expect(montant_value).to eq('60')
      # affichés sans rechargement de la page
      expect(page).to have_text('60')
    end
  end

  context 'annotation privée en tête qui lit une formule publique' do
    let!(:instructeur) { create(:instructeur) }
    let!(:procedure) do
      create(:procedure, :published, :for_individual, instructeurs: [instructeur],
        types_de_champ_public: [
          { type: :integer_number, libelle: 'Source' },
          { type: :formule, libelle: 'Double' },
        ],
        types_de_champ_private: [
          { type: :formule, libelle: 'Plus un' },
        ])
    end
    let(:revision) { procedure.active_revision }
    let(:source_tdc) { revision.types_de_champ.find { _1.libelle == 'Source' } }
    let(:double_tdc) { revision.types_de_champ.find { _1.libelle == 'Double' } }
    let(:plus_un_tdc) { revision.types_de_champ.find { _1.libelle == 'Plus un' } }
    let!(:dossier) do
      double_tdc.update!(formule_expression: "{tdc#{source_tdc.stable_id}} * 2")
      plus_un_tdc.update!(formule_expression: "{tdc#{double_tdc.stable_id}} + 1")
      create(:dossier, :brouillon, :with_individual, procedure:, user:)
    end

    scenario 'une annotation privée en tête suit une formule publique' do
      login_as user, scope: :user
      visit brouillon_dossier_path(dossier)
      find('.dom-ready')

      fill_in('Source', with: '5')
      wait_for_autosave
      fill_in('Source', with: '10')
      wait_for_autosave

      click_on 'Déposer le dossier'
      expect(page).to have_content('Merci')
      log_out

      login_as instructeur.user, scope: :user
      visit instructeur_dossier_path(procedure, dossier)
      click_on 'Annotations privées'
      within('.editable-champ', text: 'Plus un') do
        expect(page).to have_text('21')
      end
    end
  end

  private

  # pf: lecture directe en DB (project_champs est mémoïsé)
  def value_in_db(tdc, row_id: nil)
    Champ.where(dossier_id: dossier.id, stable_id: tdc.stable_id, row_id:)
      .first&.read_attribute(:value)
  end

  def taux_value = value_in_db(taux_tdc)
  def montant_value = value_in_db(montant_tdc, row_id:)
end
