# frozen_string_literal: true

# pf: lot C DLNUF — préremplissage d'une pièce justificative par référence MD
describe 'Référentiel DLNUF — préremplissage des pièces justificatives', js: true do
  let(:user) { create(:user) }
  let(:user_dossier) { user.dossiers.find_by(revision: procedure.published_revision) }
  let(:pj_stable_id) { 501 }

  let(:procedure_source) { create(:procedure, :published, types_de_champ_public: [{ type: :piece_justificative, libelle: 'Statuts source' }]) }
  let(:source) { create(:dossier, :brouillon, procedure: procedure_source, user:) }
  let(:tdc_source) { procedure_source.active_revision.types_de_champ_public.first }
  let(:reference) { "md:#{source.id}:#{tdc_source.stable_id}" }

  let(:referentiel) { create(:baserow_referentiel, :autocomplete, url: 'baserow://24') }
  let(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      {
        type: :referentiel_de_polynesie, libelle: 'Mon association', table_id: '24', referentiel:,
        referentiel_mapping: { '$.Statuts' => { 'type' => 'piece_justificative', 'prefill' => '1', 'prefill_stable_id' => pj_stable_id.to_s } },
      },
      { type: :piece_justificative, libelle: 'Statuts', stable_id: pj_stable_id },
    ])
  end
  let(:scopes) { [{ field_id: 9, type: 'equal', value: user.email.downcase }] }

  before do
    champ = source.champ_for_update(tdc_source, updated_by: :api)
    champ.piece_justificative_file.attach(io: Rails.root.join('spec/fixtures/files/file.pdf').open, filename: 'statuts.pdf', content_type: 'application/pdf')
    champ.save!
    source.update_columns(state: 'en_construction', depose_at: Time.zone.now, en_construction_at: Time.zone.now)

    allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with('24').and_return({ field_id: 9, field_name: 'Email', field_type: 'email' })
    allow(ReferentielDePolynesie::API).to receive(:search_with_data)
      .with('24', anything, drop_down_other: anything, scopes:)
      .and_return([
        { label: 'Association Manuia', value: '24:7', row_data: { 'Nom' => 'Association Manuia', 'Email' => user.email, 'Statuts' => reference } },
        { label: 'Association Here', value: '24:8', row_data: { 'Nom' => 'Association Here', 'Email' => user.email, 'Statuts' => '' } },
      ])
  end

  scenario 'la sélection de sa ligne rattache les statuts de son autre dossier' do
    log_in
    find_field('Mon association').click
    find('.fr-menu__item', text: 'Association Manuia').click

    within('.editable-champ-piece_justificative') do
      expect(page).to have_text('statuts.pdf')
      expect(page).to have_text('Donnée remplie automatiquement.')
      expect(page).to have_button('Supprimer', title: 'Supprimer le fichier statuts.pdf')
    end
  end

  scenario 'un fichier ajouté par l’usager n’est pas remplacé par une sélection' do
    log_in
    find_field('Statuts').attach_file(Rails.root.join('spec/fixtures/files/RIB.pdf'))
    expect(page).to have_text('RIB.pdf')

    find_field('Mon association').click
    find('.fr-menu__item', text: 'Association Manuia').click
    wait_for_autosave

    within('.editable-champ-piece_justificative') do
      expect(page).to have_text('RIB.pdf')
      expect(page).to have_no_text('statuts.pdf')
    end
  end

  private

  def log_in
    login_as user, scope: :user
    visit "/commencer/#{procedure.path}"
    click_on 'Commencer la démarche'
    fill_in('Prénom', with: 'prenom', visible: true)
    fill_in('Nom', with: 'Nom', visible: true)
    within('#identite-form') { click_on 'Continuer' }
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))
    find('.dom-ready')
  end
end
