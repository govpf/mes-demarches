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

  # pf: stub `available_tables` pour les tests de découverte (pas de réseau)
  let(:available_tables) { [{ name: 'Communes', id: 24 }, { name: 'Entreprises', id: 42 }] }

  describe '#tables_disponibles' do
    before do
      allow(ReferentielDePolynesie::API).to receive(:available_tables).and_return(available_tables)
    end

    it 'délègue à ReferentielDePolynesie::API.available_tables' do
      expect(service.tables_disponibles).to eq(available_tables)
    end
  end

  describe '#colonnes_pour_table' do
    it 'liste les colonnes de la table donnée avec leur type de mapping' do
      allow(engine).to receive(:config).with('99').and_return({ 'Table' => '99', 'Token' => 't' })
      cols = service.colonnes_pour_table('99')
      expect(cols).to contain_exactly(
        { nom: 'RaisonSociale', type_mapping: 'string' },
        { nom: 'Effectif', type_mapping: 'integer_number' }
      )
    end

    it 'lève BaserowIndisponible si Baserow est injoignable' do
      allow(ReferentielDePolynesie::API).to receive(:engine).and_return(nil)
      expect { service.colonnes_pour_table('24') }.to raise_error(Mcp::ReferentielMappingService::BaserowIndisponible)
    end

    it '#colonnes délègue à colonnes_pour_table(@tdc.table_id)' do
      cols = service.colonnes
      expect(cols).to contain_exactly(
        { nom: 'RaisonSociale', type_mapping: 'string' },
        { nom: 'Effectif', type_mapping: 'integer_number' }
      )
    end
  end

  describe '#configurer_source!' do
    it 'crée le BaserowReferentiel (mode autocomplete + hint + table_id)' do
      service.configurer_source!(table_id: '24', mode: 'autocomplete', hint: 'Saisissez le nom de votre commune')
      ref = referentiel_tdc.reload.referentiel
      expect(ref).to be_a(Referentiels::BaserowReferentiel)
      expect(ref.autocomplete?).to be(true)
      expect(ref.hint).to eq('Saisissez le nom de votre commune')
      expect(ref.table_id).to eq('24')
      expect(referentiel_tdc.options['table_id']).to eq('24') # dual-write legacy
    end

    it 'purge le mapping quand la table change' do
      service.configurer_source!(table_id: '24', mode: 'exact_match')
      referentiel_tdc.update!(referentiel_mapping: { '$.X' => { 'type' => 'string', 'display_usager' => '1' } })
      allow(engine).to receive(:config).with('99').and_return({ 'Table' => '99', 'Token' => 't' })
      described_class.new(referentiel_tdc.reload).configurer_source!(table_id: '99', mode: 'exact_match')
      expect(referentiel_tdc.reload.safe_referentiel_mapping).to be_empty
    end

    it 'refuse un mode invalide' do
      expect { service.configurer_source!(table_id: '24', mode: 'xxx') }
        .to raise_error(described_class::SourceInvalide, /mode/)
    end

    it 'met à jour le referentiel existant si on reconfigure sans changer de table' do
      service.configurer_source!(table_id: '24', mode: 'exact_match')
      referentiel_tdc.update!(referentiel_mapping: { '$.Y' => { 'type' => 'string', 'display_usager' => '1' } })
      described_class.new(referentiel_tdc.reload).configurer_source!(table_id: '24', mode: 'autocomplete', hint: 'Nouveau hint')
      ref = referentiel_tdc.reload.referentiel
      expect(ref.autocomplete?).to be(true)
      expect(ref.hint).to eq('Nouveau hint')
      # le mapping ne doit PAS être purgé si l'url n'a pas changé
      expect(referentiel_tdc.reload.safe_referentiel_mapping).not_to be_empty
    end

    it 'lève SourceInvalide si table_id est absent (referentiel non configured?)' do
      # On crée un service sur un tdc sans table_id
      tdc_sans_table = draft.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' }
      tdc_sans_table.update_column(:options, {})
      expect { described_class.new(tdc_sans_table).configurer_source!(mode: 'autocomplete') }
        .to raise_error(described_class::SourceInvalide, /table_id/)
    end
  end

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

    it 'refuse un prefill quand le référentiel est imbriqué dans une répétition' do
      proc_rep = create(:procedure, types_de_champ_public: [
        {
          type: :repetition, libelle: 'Lignes', children: [
            { type: :referentiel_de_polynesie, libelle: 'Ref imbriqué', table_id: '24' },
            { type: :text, libelle: 'Cible imbriquée' },
          ],
        },
      ])
      ref = proc_rep.draft_revision.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' }
      cible = proc_rep.draft_revision.types_de_champ.find { _1.libelle == 'Cible imbriquée' }
      svc = described_class.new(ref)
      expect { svc.configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: cible.stable_id.to_s }]) }
        .to raise_error(described_class::CibleInvalide, /répétition/)
    end

    context 'référentiel privé (annotation)' do
      let(:procedure) do
        create(:procedure,
          types_de_champ_public: [],
          types_de_champ_private: [
            { type: :referentiel_de_polynesie, libelle: 'Ref privé', table_id: '24' },
            { type: :text, libelle: 'Annotation cible' },
          ])
      end
      let(:ref_prive) { draft.types_de_champ.find { _1.type_champ == 'referentiel_de_polynesie' } }
      let(:annotation_cible) { draft.types_de_champ.find { _1.libelle == 'Annotation cible' } }

      it 'autorise le prefill vers une annotation privée située après' do
        described_class.new(ref_prive).configurer!([{ colonne: 'RaisonSociale', prefill_stable_id: annotation_cible.stable_id.to_s }])
        expect(ref_prive.reload.safe_referentiel_mapping['$.RaisonSociale']['prefill_stable_id']).to eq(annotation_cible.stable_id.to_s)
      end
    end
  end
end
