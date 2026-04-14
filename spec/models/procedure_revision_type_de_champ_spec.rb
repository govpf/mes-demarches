# frozen_string_literal: true

describe ProcedureRevisionTypeDeChamp do
  describe '#upper_coordinates' do
    context 'when the coordinate is in a bloc bellow another coordinate' do
      let(:procedure) do
        create(:procedure,
               types_de_champ_public: [
                 { libelle: 'l1' },
                 {
                   type: :repetition, children: [
                     { libelle: 'l2.1' },
                     { libelle: 'l2.2' }
                   ]
                 }
               ])
      end

      let(:l2_2) do
        procedure
          .draft_revision
          .revision_types_de_champ.joins(:type_de_champ)
          .find_by(type_de_champ: { libelle: 'l2.2' })
      end

      it { expect(l2_2.upper_coordinates.map(&:libelle)).to match_array(["l1", "l2.1"]) }
    end

    context 'when the coordinate is an annotation' do
      let(:procedure) do
        create(:procedure,
               types_de_champ_private: [
                 { libelle: 'a1' },
                 { libelle: 'a2' }
               ],
               types_de_champ_public: [
                 { libelle: 'l1' },
                 {
                   type: :repetition, libelle: 'l2', children: [
                     { libelle: 'l2.1' },
                     { libelle: 'l2.2' }
                   ]
                 }
               ])
      end

      let(:a2) do
        procedure
          .draft_revision
          .revision_types_de_champ.joins(:type_de_champ)
          .find_by(type_de_champ: { libelle: 'a2' })
      end

      it { expect(a2.upper_coordinates.map(&:libelle)).to match_array(["l1", "l2", "a1"]) }
    end
  end

  # pf: Tests for formula methods with repetitions
  describe 'Formula methods with repetitions' do
    describe '#in_repetition?' do
      context 'formula in repetition' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   {
                     type: :repetition, libelle: 'Bloc', children: [
                       { type: :formule, libelle: 'Formule' }
                     ]
                   }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        it 'returns true for direct child of repetition' do
          expect(formula_coordinate.in_repetition?).to be true
        end
      end

      context 'formula not in repetition' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   { type: :formule, libelle: 'Formule' }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        it 'returns false for top-level formula' do
          expect(formula_coordinate.in_repetition?).to be false
        end
      end
    end

    describe '#available_columns_for_formula' do
      context 'formula in repetition' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   { type: :integer_number, libelle: 'Parent 1' },
                   { type: :integer_number, libelle: 'Parent 2' },
                   {
                     type: :repetition, libelle: 'Bloc', children: [
                       { type: :integer_number, libelle: 'Sibling' },
                       { type: :formule, libelle: 'Formule' }
                     ]
                   }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        it 'returns only PARENT fields (before repetition), not siblings' do
          available = formula_coordinate.available_columns_for_formula

          # Doit contenir Parent 1, Parent 2 (et métadonnées système)
          labels = available.map(&:label)
          expect(labels).to include('Parent 1', 'Parent 2')

          # Ne doit PAS contenir Sibling (pas dans available_columns_for_formula, uniquement dans _editor)
          expect(labels).not_to include('Sibling')
        end
      end

      context 'formula not in repetition' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   { type: :integer_number, libelle: 'Champ 1' },
                   { type: :integer_number, libelle: 'Champ 2' },
                   { type: :formule, libelle: 'Formule' }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        it 'returns all preceding fields (classic behavior)' do
          available = formula_coordinate.available_columns_for_formula

          labels = available.map(&:label)
          expect(labels).to include('Champ 1', 'Champ 2')
        end
      end
    end

    describe '#available_columns_for_formula_editor' do
      context 'formula in repetition' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   { type: :integer_number, libelle: 'Parent' },
                   {
                     type: :repetition, libelle: 'Bloc', children: [
                       { type: :integer_number, libelle: 'Sibling' },
                       { type: :formule, libelle: 'Formule' }
                     ]
                   }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        it 'returns parents + siblings (for UI editor)' do
          available = formula_coordinate.available_columns_for_formula_editor

          labels = available.map(&:label)
          expect(labels).to include('Parent', 'Sibling')
        end
      end

      context 'formula not in repetition' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   { type: :integer_number, libelle: 'Champ 1' },
                   { type: :formule, libelle: 'Formule' }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        it 'returns same as available_columns_for_formula (no siblings)' do
          available_editor = formula_coordinate.available_columns_for_formula_editor
          available_classic = formula_coordinate.available_columns_for_formula

          expect(available_editor.map(&:label)).to eq(available_classic.map(&:label))
        end
      end
    end

    describe '#available_in_repetition_context?' do
      let(:procedure) do
        create(:procedure,
               types_de_champ_public: [
                 { type: :integer_number, libelle: 'Parent' },
                 {
                   type: :repetition, libelle: 'Bloc', children: [
                     { type: :integer_number, libelle: 'Sibling' },
                     { type: :formule, libelle: 'Formule' },
                     { type: :integer_number, libelle: 'Suivant' }
                   ]
                 }
               ])
      end

      let(:formula_coordinate) do
        procedure
          .draft_revision
          .revision_types_de_champ.joins(:type_de_champ)
          .find_by(type_de_champ: { libelle: 'Formule' })
      end

      let(:sibling_tdc) do
        procedure.draft_revision.types_de_champ.find { _1.libelle == 'Sibling' }
      end

      let(:parent_tdc) do
        procedure.draft_revision.types_de_champ.find { _1.libelle == 'Parent' }
      end

      let(:following_tdc) do
        procedure.draft_revision.types_de_champ.find { _1.libelle == 'Suivant' }
      end

      it 'accepts sibling field (same row, preceding position)' do
        column_ref = "tdc#{sibling_tdc.stable_id}"
        expect(formula_coordinate.available_in_repetition_context?(column_ref)).to be true
      end

      it 'accepts parent field (outside repetition)' do
        column_ref = "tdc#{parent_tdc.stable_id}"
        expect(formula_coordinate.available_in_repetition_context?(column_ref)).to be true
      end

      it 'rejects sibling field with later position' do
        column_ref = "tdc#{following_tdc.stable_id}"
        expect(formula_coordinate.available_in_repetition_context?(column_ref)).to be false
      end
    end

    describe '#check_collision_warning' do
      context 'when field exists in both row and parent' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   { type: :integer_number, libelle: 'Prix' },
                   {
                     type: :repetition, libelle: 'Bloc', children: [
                       { type: :integer_number, libelle: 'Prix' },
                       { type: :formule, libelle: 'Formule' }
                     ]
                   }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        let(:sibling_prix) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .where(type_de_champ: { libelle: 'Prix' })
            .where.not(parent_id: nil)
            .first
            .type_de_champ
        end

        it 'adds warning when field exists in both row and parent' do
          errors_collector = ActiveModel::Errors.new(sibling_prix)
          column_ref = "tdc#{sibling_prix.stable_id}"

          formula_coordinate.check_collision_warning(column_ref, errors_collector)

          expect(errors_collector[:formule_expression]).to include(match(/⚠️.*Prix.*existe à la fois/))
        end
      end

      context 'when field only in row' do
        let(:procedure) do
          create(:procedure,
                 types_de_champ_public: [
                   {
                     type: :repetition, libelle: 'Bloc', children: [
                       { type: :integer_number, libelle: 'Prix' },
                       { type: :formule, libelle: 'Formule' }
                     ]
                   }
                 ])
        end

        let(:formula_coordinate) do
          procedure
            .draft_revision
            .revision_types_de_champ.joins(:type_de_champ)
            .find_by(type_de_champ: { libelle: 'Formule' })
        end

        let(:sibling_prix) do
          procedure.draft_revision.types_de_champ.find { _1.libelle == 'Prix' }
        end

        it 'does not warn when field only in row' do
          errors_collector = ActiveModel::Errors.new(sibling_prix)
          column_ref = "tdc#{sibling_prix.stable_id}"

          formula_coordinate.check_collision_warning(column_ref, errors_collector)

          expect(errors_collector[:formule_expression]).to be_empty
        end
      end
    end
  end
end
