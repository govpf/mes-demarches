# frozen_string_literal: true

describe Instructeurs::PfFullTextSearchInputComponent, type: :component do
  let(:instructeur) { create(:instructeur) }
  let(:procedure) { create(:procedure) }
  let(:procedure_presentation) do
    assign_to = create(:assign_to, instructeur:, groupe_instructeur: procedure.defaut_groupe_instructeur)
    assign_to.procedure_presentation_or_default_and_errors.first
  end
  let(:component) { described_class.new(procedure_presentation:, statut: 'tous') }

  subject { render_inline(component) }

  it 'renders a pre-filled search input posting to set_full_text_filter' do
    procedure_presentation.update!(tous_filters: [FilteredColumn.new(column: Columns::PfFullTextColumn.new(procedure_id: procedure.id), filter: { 'operator' => 'match', 'value' => ['dupont'] })])

    input = subject.css('input#pf-full-text-search-input').first
    expect(input).not_to be_nil
    expect(input['value']).to eq('dupont')
    expect(input['type']).to eq('search')
    expect(input['aria-label']).to eq('Rechercher dans cette démarche')
    expect(subject.css('form').first['action']).to include('set_full_text_filter')
  end
end
