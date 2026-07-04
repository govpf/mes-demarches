# frozen_string_literal: true

describe 'Instructeur dossier layout toggle (grid/stacked)', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:instructeur) { create(:instructeur, password: password) }
  let(:types_de_champ_public) { [{ type: :text, libelle: 'Nom' }] }
  let!(:procedure) { create(:procedure, :published, types_de_champ_public:, instructeurs: [instructeur]) }
  let!(:dossier) { create(:dossier, :en_construction, :with_populated_champs, procedure: procedure) }

  before { login_as(instructeur.user, scope: :user) }

  context 'avec la gate Flipper activée' do
    before { Flipper.enable(:dossier_layout_grid, instructeur) }
    after  { Flipper.disable(:dossier_layout_grid) }

    context 'user habitué, dans la fenêtre de rollout' do
      before do
        instructeur.user.update!(created_at: Date.new(2025, 1, 1))
        # Le navigateur vit en temps réel : travel_to rendrait l'expiration absolue du
        # cookie de dismiss (FEATURE_ROLLOUT_DATE + BANNER_DURATION) antérieure à
        # l'horloge du navigateur une fois la fenêtre de rollout réelle passée.
        # On déplace donc la fenêtre plutôt que l'horloge.
        stub_const('InstructeurChampDisplayHelper::FEATURE_ROLLOUT_DATE', Date.current - 5.days)
      end

      it 'affiche le bandeau avec les deux boutons "garder" et "revenir"' do
        visit instructeur_dossier_path(procedure, dossier)

        expect(page).to have_css('.fr-callout', text: 'Nouvel affichage des champs')
        expect(page).to have_button('Garder le nouvel affichage')
        expect(page).to have_button("Revenir à l'ancien affichage")
      end

      it 'cliquer sur "Garder" fait disparaître le bandeau sans changer le layout' do
        visit instructeur_dossier_path(procedure, dossier)
        click_on 'Garder le nouvel affichage'

        expect(page).not_to have_css('.fr-callout', text: 'Nouvel affichage des champs')
        expect(instructeur.reload.dossier_layout_preference).to be_nil
      end

      it 'cliquer sur "Revenir" bascule en stacked et persiste en DB' do
        visit instructeur_dossier_path(procedure, dossier)
        click_on "Revenir à l'ancien affichage"

        expect(page).to have_css('.champs-grid.champs-grid--stacked')
        expect(instructeur.reload.dossier_layout_preference).to eq('stacked')
      end
    end

    context 'choix déjà fait (persistance DB = grid)' do
      before { instructeur.update!(dossier_layout_preference: 'grid') }

      it 'affiche le toggle JS et bascule la classe visuellement sans reload' do
        visit instructeur_dossier_path(procedure, dossier)

        expect(page).not_to have_css('.fr-callout', text: 'Nouvel affichage')
        expect(page).to have_css('.champs-grid:not(.champs-grid--stacked)')

        toggle = find('button[data-dossier-layout-toggle-target="button"]')
        toggle.click

        expect(page).to have_css('.champs-grid.champs-grid--stacked')
      end
    end
  end

  context 'avec la gate Flipper désactivée' do
    before { instructeur.update!(dossier_layout_preference: nil) }

    it 'force le rendu stacked et ne propose ni bandeau ni toggle' do
      visit instructeur_dossier_path(procedure, dossier)

      expect(page).to have_css('.champs-grid.champs-grid--stacked')
      expect(page).not_to have_css('.fr-callout', text: 'Nouvel affichage des champs')
      expect(page).not_to have_button("Revenir à l'ancien affichage")
      expect(page).not_to have_button('Garder le nouvel affichage')
    end
  end
end
