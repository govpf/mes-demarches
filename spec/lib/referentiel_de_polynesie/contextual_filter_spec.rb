# frozen_string_literal: true

describe ReferentielDePolynesie::ContextualFilter do
  let(:referentiel) { create(:baserow_referentiel) } # url baserow://24, autocomplete
  let(:filter_config) { { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => pilot_column_id } }
  let(:fields) do
    {
      1 => { name: 'Nom', type: 'text', select_options: [] },
      12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }, { id: 101, value: 'Plants' }] },
      13 => { name: 'Familles', type: 'multiple_select', select_options: [{ id: 200, value: 'Semences' }] },
      14 => { name: 'Code', type: 'text', select_options: [] },
    }
  end

  context 'pilote à la racine (liste déroulante avant le référentiel)' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, referentiel_filter: filter_config },
      ])
    end
    let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
    let(:pilot_column_id) { 'type_de_champ/0' }
    let(:dossier) { create(:dossier, procedure:) }
    let(:filter) { described_class.for(type_de_champ: rdp_tdc, dossier:) }

    # Le stable_id n'est connu qu'après création : on réécrit la config du TDC.
    before do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}"))
    end

    it 'est configuré, valide, et connaît le pilote' do
      expect(filter.configured?).to be(true)
      expect(filter.invalid?).to be(false)
      expect(filter.pilot_tdc).to eq(pilot_tdc)
      expect(filter.pilot_libelle).to eq('Type de produit')
      expect(filter.baserow_field_id).to eq(12)
      expect(filter.baserow_field_name).to eq('Catégorie')
    end

    it 'résout la valeur du pilote depuis le dossier persisté' do
      dossier.project_champ(pilot_tdc).update!(value: 'Semences')
      expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).pilot_value).to eq('Semences')
    end

    it 'a une valeur nil quand le pilote est vide' do
      expect(filter.pilot_value).to be_nil
    end

    describe '#baserow_scope' do
      before { dossier.project_champ(pilot_tdc).update!(value: 'Semences') }
      let(:filter) { described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload) }

      it 'single_select → single_select_equal sur l\'id de l\'option (insensible à la casse)' do
        expect(filter.baserow_scope(fields)).to eq(field_id: 12, type: 'single_select_equal', value: 100)
      end

      it 'multiple_select → multiple_select_has sur l\'id de l\'option' do
        rdp_tdc.update!(referentiel_filter: rdp_tdc.referentiel_filter.merge('baserow_field_id' => 13, 'baserow_field_name' => 'Familles'))
        expect(described_class.for(type_de_champ: rdp_tdc.reload, dossier:).baserow_scope(fields)).to eq(field_id: 13, type: 'multiple_select_has', value: 200)
      end

      it 'texte → equal sur la valeur' do
        rdp_tdc.update!(referentiel_filter: rdp_tdc.referentiel_filter.merge('baserow_field_id' => 14, 'baserow_field_name' => 'Code'))
        expect(described_class.for(type_de_champ: rdp_tdc.reload, dossier:).baserow_scope(fields)).to eq(field_id: 14, type: 'equal', value: 'Semences')
      end

      it 'option introuvable → nil (fail-closed)' do
        dossier.project_champ(pilot_tdc).update!(value: 'Fleurs')
        expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).baserow_scope(fields)).to be_nil
      end

      it 'colonne absente des fields → nil' do
        expect(filter.baserow_scope({})).to be_nil
      end

      it 'pilote vide → nil' do
        dossier.project_champ(pilot_tdc).update!(value: nil)
        expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).baserow_scope(fields)).to be_nil
      end
    end

    describe '#matches_row_data?' do
      before { dossier.project_champ(pilot_tdc).update!(value: 'Semences') }
      let(:filter) { described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload) }

      it('valeur identique') { expect(filter.matches_row_data?({ 'Catégorie' => 'Semences' })).to be(true) }
      it('insensible à la casse') { expect(filter.matches_row_data?({ 'Catégorie' => 'semences' })).to be(true) }
      it('valeur différente') { expect(filter.matches_row_data?({ 'Catégorie' => 'Plants' })).to be(false) }
      it('multiple_select simplifié « A, B »') { expect(filter.matches_row_data?({ 'Catégorie' => 'Plants, Semences' })).to be(true) }
      it('colonne absente → antériorité tolérée') { expect(filter.matches_row_data?({ 'Nom' => 'x' })).to be(true) }
      it('row_data nil → toléré') { expect(filter.matches_row_data?(nil)).to be(true) }

      # pf: le rempart n°1 sélectionne cette ligne (opérateur `equal`) : le découpage sur la
      # virgule ne doit pas la rendre indéposable.
      it 'valeur exacte contenant une virgule (égalité avant découpage)' do
        dossier.project_champ(pilot_tdc).update!(value: 'Semences, bio')
        f = described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload)
        expect(f.matches_row_data?({ 'Catégorie' => 'Semences, bio' })).to be(true)
      end
    end

    describe '#empty_label' do
      it 'demande de renseigner le pilote quand il est vide' do
        expect(filter.empty_label).to eq('Renseignez d’abord « Type de produit »')
      end

      it 'annonce l\'absence de résultat pour la valeur du pilote' do
        dossier.project_champ(pilot_tdc).update!(value: 'Plants')
        expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).empty_label).to eq('Aucun résultat pour « Plants »')
      end
    end

    it 'est invalide si le pilote a disparu de la révision' do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => 'type_de_champ/424242'))
      expect(described_class.for(type_de_champ: rdp_tdc.reload, dossier:).invalid?).to be(true)
    end

    it 'n\'est pas configuré sans referentiel_filter' do
      rdp_tdc.update!(referentiel_filter: nil)
      f = described_class.for(type_de_champ: rdp_tdc.reload, dossier:)
      expect(f.configured?).to be(false)
      expect(f.invalid?).to be(false)
    end
  end

  context 'pilote dans la même ligne d\'un bloc répétable' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        {
          type: :repetition, libelle: 'Produits', children: [
            { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
            { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, referentiel_filter: filter_config },
          ],
        },
      ])
    end
    let(:repetition_tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:pilot_tdc) { procedure.draft_revision.children_of(repetition_tdc).first }
    let(:rdp_tdc) { procedure.draft_revision.children_of(repetition_tdc).second }
    let(:pilot_column_id) { 'type_de_champ/0' }
    let(:dossier) { create(:dossier, procedure:) }

    before do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}"))
    end

    # pf: garde-fou factory — le `deep_dup` de build_types_de_champ dupliquait l'objet
    # Referentiel resté dans les `children`, laissant le champ enfant sans referentiel_id.
    it 'conserve le référentiel du champ enfant de la répétition' do
      expect(rdp_tdc.referentiel_id).to eq(referentiel.id)
      expect(rdp_tdc.table_id).to be_present
    end

    # pf: sans row_id le champ pilote n'est pas projetable : fail-closed, jamais de 500.
    it 'est invalide sans row_id (pilote de la même ligne)' do
      f = described_class.for(type_de_champ: rdp_tdc, dossier:, row_id: nil)
      expect(f.invalid?).to be(true)
      expect(f.pilot_value).to be_nil
    end

    it 'résout le pilote ligne par ligne' do
      row1 = dossier.repetition_row_ids(repetition_tdc).first || dossier.repetition_add_row(repetition_tdc, updated_by: 'test')
      row2 = dossier.repetition_add_row(repetition_tdc, updated_by: 'test')
      dossier.reload
      dossier.project_champ(pilot_tdc, row_id: row1).update!(value: 'Semences')
      dossier.project_champ(pilot_tdc, row_id: row2).update!(value: 'Plants')
      dossier.reload

      expect(described_class.for(type_de_champ: rdp_tdc, dossier:, row_id: row1).pilot_value).to eq('Semences')
      expect(described_class.for(type_de_champ: rdp_tdc, dossier:, row_id: row2).pilot_value).to eq('Plants')
    end
  end

  context 'pilote dans un autre bloc' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :repetition, libelle: 'Autre bloc', children: [{ type: :drop_down_list, libelle: 'Type', options: ['A'] }] },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, referentiel_filter: filter_config },
      ])
    end
    let(:other_pilot) { procedure.draft_revision.children_of(procedure.draft_revision.types_de_champ_public.first).first }
    let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
    let(:pilot_column_id) { 'type_de_champ/0' }
    let(:dossier) { create(:dossier, procedure:) }

    it 'est invalide (sémantique ambiguë : quelle ligne ?)' do
      rdp_tdc.update!(referentiel_filter: filter_config.merge('pilot_column_id' => "type_de_champ/#{other_pilot.stable_id}"))
      f = described_class.for(type_de_champ: rdp_tdc.reload, dossier:)
      expect(f.invalid?).to be(true)
      expect(f.pilot_value).to be_nil
    end
  end
end
