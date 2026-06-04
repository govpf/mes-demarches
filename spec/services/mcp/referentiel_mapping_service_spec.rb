# frozen_string_literal: true

RSpec.describe Mcp::ReferentielMappingService do
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :referentiel_de_polynesie, libelle: 'Entreprise', table_id: '24' },
      { type: :text, libelle: 'Raison sociale cible' },
      { type: :integer_number, libelle: 'Effectif cible' },
    ])
  end
  let(:draft) { procedure.draft_revision }
  let(:referentiel_tdc) { draft.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' } }
  let(:cible_texte) { draft.types_de_champ.find { _1.libelle == 'Raison sociale cible' } }
  let(:cible_nombre) { draft.types_de_champ.find { _1.libelle == 'Effectif cible' } }

  # Baserow renvoie 2 colonnes — clés entières, valeurs avec clés symboles (shape réelle de l'API)
  let(:baserow_fields) { { 1 => { name: 'RaisonSociale', type: 'text' }, 2 => { name: 'Effectif', type: 'number', number_decimal_places: 0 } } }
  # pf: API.engine retourne la CLASSE BaserowAPI (pas une instance) — utiliser class_double
  let(:engine) { class_double(ReferentielDePolynesie::BaserowAPI) }

  before do
    allow(ReferentielDePolynesie::API).to receive(:engine).and_return(engine)
    allow(engine).to receive(:config).with('24').and_return({ 'Table' => '24', 'Token' => 't' })
    allow(engine).to receive(:fields).and_return(baserow_fields)
    # pf: baserow_type_to_mapping_type est une méthode de classe, appelée directement sur
    # ReferentielDePolynesie::BaserowAPI (pas via engine) — pas de stub nécessaire, l'implémentation réelle
    # est de la logique pure (pas de réseau).
  end

  subject(:service) { described_class.new(referentiel_tdc) }

  describe '#colonnes' do
    it 'liste les colonnes Baserow avec leur type de mapping' do
      cols = service.colonnes
      expect(cols).to contain_exactly(
        { nom: 'RaisonSociale', type_mapping: 'string' },
        { nom: 'Effectif', type_mapping: 'integer_number' }
      )
    end

    it 'lève si Baserow est injoignable' do
      allow(ReferentielDePolynesie::API).to receive(:engine).and_return(nil)
      expect { service.colonnes }.to raise_error(Mcp::ReferentielMappingService::BaserowIndisponible)
    end
  end

  describe '#configurer!' do
    it 'pose un prefill vers une cible compatible et située après' do
      service.configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: cible_texte.stable_id.to_s }])
      mapping = referentiel_tdc.reload.safe_referentiel_mapping
      expect(mapping['$.RaisonSociale']['prefill']).to eq('1')
      expect(mapping['$.RaisonSociale']['prefill_stable_id']).to eq(cible_texte.stable_id.to_s)
      expect(mapping['$.RaisonSociale']['type']).to eq('string')
    end

    it 'pose un rapatriement usager/instructeur' do
      service.configurer!([{ colonne: 'Effectif', display_usager: true, display_instructeur: true }])
      mapping = referentiel_tdc.reload.safe_referentiel_mapping
      expect(mapping['$.Effectif']).to include('display_usager' => '1', 'display_instructeur' => '1')
    end

    it 'refuse une colonne inconnue de Baserow' do
      expect { service.configurer!([{ colonne: 'Inexistante', display_usager: true }]) }
        .to raise_error(Mcp::ReferentielMappingService::ColonneInconnue, /Inexistante/)
    end

    it 'refuse un prefill vers une cible de type incompatible' do
      # RaisonSociale (string) -> cible_nombre (integer_number) : incompatible
      expect { service.configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: cible_nombre.stable_id.to_s }]) }
        .to raise_error(Mcp::ReferentielMappingService::CibleInvalide, /compatible/)
    end

    it 'refuse un prefill vers un champ situé AVANT le référentiel' do
      # créer une procédure où la cible précède le référentiel
      proc2 = create(:procedure, types_de_champ_public: [
        { type: :text, libelle: 'Avant' },
        { type: :referentiel_de_polynesie, libelle: 'Ref', table_id: '24' },
      ])
      ref = proc2.draft_revision.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' }
      avant = proc2.draft_revision.types_de_champ.find { _1.libelle == 'Avant' }
      expect { described_class.new(ref).configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: avant.stable_id.to_s }]) }
        .to raise_error(Mcp::ReferentielMappingService::CibleInvalide)
    end

    it 'nettoie les entrées dont la colonne a disparu de Baserow' do
      referentiel_tdc.update!(referentiel_mapping: { '$.ColonneDisparue' => { 'type' => 'string', 'display_usager' => '1' } })
      service.configurer!([{ colonne: 'RaisonSociale', display_usager: true }])
      mapping = referentiel_tdc.reload.safe_referentiel_mapping
      expect(mapping).not_to have_key('$.ColonneDisparue')
      expect(mapping).to have_key('$.RaisonSociale')
    end
  end
end
