# frozen_string_literal: true

# pf: backport upstream 3570fe70b3 (règle sur ChampValue, l’ancien chemin encore utilisé en PF)

RSpec.describe Dossiers::InvalidIneligibiliteRulesComponent, type: :component do
  include Logic

  let(:procedure) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :checkbox, libelle: 'certifie', stable_id: 1 },
      { type: :text, libelle: 'texte', stable_id: 2 },
    ])
  end
  let(:dossier) { create(:dossier, procedure:) }
  let(:checkbox) { dossier.project_champs_public.first }
  let(:texte) { dossier.project_champs_public.last }
  let(:updated_champ) { nil }
  let(:component) { described_class.new(dossier:, updated_champ:) }

  subject { render_inline(component).to_html }

  before do
    procedure.published_revision.update!(
      ineligibilite_enabled: true,
      ineligibilite_message: 'non éligible',
      ineligibilite_rules: ds_eq(champ_value(1), constant(false))
    )
  end

  context 'on a page render, the rules being met by the untouched checkbox' do
    it 'renders the modal closed' do
      expect(dossier.can_passer_en_construction?).to be false
      expect(subject).to have_selector("[data-fr-opened='false']")
      expect(subject).to have_content('non éligible')
    end
  end

  context 'after the edit of a champ the rules do not read' do
    let(:updated_champ) { texte }

    it { is_expected.to have_selector("[data-fr-opened='false']") }
  end

  context 'after the edit of the checkbox the rules read' do
    let(:updated_champ) { checkbox }

    it { is_expected.to have_selector("[data-fr-opened='true']") }

    context 'when the edit made the dossier eligible' do
      before { checkbox.update!(value: 'true') }

      it { is_expected.to have_selector("[data-fr-opened='false']") }
    end
  end

  context 'when ineligibilite is disabled' do
    before { procedure.published_revision.update!(ineligibilite_enabled: false) }

    it { is_expected.to be_empty }
  end
end
