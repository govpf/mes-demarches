# frozen_string_literal: true

require 'rails_helper'

describe 'As an administrateur I can add lexpol champ', js: true do
  include ActionView::RecordIdentifier

  let(:administrateur) { procedure.administrateurs.first }
  let(:procedure) { create(:procedure, :with_service) }

  before do
    login_as administrateur.user, scope: :user
    visit champs_admin_procedure_path(procedure)
  end

  context 'lexpol enabled' do
    before { Flipper.enable(:lexpol, procedure) }
    before do
      allow_any_instance_of(APILexpol).to receive(:get_models).and_return([["ATRRIB CPPA APPN JET SKI 2024", "600203"], ["Test Monituru 1", "598706"]])
    end

    it "Add lexpol champ and see models list" do
      add_champ

      select('Lexpol', from: 'Type de champ')
      fill_in 'Libellé du champ', with: 'Libellé de champ lexpol', fill_options: { clear: :backspace }

      wait_until { procedure.draft_types_de_champ_public.first.type_champ == TypeDeChamp.type_champs.fetch(:lexpol) }
      expect(page).to have_content('Formulaire enregistré')

      expect(page).to have_content('Sélectionner un modèle Lexpol')
      expect(page).to have_content('Variables Lexpol')

      within('select[name*="lexpol_modele"]') do
        expect(page).to have_content('ATRRIB CPPA APPN JET SKI 2024')
        expect(page).to have_content('Test Monituru 1')
        expect(page).to have_content('Sélectionnez un modèle')
      end
    end
  end
end
