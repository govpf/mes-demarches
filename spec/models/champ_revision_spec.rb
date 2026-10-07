# frozen_string_literal: true

describe ChampRevision do
  describe "associations" do
    it {
      is_expected.to belong_to(:champ)
      is_expected.to belong_to(:instructeur)
      is_expected.to belong_to(:etablissement).optional
    }
  end

  describe "create_or_update_revision" do
      let(:procedure) { create(:procedure, :published) }
      let(:type_de_champ) { create(:type_de_champ_text, procedure: procedure) }
      let(:dossier) { create(:dossier, procedure: procedure) }
      let(:champ) { Champs::TextChamp.new(value: 'my_string', dossier: dossier, stable_id: type_de_champ.stable_id).tap(&:save!) }

      let!(:instructeur) { create(:instructeur) }

      context "when champ is not a Textarea" do
        context "when no champ_revision yet for current_champ" do
          it "create a new champ_revision" do
            ChampRevision.create_or_update_revision(champ, instructeur.id)
            expect(ChampRevision.where(champ_id: champ.id).count).to eq(1)
          end
        end

        context "When there's already a revision" do
          before {
            ChampRevision.create_or_update_revision(champ, instructeur.id)
            ChampRevision.last.update(updated_at: delay)
            champ.update(value: 'my_string2')
          }
          context "when existing champ_revision is recent" do
            let(:delay) { 4.seconds.ago }
            it "does not create a new champ_revision" do
              ChampRevision.create_or_update_revision(champ, instructeur.id)
              expect(ChampRevision.where(champ_id: champ).count).to eq(1)
            end
          end

          context "when existing champ_revision is old" do
            let(:delay) { 10.seconds.ago }
            it "does create a new champ_revision" do
              ChampRevision.create_or_update_revision(champ, instructeur.id)
              expect(ChampRevision.where(champ_id: champ).count).to eq(2)
            end
          end
        end
      end

      context "when champ is a Textarea" do
        let(:type_de_champ_textarea) { create(:type_de_champ_textarea, procedure: procedure) }
        let(:champ) { Champs::TextareaChamp.new(value: 'my_string', dossier: dossier, stable_id: type_de_champ_textarea.stable_id).tap(&:save!) }
        context "When there's already a revision" do
          before {
            ChampRevision.create_or_update_revision(champ, instructeur.id)
            ChampRevision.last.update(updated_at: delay)
            champ.update(value: 'my_string2')
          }
          context "when already champ_revision recent" do
            let(:delay) { 110.seconds.ago }
            it "does not create a new champ_revision" do
              ChampRevision.create_or_update_revision(champ, instructeur.id)
              expect(ChampRevision.where(champ_id: champ).count).to eq(1)
            end
          end

          context "when existing champ_revision is old" do
            let(:delay) { 130.seconds.ago }
            it "does create a new champ_revision" do
              ChampRevision.create_or_update_revision(champ, instructeur.id)
              expect(ChampRevision.where(champ_id: champ).count).to eq(2)
            end
          end
        end
      end
    end

  # pf: l'historique d'une annotation PJ doit afficher les noms de fichiers stockés,
  # même quand la pièce a été remplacée ou supprimée depuis.
  describe "#display_value" do
    let(:procedure) { create(:procedure, :published, types_de_champ_private: [{ type: :piece_justificative }]) }
    let(:dossier) { create(:dossier, :en_instruction, procedure:) }
    let(:champ) { dossier.project_champs_private.first }
    let(:instructeur) { create(:instructeur) }

    before do
      champ.piece_justificative_file.attach(io: StringIO.new('pdf'), filename: 'ancien.pdf', content_type: 'application/pdf')
      champ.save!
      ChampRevision.create_or_update_revision(champ, instructeur.id)
      champ.piece_justificative_file.purge
    end

    it "affiche les noms de fichiers de la révision" do
      expect(ChampRevision.where(champ:).last.display_value).to eq('ancien.pdf')
    end
  end
end
