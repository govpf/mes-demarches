# frozen_string_literal: true

describe 'shared/champs/referentiel_de_polynesie/show', type: :view do
  let(:instructeur) { create(:instructeur) }
  let(:profile) { 'instructeur' }

  # pf: mapping avec 2 colonnes displayable ; seule "Nom" est affichable côté instructeur,
  # "Secret" uniquement côté usager. L'admin a donc configuré un sous-ensemble par profil.
  let(:referentiel_mapping) do
    {
      '$.Nom' => { 'type' => 'string', 'libelle' => 'Nom', 'display_instructeur' => '1', 'display_usager' => '1' },
      '$.Secret' => { 'type' => 'string', 'libelle' => 'Secret', 'display_usager' => '1' }
    }
  end
  let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, libelle: 'Commune', referentiel_mapping: }] }
  let(:procedure) { create(:procedure, types_de_champ_public:) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:types_de_champ) { dossier.revision.types_de_champ_public }
  let(:champ) { dossier.project_champs_public.first }

  before do
    view.extend DossierHelper
    view.extend DossierLinkHelper
    allow(view).to receive(:current_instructeur).and_return(instructeur) if profile == 'instructeur'

    # pf: mode upstream — data plat + value_json calculé (comme après update_external_data!).
    # update_columns pour éviter le wipe de clear_previous_result déclenché par external_id_changed?.
    champ.update!(external_id: '24:1', value: 'Papeete')
    champ.update_columns(
      data: { 'Nom' => 'Papeete', 'Secret' => 'SENSIBLE' },
      value_json: { '$.Nom' => 'Papeete', '$.Secret' => 'SENSIBLE' }
    )
  end

  subject { render ViewableChamp::SectionComponent.new(types_de_champ:, dossier:, demande_seen_at: nil, profile:) }

  context 'profil instructeur' do
    it 'affiche la colonne configurée display_instructeur' do
      expect(subject).to include('Papeete')
      expect(subject).to include('Nom')
    end

    it "n'affiche PAS les colonnes non configurées display_instructeur" do
      expect(subject).not_to include('SENSIBLE')
      expect(subject).not_to include('Secret')
    end
  end

  context 'profil usager' do
    let(:profile) { 'usager' }

    it 'affiche les colonnes configurées display_usager' do
      expect(subject).to include('Papeete')
      expect(subject).to include('SENSIBLE')
    end
  end
end
