# frozen_string_literal: true

describe EditableChamp::SiretComponent, type: :component do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :siret }]) }
  let(:dossier) { create(:dossier, :with_populated_champs, procedure:) }
  let(:champ) { dossier.project_champs_public.first }
  let(:form) { double(object: champ) }
  let(:component) { described_class.new(form:, champ:) }

  # pf: une même erreur remontait deux fois. `error_full_messages` concatène les
  # erreurs imbriquées portées par le dossier et celles portées par l'instance du
  # champ ; sans déduplication, le composant de statut les rend via `to_sentence`,
  # ce qui produit « doit être un numéro Tahiti … et doit être un numéro Tahiti … ».
  describe "#error_full_messages" do
    subject { component.error_full_messages }

    context "quand la même erreur est portée par le champ ET remontée par le dossier" do
      before do
        # pf: en production, le contrôleur tient UNE seule instance de dossier —
        # `champ = dossier.public_champ_for_update(...)` puis `dossier.validate(...)`.
        # L'association inverse n'étant pas garantie ici, on la force, sinon
        # `object.dossier.errors` est vide et le doublon ne se reproduit pas.
        allow(champ).to receive(:dossier).and_return(dossier)
        champ.errors.add(:external_id, :length)
        dossier.errors.import(champ.errors.first)
      end

      it "ne la présente qu’une fois" do
        expect(subject.size).to eq(1)
      end
    end

    context "quand deux erreurs distinctes coexistent sur le champ" do
      before do
        champ.errors.add(:external_id, :length)
        champ.errors.add(:external_id, :not_found)
      end

      it "les conserve toutes les deux" do
        expect(subject.size).to eq(2)
      end
    end
  end
end
