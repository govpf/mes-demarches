describe ProcedureRevision do
  let(:draft) { procedure.draft_revision }
  let(:type_de_champ_public) { draft.types_de_champ_public.first }
  let(:type_de_champ_private) { draft.types_de_champ_private.first }
  let(:type_de_champ_repetition) do
    repetition = draft.types_de_champ_public.repetition.first
    repetition.update(stable_id: 3333)
    repetition
  end

  describe '#add_type_de_champ' do
    # tdc: public: text, repetition ; private: text ; +1 text child of repetition
    let(:procedure) { create(:procedure, :with_type_de_champ, :with_type_de_champ_private, :with_repetition) }
    let(:text_params) { { type_champ: :text, libelle: 'text' } }
    let(:tdc_params) { text_params }
    let(:last_coordinate) { draft.revision_types_de_champ.last }

    subject { draft.add_type_de_champ(tdc_params) }

    context 'with a text tdc' do
      it 'public' do
        expect { subject }.to change { draft.types_de_champ_public.size }.from(2).to(3)
        expect(draft.types_de_champ_public.last).to eq(subject)

        expect(last_coordinate.position).to eq(2)
        expect(last_coordinate.type_de_champ).to eq(subject)
      end
    end

    context 'with a private tdc' do
      let(:tdc_params) { text_params.merge(private: true) }

      it { expect { subject }.to change { draft.types_de_champ_private.count }.from(1).to(2) }
    end

    context 'with a repetition child' do
      let(:tdc_params) { text_params.merge(parent_id: type_de_champ_repetition.stable_id) }

      it do
        expect { subject }.to change { draft.reload.types_de_champ.count }.from(4).to(5)
        expect(draft.children_of(type_de_champ_repetition).last).to eq(subject)

        expect(last_coordinate.position).to eq(1)

        parent_coordinate = draft.revision_types_de_champ.find_by(type_de_champ: type_de_champ_repetition)
        expect(last_coordinate.parent).to eq(parent_coordinate)
      end
    end

    context 'when a libelle is missing' do
      let(:tdc_params) { text_params.except(:libelle) }

      it { expect(subject.errors.full_messages).to eq(["Libelle doit être rempli"]) }
    end

    context 'when a parent is incorrect' do
      let(:tdc_params) { text_params.merge(parent_id: 123456789) }

      it { expect(subject.errors.full_messages).not_to be_empty }
    end
  end

  describe '#move_type_de_champ' do
    let(:procedure) { create(:procedure, :with_type_de_champ, types_de_champ_count: 4) }
    let(:last_type_de_champ) { draft.types_de_champ_public.last }

    context 'with 4 types de champ publiques' do
      it 'move down' do
        expect(draft.types_de_champ_public.index(type_de_champ_public)).to eq(0)

        draft.move_type_de_champ(type_de_champ_public.stable_id, 2)
        draft.reload

        expect(draft.types_de_champ_public.index(type_de_champ_public)).to eq(2)
        expect(draft.procedure.types_de_champ_for_procedure_presentation.not_repetition.index(type_de_champ_public)).to eq(2)
      end

      it 'move up' do
        expect(draft.types_de_champ_public.index(last_type_de_champ)).to eq(3)

        draft.move_type_de_champ(last_type_de_champ.stable_id, 0)
        draft.reload

        expect(draft.types_de_champ_public.index(last_type_de_champ)).to eq(0)
        expect(draft.procedure.types_de_champ_for_procedure_presentation.not_repetition.index(last_type_de_champ)).to eq(0)
      end
    end

    context 'with a champ repetition repetition' do
      let(:procedure) { create(:procedure, :with_repetition) }

      let!(:second_child) do
        draft.add_type_de_champ({
          type_champ: TypeDeChamp.type_champs.fetch(:text),
          libelle: "second child",
          parent_id: type_de_champ_repetition.stable_id
        })
      end

      let!(:last_child) do
        draft.add_type_de_champ({
          type_champ: TypeDeChamp.type_champs.fetch(:text),
          libelle: "last child",
          parent_id: type_de_champ_repetition.stable_id
        })
      end

      it 'move down' do
        expect(draft.children_of(type_de_champ_repetition).index(second_child)).to eq(1)

        draft.move_type_de_champ(second_child.stable_id, 2)

        expect(draft.children_of(type_de_champ_repetition).index(second_child)).to eq(2)
      end

      it 'move up' do
        expect(draft.children_of(type_de_champ_repetition).index(last_child)).to eq(2)

        draft.move_type_de_champ(last_child.stable_id, 0)

        expect(draft.children_of(type_de_champ_repetition).index(last_child)).to eq(0)
      end
    end
  end

  describe '#remove_type_de_champ' do
    context 'for a classic tdc' do
      let(:procedure) { create(:procedure, :with_type_de_champ, :with_type_de_champ_private) }

      it 'type_de_champ' do
        draft.remove_type_de_champ(type_de_champ_public.stable_id)

        expect(draft.types_de_champ_public).to be_empty
      end

      it 'type_de_champ_private' do
        draft.remove_type_de_champ(type_de_champ_private.stable_id)

        expect(draft.types_de_champ_private).to be_empty
      end
    end

    context 'with multiple tdc' do
      context 'in public tdc' do
        let(:procedure) { create(:procedure, :with_type_de_champ, types_de_champ_count: 3) }

        it 'reorders' do
          expect(draft.revision_types_de_champ_public.pluck(:position)).to eq([0, 1, 2])

          draft.remove_type_de_champ(draft.types_de_champ_public[1].stable_id)

          expect(draft.revision_types_de_champ_public.pluck(:position)).to eq([0, 1])
        end
      end

      context 'in repetition tdc' do
        let(:procedure) { create(:procedure, :with_repetition) }
        let!(:second_child) do
          draft.add_type_de_champ({
            type_champ: TypeDeChamp.type_champs.fetch(:text),
            libelle: "second child",
            parent_id: type_de_champ_repetition.stable_id
          })
        end

        let!(:last_child) do
          draft.add_type_de_champ({
            type_champ: TypeDeChamp.type_champs.fetch(:text),
            libelle: "last child",
            parent_id: type_de_champ_repetition.stable_id
          })
        end

        it 'reorders' do
          children = draft.children_of(type_de_champ_repetition)
          expect(children.pluck(:position)).to eq([0, 1, 2])
          expect(children.pluck(:order_place)).to eq([0, 1, 2])

          draft.remove_type_de_champ(children[1].stable_id)

          children.reload

          expect(children.pluck(:position)).to eq([0, 1])
          expect(children.pluck(:order_place)).to eq([0, 1])
        end
      end
    end

    context 'for a type_de_champ_repetition' do
      let(:procedure) { create(:procedure, :with_repetition) }
      let!(:child) { child = draft.children_of(type_de_champ_repetition).first }

      it 'can remove its children' do
        draft.remove_type_de_champ(child.stable_id)

        expect(type_de_champ_repetition.types_de_champ).to be_empty
        expect { child.reload }.to raise_error ActiveRecord::RecordNotFound
        expect(draft.types_de_champ_public.size).to eq(1)
      end

      it 'can remove the parent' do
        draft.remove_type_de_champ(type_de_champ_repetition.stable_id)

        expect { child.reload }.to raise_error ActiveRecord::RecordNotFound
        expect { type_de_champ_repetition.reload }.to raise_error ActiveRecord::RecordNotFound
        expect(draft.types_de_champ_public).to be_empty
      end

      context 'when there already is a revision with this child' do
        let!(:new_draft) { procedure.create_new_revision }

        it 'can remove its children only in the new revision' do
          new_draft.remove_type_de_champ(child.stable_id)

          expect { child.reload }.not_to raise_error
          expect(draft.children_of(type_de_champ_repetition).size).to eq(1)
          expect(new_draft.children_of(type_de_champ_repetition)).to be_empty
        end

        it 'can remove the parent only in the new revision' do
          new_draft.remove_type_de_champ(type_de_champ_repetition.stable_id)

          expect { child.reload }.not_to raise_error
          expect { type_de_champ_repetition.reload }.not_to raise_error
          expect(draft.types_de_champ_public.size).to eq(1)
          expect(new_draft.types_de_champ_public).to be_empty
        end
      end
    end
  end

  describe '#create_new_revision' do
    let(:new_draft) { procedure.create_new_revision }

    context 'from a simple procedure' do
      let(:procedure) { create(:procedure) }

      it 'should be part of procedure' do
        expect(new_draft.procedure).to eq(draft.procedure)
        expect(procedure.revisions.count).to eq(2)
        expect(procedure.revisions).to eq([draft, new_draft])
      end
    end

    context 'with simple tdc' do
      let(:procedure) { create(:procedure, :with_type_de_champ, :with_type_de_champ_private) }

      it 'should have the same tdcs with different links' do
        expect(new_draft.types_de_champ_public.count).to eq(1)
        expect(new_draft.types_de_champ_private.count).to eq(1)
        expect(new_draft.types_de_champ_public).to eq(draft.types_de_champ_public)
        expect(new_draft.types_de_champ_private).to eq(draft.types_de_champ_private)

        expect(new_draft.revision_types_de_champ_public.count).to eq(1)
        expect(new_draft.revision_types_de_champ_private.count).to eq(1)
        expect(new_draft.revision_types_de_champ_public).not_to eq(draft.revision_types_de_champ_public)
        expect(new_draft.revision_types_de_champ_private).not_to eq(draft.revision_types_de_champ_private)
      end
    end

    context 'with repetition_type_de_champ' do
      let(:procedure) { create(:procedure, :with_repetition) }

      it 'should have the same tdcs with different links' do
        expect(new_draft.types_de_champ.count).to eq(2)
        expect(new_draft.types_de_champ).to eq(draft.types_de_champ)

        new_repetition, new_child = new_draft.types_de_champ.partition(&:repetition?).map(&:first)

        parent = new_draft.revision_types_de_champ.find_by(type_de_champ: new_repetition)
        child = new_draft.revision_types_de_champ.find_by(type_de_champ: new_child)

        expect(child.parent_id).to eq(parent.id)
      end
    end
  end

  describe '#update_type_de_champ' do
    let(:procedure) { create(:procedure, :with_repetition) }
    let(:last_coordinate) { draft.revision_types_de_champ.last }
    let(:last_type_de_champ) { last_coordinate.type_de_champ }

    context 'bug with duplicated repetition child' do
      before do
        procedure.publish!
        procedure.reload
        draft.find_or_clone_type_de_champ(last_type_de_champ.stable_id).update(libelle: 'new libelle')
        procedure.reload
        draft.reload
      end

      it do
        expect(procedure.revisions.size).to eq(2)
        expect(draft.revision_types_de_champ.where.not(parent_id: nil).size).to eq(1)
      end
    end
  end

  describe '#compare' do
    let(:first_tdc) { draft.types_de_champ_public.first }
    let(:new_draft) { procedure.create_new_revision }

    subject { procedure.active_revision.compare(new_draft.reload) }

    context 'when a type de champ is added' do
      let(:procedure) { create(:procedure) }
      let(:new_tdc) do
        new_draft.add_type_de_champ(
          type_champ: TypeDeChamp.type_champs.fetch(:text),
          libelle: "Un champ text"
        )
      end

      before { new_tdc }

      it do
        is_expected.to eq([
          {
            model: :type_de_champ,
            op: :add,
            label: "Un champ text",
            private: false,
            stable_id: new_tdc.stable_id
          }
        ])
      end
    end

    context 'when a type de champ is changed' do
      let(:procedure) { create(:procedure, :with_type_de_champ) }

      before do
        updated_tdc = new_draft.find_or_clone_type_de_champ(first_tdc.stable_id)

        updated_tdc.update(libelle: 'modifier le libelle', description: 'une description', mandatory: !updated_tdc.mandatory)
      end

      it do
        is_expected.to eq([
          {
            model: :type_de_champ,
            op: :update,
            attribute: :libelle,
            label: first_tdc.libelle,
            private: false,
            from: first_tdc.libelle,
            to: "modifier le libelle",
            stable_id: first_tdc.stable_id
          },
          {
            model: :type_de_champ,
            op: :update,
            attribute: :description,
            label: first_tdc.libelle,
            private: false,
            from: first_tdc.description,
            to: "une description",
            stable_id: first_tdc.stable_id
          },
          {
            model: :type_de_champ,
            op: :update,
            attribute: :mandatory,
            label: first_tdc.libelle,
            private: false,
            from: false,
            to: true,
            stable_id: first_tdc.stable_id
          }
        ])
      end
    end

    context 'when a type de champ is moved' do
      let(:procedure) { create(:procedure, :with_type_de_champ, types_de_champ_count: 3) }
      let(:new_draft_second_tdc) { new_draft.types_de_champ_public.second }
      let(:new_draft_third_tdc) { new_draft.types_de_champ_public.third }

      before do
        new_draft_second_tdc
        new_draft_third_tdc
        new_draft.move_type_de_champ(new_draft_second_tdc.stable_id, 2)
      end

      it do
        is_expected.to eq([
          {
            model: :type_de_champ,
            op: :move,
            label: new_draft_third_tdc.libelle,
            private: false,
            from: 2,
            to: 1,
            stable_id: new_draft_third_tdc.stable_id
          },
          {
            model: :type_de_champ,
            op: :move,
            label: new_draft_second_tdc.libelle,
            private: false,
            from: 1,
            to: 2,
            stable_id: new_draft_second_tdc.stable_id
          }
        ])
      end
    end

    context 'when a type de champ is removed' do
      let(:procedure) { create(:procedure, :with_type_de_champ) }

      before do
        new_draft.remove_type_de_champ(first_tdc.stable_id)
      end

      it do
        is_expected.to eq([
          {
            model: :type_de_champ,
            op: :remove,
            label: first_tdc.libelle,
            private: false,
            stable_id: first_tdc.stable_id
          }
        ])
      end
    end

    context 'when a child type de champ is transformed into a drop_down_list' do
      let(:procedure) { create(:procedure, :with_repetition) }

      before do
        child = new_draft.children_of(new_draft.types_de_champ_public.last).first
        new_draft.find_or_clone_type_de_champ(child.stable_id).update(type_champ: :drop_down_list, drop_down_options: ['one', 'two'])
      end

      it do
        is_expected.to eq([
          {
            model: :type_de_champ,
            op: :update,
            attribute: :type_champ,
            label: "sub type de champ",
            private: false,
            from: "text",
            to: "drop_down_list",
            stable_id: new_draft.types_de_champ_public.last.types_de_champ.first.stable_id
          },
          {
            model: :type_de_champ,
            op: :update,
            attribute: :drop_down_options,
            label: "sub type de champ",
            private: false,
            from: [],
            to: ["one", "two"],
            stable_id: new_draft.types_de_champ_public.last.types_de_champ.first.stable_id
          }
        ])
      end
    end

    context 'when a child type de champ is transformed into a map' do
      let(:procedure) { create(:procedure, :with_repetition) }

      before do
        child = new_draft.types_de_champ_public.last.types_de_champ.first
        new_draft.find_or_clone_type_de_champ(child.stable_id).update(type_champ: :carte, options: { cadastres: true, znieff: true })
      end

      it do
        is_expected.to eq([
          {
            model: :type_de_champ,
            op: :update,
            attribute: :type_champ,
            label: "sub type de champ",
            private: false,
            from: "text",
            to: "carte",
            stable_id: new_draft.types_de_champ_public.last.types_de_champ.first.stable_id
          },
          {
            model: :type_de_champ,
            op: :update,
            attribute: :carte_layers,
            label: "sub type de champ",
            private: false,
            from: [],
            to: [:cadastres, :znieff],
            stable_id: new_draft.types_de_champ_public.last.types_de_champ.first.stable_id
          }
        ])
      end
    end
  end

  describe 'children_of' do
    context 'with a simple tdc' do
      let(:procedure) { create(:procedure, :with_type_de_champ) }

      it { expect(draft.children_of(draft.types_de_champ.first)).to be_empty }
    end

    context 'with a repetition tdc' do
      let(:procedure) { create(:procedure, :with_repetition) }
      let!(:parent) { draft.types_de_champ.find(&:repetition?) }
      let!(:child) { draft.types_de_champ.reject(&:repetition?).first }

      it { expect(draft.children_of(parent)).to match([child]) }

      context 'with multiple child' do
        let(:child_position_2) { create(:type_de_champ_text) }
        let(:child_position_1) { create(:type_de_champ_text) }

        before do
          parent_coordinate = draft.revision_types_de_champ.find_by(type_de_champ_id: parent.id)
          draft.revision_types_de_champ.create(type_de_champ: child_position_2, position: 2, parent_id: parent_coordinate.id)
          draft.revision_types_de_champ.create(type_de_champ: child_position_1, position: 1, parent_id: parent_coordinate.id)
        end

        it 'returns the children in order' do
          expect(draft.children_of(parent)).to eq([child, child_position_1, child_position_2])
        end
      end

      context 'with multiple revision' do
        let(:new_child) { create(:type_de_champ_text) }
        let(:new_draft) do
          procedure.publish!
          procedure.draft_revision
        end

        before do
          new_draft
            .revision_types_de_champ
            .where(type_de_champ: child)
            .update(type_de_champ: new_child)
        end

        it 'returns the children regarding the revision' do
          expect(draft.children_of(parent)).to match([child])
          expect(new_draft.children_of(parent)).to match([new_child])
        end
      end
    end
  end

  describe '#estimated_fill_duration' do
    let(:mandatory) { true }
    let(:types_de_champ) do
      [
        build(:type_de_champ_text, position: 1, mandatory: true),
        build(:type_de_champ_siret, position: 2, mandatory: true),
        build(:type_de_champ_piece_justificative, position: 3, mandatory: mandatory)
      ]
    end
    let(:procedure) { create(:procedure, types_de_champ: types_de_champ) }

    subject { procedure.active_revision.estimated_fill_duration }

    it 'sums the durations of public champs' do
      expect(subject).to eq \
          TypesDeChamp::TypeDeChampBase::FILL_DURATION_SHORT \
        + TypesDeChamp::TypeDeChampBase::FILL_DURATION_MEDIUM \
        + TypesDeChamp::TypeDeChampBase::FILL_DURATION_LONG
    end

    context 'when some champs are optional' do
      let(:mandatory) { false }

      it 'estimates that half of optional champs will be filled' do
        expect(subject).to eq \
             TypesDeChamp::TypeDeChampBase::FILL_DURATION_SHORT \
          + TypesDeChamp::TypeDeChampBase::FILL_DURATION_MEDIUM \
          + TypesDeChamp::TypeDeChampBase::FILL_DURATION_LONG / 2
      end
    end

    context 'when there are repetitions' do
      let(:types_de_champ) do
        [
          build(:type_de_champ_repetition, position: 1, mandatory: true, types_de_champ: [
            build(:type_de_champ_text, position: 1, mandatory: true),
            build(:type_de_champ_piece_justificative, position: 2, mandatory: true)
          ])
        ]
      end

      it 'estimates that between 2 and 3 rows will be filled for each repetition' do
        row_duration = TypesDeChamp::TypeDeChampBase::FILL_DURATION_SHORT + TypesDeChamp::TypeDeChampBase::FILL_DURATION_LONG
        expect(subject).to eq row_duration * 2.5
      end
    end

    describe 'caching behavior' do
      let(:procedure) { create(:procedure, :published, types_de_champ: types_de_champ) }

      before { Rails.cache = ActiveSupport::Cache::MemoryStore.new }
      after { Rails.cache = ActiveSupport::Cache::NullStore.new }

      context 'when a type de champ belonging to a draft revision is updated' do
        let(:draft_revision) { procedure.draft_revision }

        before do
          draft_revision.estimated_fill_duration
          draft_revision.types_de_champ.first.update!(type_champ: TypeDeChamp.type_champs.fetch(:piece_justificative))
        end

        it 'returns an up-to-date estimate' do
          expect(draft_revision.estimated_fill_duration).to eq \
              TypesDeChamp::TypeDeChampBase::FILL_DURATION_LONG \
            + TypesDeChamp::TypeDeChampBase::FILL_DURATION_MEDIUM \
            + TypesDeChamp::TypeDeChampBase::FILL_DURATION_LONG \
        end
      end

      context 'when the revision is published (and thus immutable)' do
        let(:published_revision) { procedure.published_revision }

        it 'caches the estimate' do
          expect(published_revision).to receive(:compute_estimated_fill_duration).once
          published_revision.estimated_fill_duration
          published_revision.estimated_fill_duration
        end
      end
    end
  end
end
