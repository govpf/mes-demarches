# frozen_string_literal: true

describe 'Instructeur consulte un champ TeFenua', js: true do
  let(:instructeur) { create(:instructeur) }
  let(:types_de_champ_public) { [{ type: :te_fenua, libelle: 'Carte TeFenua', options: { parcelles: '1' } }] }
  let(:procedure) { create(:procedure, :published, types_de_champ_public:, instructeurs: [instructeur]) }
  let(:dossier) { create(:dossier, :en_construction, procedure:) }
  let(:polygon) do
    { type: 'Polygon', coordinates: [[[-149.56, -17.53], [-149.55, -17.53], [-149.55, -17.54], [-149.56, -17.53]]] }
  end
  let(:payload) { '<img src=x onerror="window.teFenuaInjected=1">' }

  before do
    # La valeur est écrite sans callbacks pour simuler une donnée déjà stockée
    # avant le nettoyage serveur : seul le rendu JS doit la neutraliser.
    value = {
      parcelles: {
        type: 'FeatureCollection',
        features: [{ type: 'Feature', id: "parcelles 1'); window.teFenuaInjectedId=1; ('", geometry: polygon, properties: { label: payload } }],
      },
    }.to_json
    dossier.champs.first.update_column(:value, value)

    login_as(instructeur.user, scope: :user)
  end

  scenario 'les libellés du GeoJSON sont affichés comme du texte, jamais exécutés' do
    visit instructeur_dossier_path(procedure, dossier)

    expect(page).to have_css('.te-fenua[data-initialized="true"]', wait: 10)
    expect(page).to have_css('.geo-areas li', text: payload)
    expect(page).not_to have_css('.geo-areas li img[src="x"]')

    find('.geo-areas li button').click

    expect(page.evaluate_script('window.teFenuaInjected')).to be_nil
    expect(page.evaluate_script('window.teFenuaInjectedId')).to be_nil
  end
end
