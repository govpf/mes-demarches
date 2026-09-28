# frozen_string_literal: true

# pf: une colonne système (ex. « Date de création ») saisie dans l'éditeur de
# formule est enregistrée sous son identifiant ({self_created_at}), acceptée par
# la validation, puis réaffichée par son libellé au rechargement de la page.
describe 'Formule référençant une colonne système', js: true do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :formule, libelle: 'Année de création' }]) }
  let(:administrateur) { procedure.administrateurs.first }

  before do
    Flipper.enable(:formule, procedure)
    login_as administrateur.user, scope: :user
    visit champs_admin_procedure_path(procedure)
  end

  scenario 'la date de création est enregistrée par identifiant et réaffichée par libellé' do
    fill_in 'Expression de la formule', with: 'ANNEE({Date de création})'
    # conversion libellés → identifiants côté JS (debounce) avant le blur
    expect(page).to have_css("input[type=hidden][name$='[formule_expression]'][value='ANNEE({self_created_at})']", visible: false)
    find('body').click
    expect(page).to have_content('Formulaire enregistré')

    formule_tdc = procedure.reload.draft_revision.types_de_champ_public.find(&:formule?)
    expect(formule_tdc.formule_expression).to eq('ANNEE({self_created_at})')

    visit champs_admin_procedure_path(procedure)
    expect(page).to have_field('Expression de la formule', with: 'ANNEE({Date de création})')
    expect(page).to have_no_content('Colonne inconnue')
    expect(page).to have_no_content('self_created_at')
  end
end
