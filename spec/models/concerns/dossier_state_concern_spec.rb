# frozen_string_literal: true

RSpec.describe DossierStateConcern do
  include Logic

  let(:procedure) { create(:procedure, :published, :for_individual, types_de_champ_public:, declarative_with_state:, auto_archive_on:) }
  let(:types_de_champ_public) do
    [
      { type: :text, stable_id: 90 },
      { type: :text, stable_id: 91 },
      { type: :piece_justificative, stable_id: 92, condition: ds_eq(constant(true), constant(false)) },
      { type: :titre_identite, stable_id: 93, condition: ds_eq(constant(true), constant(false)) },
      { type: :repetition, stable_id: 94, children: [{ type: :text, stable_id: 941 }, { type: :text, stable_id: 942 }] },
      { type: :repetition, stable_id: 95, children: [{ type: :text, stable_id: 951 }] },
      { type: :repetition, stable_id: 96, children: [{ type: :text, stable_id: 961 }], condition: ds_eq(constant(true), constant(false)) },
      { type: :text, stable_id: 97, condition: ds_eq(constant(true), constant(false)) },
      { type: :titre_identite, stable_id: 98 }
    ]
  end
  let(:auto_archive_on) { nil }
  let(:declarative_with_state) { nil }
  let(:dossier_state) { :brouillon }
  let(:dossier) do
    create(:dossier, dossier_state, :with_individual, :with_populated_champs, procedure:).tap do |dossier|
      procedure.draft_revision.remove_type_de_champ(91)
      procedure.draft_revision.remove_type_de_champ(95)
      procedure.draft_revision.remove_type_de_champ(942)
      procedure.publish_revision!
      perform_enqueued_jobs
      dossier.reload
      champ_repetition = dossier.project_champs_public.find { _1.stable_id == 94 }
      row_id = champ_repetition.row_ids.first
      dossier.champs.filter(&:row?).find { _1.row_id == row_id }.touch(:discarded_at)
    end
  end

  describe 'submit brouillon' do
    it do
      expect(dossier.champs.size).to eq(20)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(2)
      expect(dossier.champs.filter { _1.row? && _1.discarded? }.size).to eq(1)
      expect(dossier.champs.filter { _1.row? && _1.stable_id.in?([95, 96]) }.size).to eq(4)
      expect(dossier.champs.filter { _1.stable_id.in?([90, 92, 93, 97, 961, 951]) }.size).to eq(8)

      champ_text = dossier.project_champs_public.find { _1.stable_id == 90 }
      champ_text.update(value: '')

      dossier.passer_en_construction!
      dossier.reload

      expect(dossier.champs.size).to eq(3)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(1)
      expect(dossier.champs.filter { _1.row? && _1.discarded? }.size).to eq(0)
      expect(dossier.champs.filter { _1.row? && _1.stable_id.in?([95, 96]) }.size).to eq(0)
      expect(dossier.champs.filter { _1.stable_id.in?([90, 92, 93, 97, 961, 951]) }.size).to eq(0)
      expect(dossier.submitted_revision_id).to eq(dossier.revision_id)
    end

    it "create dossier_depose notification for all instructeurs" do
      procedure.defaut_groupe_instructeur.add_instructeurs(ids: create_list(:instructeur, 2).map(&:id))
      dossier.passer_en_construction!

      expect(DossierNotification.count).to eq(2)

      notification = DossierNotification.first
      expect(notification.dossier_id).to eq(dossier.id)
      expect(notification.notification_type).to eq("dossier_depose")
    end
  end

  describe 'submit en construction' do
    let(:dossier_state) { :en_construction }

    it do
      expect(dossier.champs.size).to eq(20)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(2)
      expect(dossier.champs.filter { _1.row? && _1.discarded? }.size).to eq(1)
      expect(dossier.champs.filter { _1.row? && _1.stable_id.in?([95, 96]) }.size).to eq(4)
      expect(dossier.champs.filter { _1.stable_id.in?([92, 93, 97, 961, 951]) }.size).to eq(7)

      dossier.submit_en_construction!
      dossier.reload

      expect(dossier.champs.size).to eq(4)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(1)
      expect(dossier.champs.filter { _1.row? && _1.discarded? }.size).to eq(0)
      expect(dossier.champs.filter { _1.row? && _1.stable_id.in?([95, 96]) }.size).to eq(0)
      expect(dossier.champs.filter { _1.stable_id.in?([92, 93, 97, 961, 951]) }.size).to eq(0)
      expect(dossier.submitted_revision_id).to eq(dossier.revision_id)
    end

    context "when there are instructeurs followers" do
      let!(:instructeur_follower) { create(:instructeur, followed_dossiers: [dossier]) }
      let!(:instructeur_not_follower) { create(:instructeur) }

      before do
        procedure.defaut_groupe_instructeur.add_instructeurs(ids: [instructeur_follower, instructeur_not_follower].map(&:id))
      end

      it "create dossier_modifie notification only for instructeur follower" do
        dossier.submit_en_construction!

        expect(DossierNotification.count).to eq(1)

        notification = DossierNotification.last
        expect(notification.dossier_id).to eq(dossier.id)
        expect(notification.instructeur_id).to eq(instructeur_follower.id)
        expect(notification.notification_type).to eq("dossier_modifie")
      end
    end
  end

  describe 'accepter' do
    let(:dossier_state) { :en_instruction }

    it do
      expect(dossier.champs.size).to eq(20)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(2)
      expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(2)

      dossier.accepter!(motivation: 'test')
      dossier.reload

      expect(dossier.champs.size).to eq(15)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(1)
      expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(0)
    end
  end

  describe 'refuser' do
    let(:dossier_state) { :en_instruction }

    it do
      expect(dossier.champs.size).to eq(20)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(2)
      expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(2)

      dossier.refuser!(motivation: 'test')
      dossier.reload

      expect(dossier.champs.size).to eq(15)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(1)
      expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(0)
    end
  end

  describe 'classer_sans_suite' do
    let(:dossier_state) { :en_instruction }

    it do
      expect(dossier.champs.size).to eq(20)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(2)
      expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(2)

      dossier.classer_sans_suite!(motivation: 'test')
      dossier.reload

      expect(dossier.champs.size).to eq(15)
      expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(1)
      expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(0)
    end
  end

  describe 'automatiquement' do
    let(:dossier_state) { :en_construction }

    describe 'accepter' do
      let(:declarative_with_state) { Dossier.states.fetch(:accepte) }

      it do
        expect(dossier.champs.size).to eq(20)
        expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(2)
        expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(2)

        dossier.accepter_automatiquement!
        dossier.reload

        expect(dossier.champs.size).to eq(15)
        expect(dossier.champs.filter { _1.row? && _1.stable_id == 94 }.size).to eq(1)
        expect(dossier.champs.filter { _1.stable_id.in?([93, 98]) }.size).to eq(0)
      end
    end

    describe 'en_instruction' do
      context "when dossier has a dossier_depose notification" do
        let(:auto_archive_on) { 1.day.from_now }
        let!(:notification) { create(:dossier_notification, :for_groupe_instructeur, groupe_instructeur_id: dossier.groupe_instructeur_id, dossier:) }

        it "destroy the notification" do
          travel_to(2.days.from_now)
          dossier.passer_automatiquement_en_instruction!

          expect(DossierNotification.count).to eq(0)
        end
      end
    end
  end

  describe 'warm_pj_previews' do
    let(:procedure) { create(:procedure, :published, :for_individual, types_de_champ_public: [{ type: :piece_justificative, stable_id: 100 }], declarative_with_state: nil, auto_archive_on: nil) }
    let(:dossier) { create(:dossier, :en_instruction, :with_individual, procedure:) }
    let(:champ_pj) { dossier.project_champs_public.find { _1.stable_id == 100 } }

    before do
      champ_pj.piece_justificative_file.attach(
        io: StringIO.new(File.read(Rails.root.join('spec/fixtures/files/logo_test_procedure.png'), mode: 'rb')),
        filename: 'logo_test_procedure.png',
        content_type: 'image/png'
      )
    end

    it 'generates variants for image attachments' do
      attachment = champ_pj.piece_justificative_file.attachments.first
      expect(attachment.variant(resize_to_limit: [400, 400]).key).to be_nil

      expect { dossier.send(:warm_pj_previews) }.to change { ActiveStorage::VariantRecord.count }.by(1)

      expect(attachment.variant(resize_to_limit: [400, 400]).key).not_to be_nil
    end

    it 'does not raise when variant processing fails' do
      attachment = champ_pj.piece_justificative_file.attachments.first
      allow(attachment).to receive(:variant).and_raise(StandardError.new('S3 upload failed'))

      expect { dossier.send(:warm_pj_previews) }.not_to raise_error
    end

    context 'when a VariantRecord is orphaned (no S3 file)' do
      it 'cleans up the orphan variant record' do
        attachment = champ_pj.piece_justificative_file.attachments.first
        blob = attachment.blob

        # Create an orphan VariantRecord with an image blob that has no backing file in storage.
        # We insert records directly to simulate the Rails bug (VariantRecord committed before S3 upload).
        orphan_blob = ActiveStorage::Blob.create_before_direct_upload!(
          filename: 'variant.png',
          byte_size: 100,
          checksum: 'abc123',
          content_type: 'image/png'
        )
        orphan_variant = ActiveStorage::VariantRecord.create!(blob: blob, variation_digest: 'orphan_digest')
        # Directly create the attachment record without triggering file validation
        ActiveStorage::Attachment.create!(
          name: 'image',
          record_type: 'ActiveStorage::VariantRecord',
          record_id: orphan_variant.id,
          blob_id: orphan_blob.id
        )
        orphan_variant.reload

        # Make variant processing raise to trigger cleanup
        allow(attachment).to receive(:variant).and_raise(StandardError.new('processing failed'))

        # The orphan blob key does not exist in storage
        expect(orphan_blob.service.exist?(orphan_blob.key)).to be false

        expect {
          dossier.send(:warm_pj_previews)
        }.to change { ActiveStorage::VariantRecord.where(id: orphan_variant.id).count }.from(1).to(0)
      end
    end
  end
end
