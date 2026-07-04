# frozen_string_literal: true

describe 'dossiers/show', type: :view do
  let(:procedure) { create(:procedure, :published, types_de_champ_public: [{ type: :text, libelle: 'Description' }]) }
  let(:dossier) { create(:dossier, :en_construction, procedure: procedure) }
  let(:acls) { PiecesJustificativesService.new(user_profile: create(:instructeur), export_template: nil).acl_for_dossier_export(procedure) }

  before do
    assign(:dossier, dossier)
    assign(:acls, acls)
  end

  subject { render(template: 'dossiers/show', formats: [:pdf]) }

  it 'renders a PDF document' do
    subject
    expect(rendered).to be_present
  end

  context 'when a champ contains mathematical alphanumeric characters (AI-generated bold/italic)' do
    before do
      dossier.champs.first.update(value: 'Texte avec du 𝗴𝗿𝗮𝘀 et de l’𝘪𝘵𝘢𝘭𝘪𝘲𝘶𝘦')
    end

    it 'embeds the math fallback font so the characters are visible' do
      subject
      expect(rendered).to include('NotoSansMath')
    end
  end
end
