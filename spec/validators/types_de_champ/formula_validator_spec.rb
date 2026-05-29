# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TypesDeChamp::FormulaValidator do
  let(:procedure) { create(:procedure, types_de_champ_public: types) }

  subject { procedure.validate(:types_de_champ_public_editor) }

  context 'with a valid formula referencing a preceding champ' do
    let(:types) { [{ type: :integer_number, libelle: 'Montant' }, { type: :formule, libelle: 'Calcul' }] }

    before do
      formule_tdc = procedure.draft_revision.types_de_champ_public.find(&:formule?)
      montant_tdc = procedure.draft_revision.types_de_champ_public.find(&:integer_number?)
      formule_tdc.update_column(:options, { 'formule_expression' => "{tdc#{montant_tdc.stable_id}} * 2" })
    end

    it 'does not add errors' do
      expect { subject }.not_to change { procedure.errors.count }
    end
  end

  context 'with a formula referencing an unknown column' do
    let(:types) { [{ type: :formule, libelle: 'Calcul' }] }

    before do
      formule_tdc = procedure.draft_revision.types_de_champ_public.find(&:formule?)
      formule_tdc.update_column(:options, { 'formule_expression' => '{tdc99999} * 2' })
    end

    it 'adds an error' do
      expect { subject }.to change { procedure.errors.count }.by_at_least(1)
      expect(procedure.errors.full_messages.join).to include('Colonne inconnue')
    end
  end

  context 'with a formula referencing a following champ (order violation)' do
    let(:types) { [{ type: :formule, libelle: 'Calcul' }, { type: :integer_number, libelle: 'Montant' }] }

    before do
      formule_tdc = procedure.draft_revision.types_de_champ_public.find(&:formule?)
      montant_tdc = procedure.draft_revision.types_de_champ_public.find(&:integer_number?)
      formule_tdc.update_column(:options, { 'formule_expression' => "{tdc#{montant_tdc.stable_id}} * 2" })
    end

    it 'adds an error about order constraint' do
      expect { subject }.to change { procedure.errors.count }.by_at_least(1)
      expect(procedure.errors.full_messages.join).to include('ne peut référencer')
    end
  end

  context 'with an empty formula expression' do
    let(:types) { [{ type: :formule, libelle: 'Calcul' }] }

    before do
      formule_tdc = procedure.draft_revision.types_de_champ_public.find(&:formule?)
      formule_tdc.update_column(:options, { 'formule_expression' => '' })
    end

    it 'does not add errors' do
      expect { subject }.not_to change { procedure.errors.count }
    end
  end

  context 'with old format (labels)' do
    let(:types) { [{ type: :integer_number, libelle: 'Montant' }, { type: :formule, libelle: 'Calcul' }] }

    before do
      formule_tdc = procedure.draft_revision.types_de_champ_public.find(&:formule?)
      formule_tdc.update_column(:options, { 'formule_expression' => '{Montant} * 2' })
    end

    it 'validates old format references' do
      expect { subject }.not_to change { procedure.errors.count }
    end
  end

  context 'with old format referencing unknown label' do
    let(:types) { [{ type: :formule, libelle: 'Calcul' }] }

    before do
      formule_tdc = procedure.draft_revision.types_de_champ_public.find(&:formule?)
      formule_tdc.update_column(:options, { 'formule_expression' => '{Inexistant} * 2' })
    end

    it 'adds an error about unknown field' do
      expect { subject }.to change { procedure.errors.count }.by_at_least(1)
      expect(procedure.errors.full_messages.join).to include('Champs inconnus')
    end
  end

  # pf: agrégat sur bloc répétable — {tdc<bloc>} (COUNT) et {tdc<bloc>/sub_<id>} (SOMME).
  context 'with an aggregate formula referencing a preceding repetition block' do
    let(:types) do
      [
        { type: :repetition, libelle: 'Facture', mandatory: false, children: [
          { type: :integer_number, libelle: 'Prix HT' },
        ] },
        { type: :formule, libelle: 'Total' },
      ]
    end
    let(:revision) { procedure.draft_revision }
    let(:bloc_tdc) { revision.types_de_champ.find { _1.libelle == 'Facture' } }
    let(:prix_tdc) { revision.types_de_champ.find { _1.libelle == 'Prix HT' } }
    let(:formule_tdc) { revision.types_de_champ.find { _1.libelle == 'Total' } }

    it 'accepts NB({bloc}) sans erreur' do
      formule_tdc.update_column(:options, { 'formule_expression' => "NB({tdc#{bloc_tdc.stable_id}})" })
      expect { subject }.not_to change { procedure.errors.count }
    end

    it 'accepts SOMME({bloc/sous-champ}) sans erreur' do
      formule_tdc.update_column(:options, { 'formule_expression' => "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{prix_tdc.stable_id}})" })
      expect { subject }.not_to change { procedure.errors.count }
    end
  end

  context 'with an aggregate referencing a repetition block placed AFTER the formula' do
    let(:types) do
      [
        { type: :formule, libelle: 'Total' },
        { type: :repetition, libelle: 'Facture', mandatory: false, children: [
          { type: :integer_number, libelle: 'Prix HT' },
        ] },
      ]
    end
    let(:revision) { procedure.draft_revision }
    let(:bloc_tdc) { revision.types_de_champ.find { _1.libelle == 'Facture' } }
    let(:formule_tdc) { revision.types_de_champ.find { _1.libelle == 'Total' } }

    it 'adds an error (le bloc ne précède pas la formule)' do
      formule_tdc.update_column(:options, { 'formule_expression' => "NB({tdc#{bloc_tdc.stable_id}})" })
      expect { subject }.to change { procedure.errors.count }.by_at_least(1)
      expect(procedure.errors.full_messages.join).to include('bloc')
    end
  end

  context 'with a private formula referencing a public champ' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :integer_number, libelle: 'Montant' },
      ], types_de_champ_private: [
        { type: :formule, libelle: 'Calcul Privé' },
      ])
    end

    subject { procedure.validate(:types_de_champ_private_editor) }

    before do
      montant_tdc = procedure.draft_revision.types_de_champ_public.find(&:integer_number?)
      formule_tdc = procedure.draft_revision.types_de_champ_private.find(&:formule?)
      formule_tdc.update_column(:options, { 'formule_expression' => "{tdc#{montant_tdc.stable_id}} * 2" })
    end

    it 'does not add errors (private can reference public)' do
      expect { subject }.not_to change { procedure.errors.count }
    end
  end
end
