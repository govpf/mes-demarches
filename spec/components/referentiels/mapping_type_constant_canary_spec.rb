# frozen_string_literal: true

# pf: canari — le MCP (Mcp::ReferentielMappingService) réutilise cette constante publique
# pour valider la compatibilité de type des cibles de pré-remplissage. Si un bump upstream
# la renomme/déplace/modifie, ce test casse → on adapte le service (blast radius localisé).
RSpec.describe 'Canari MAPPING_TYPE_TO_TYPE_DE_CHAMP' do
  subject { Referentiels::ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP }

  it 'existe et expose les familles de types attendues' do
    expect(subject).to be_a(Hash)
    expect(subject.keys).to include(:string, :integer_number, :decimal_number, :boolean, :date)
    expect(subject[:integer_number]).to include('integer_number')
    expect(subject[:boolean]).to include('yes_no', 'checkbox')
    expect(subject[:string]).to include('text')
  end
end
