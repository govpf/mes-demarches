# frozen_string_literal: true

describe FormulaColumnResolver do
  describe 'résolution des références scalaires (cas existants — non régression)' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :text, libelle: 'Référence' },
        { type: :integer_number, libelle: 'Montant' },
      ])
    end
    let(:revision) { procedure.active_revision || procedure.draft_revision }
    let(:resolver) { described_class.new(revision) }
    let(:reference_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Référence' } }
    let(:montant_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Montant' } }

    it 'résout un tdc<N> vers la Column champ scalaire' do
      result = resolver.resolve("tdc#{reference_tdc.stable_id}")
      expect(result).to be_a(Columns::ChampColumn)
      expect(result.stable_id).to eq(reference_tdc.stable_id)
    end

    it 'résout une référence inconnue vers nil' do
      expect(resolver.resolve('tdc99999999')).to be_nil
    end

    it 'résout une colonne système' do
      expect(resolver.resolve('dossier_number')).not_to be_nil
    end
  end

  describe 'résolution des blocs répétables (étape A — formules-agrégat)' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :text, libelle: 'Référence dossier' },
        {
          type: :repetition, libelle: 'Lignes de facture', children: [
            { type: :text, libelle: 'Désignation' },
            { type: :integer_number, libelle: 'Prix HT' },
            { type: :integer_number, libelle: 'Quantité' },
          ],
        },
      ])
    end
    let(:revision) { procedure.active_revision || procedure.draft_revision }
    let(:resolver) { described_class.new(revision) }
    let(:bloc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Lignes de facture' } }
    let(:prix_ht_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Prix HT' } }
    let(:quantite_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Quantité' } }

    context 'référence au bloc seul {tdc<bloc>}' do
      it 'résout vers une RepetitionRef qui porte le TDC bloc' do
        result = resolver.resolve("tdc#{bloc_tdc.stable_id}")
        expect(result).to be_a(FormulaColumnResolver::RepetitionRef)
        expect(result.bloc_tdc.stable_id).to eq(bloc_tdc.stable_id)
        expect(result.bloc_tdc).to be_repetition
      end
    end

    context 'référence à un sous-champ {tdc<bloc>/sub_<sub>}' do
      it 'résout vers une RepetitionSubChampRef qui porte bloc + sous-tdc' do
        ref = "tdc#{bloc_tdc.stable_id}/sub_#{prix_ht_tdc.stable_id}"
        result = resolver.resolve(ref)

        expect(result).to be_a(FormulaColumnResolver::RepetitionSubChampRef)
        expect(result.bloc_tdc.stable_id).to eq(bloc_tdc.stable_id)
        expect(result.sub_tdc.stable_id).to eq(prix_ht_tdc.stable_id)
      end

      it 'fonctionne pour chaque sous-champ du bloc' do
        ref = "tdc#{bloc_tdc.stable_id}/sub_#{quantite_tdc.stable_id}"
        result = resolver.resolve(ref)

        expect(result).to be_a(FormulaColumnResolver::RepetitionSubChampRef)
        expect(result.sub_tdc.stable_id).to eq(quantite_tdc.stable_id)
      end
    end

    context 'référence à un sous-champ d\'un bloc inconnu' do
      it 'résout vers nil' do
        expect(resolver.resolve('tdc99999/sub_42')).to be_nil
      end
    end

    context 'référence à un sous-champ inexistant dans un bloc connu' do
      it 'résout vers nil' do
        expect(resolver.resolve("tdc#{bloc_tdc.stable_id}/sub_99999")).to be_nil
      end
    end

    context 'co-existence avec la résolution scalaire des sous-TDC' do
      it 'permet aussi la résolution directe d\'un sous-TDC via tdc<sub> (formules-ligne)' do
        # Une formule-ligne dans le bloc utilise tdc<sub> directement.
        # Le chantier #3 n'altère pas ce comportement.
        result = resolver.resolve("tdc#{prix_ht_tdc.stable_id}")
        expect(result).to be_a(Columns::ChampColumn)
        expect(result.stable_id).to eq(prix_ht_tdc.stable_id)
      end
    end
  end

  describe '#resolve_with_path' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :commune_de_polynesie, libelle: 'Code postal' },
        {
          type: :repetition, libelle: 'Lignes', children: [
            { type: :integer_number, libelle: 'Prix HT' },
          ],
        },
      ])
    end
    let(:revision) { procedure.active_revision || procedure.draft_revision }
    let(:resolver) { described_class.new(revision) }
    let(:commune_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Code postal' } }
    let(:bloc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Lignes' } }
    let(:prix_ht_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Prix HT' } }

    it 'résout un sous-champ de bloc vers [RepetitionSubChampRef, nil]' do
      ref = "tdc#{bloc_tdc.stable_id}/sub_#{prix_ht_tdc.stable_id}"
      target, path = resolver.resolve_with_path(ref)

      expect(target).to be_a(FormulaColumnResolver::RepetitionSubChampRef)
      expect(path).to be_nil
    end

    it 'préserve le contrat [Column, :path_symbol] pour les références non-bloc' do
      # Cas historique : {tdc<N>/path} où le TDC n'est PAS un bloc répétable
      # (ex: commune, DN, dropdown lié...). Le path doit être retourné comme
      # symbole, et la résolution du column_id seul ne doit pas être altérée.
      ref = "tdc#{commune_tdc.stable_id}/commune"
      target, path = resolver.resolve_with_path(ref)

      # target peut être un Columns::* selon le type ; ce qui compte :
      # ce n'est PAS un RepetitionSubChampRef, et le path est un Symbol.
      expect(target).not_to be_a(FormulaColumnResolver::RepetitionSubChampRef)
      expect(path).to be_a(Symbol)
      expect(path).to eq(:commune)
    end
  end
end
