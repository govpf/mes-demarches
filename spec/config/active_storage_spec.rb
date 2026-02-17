# frozen_string_literal: true

describe "ActiveStorage configuration" do
  describe "blob analysis" do
    it "does not enqueue AnalyzeJob when an image blob is created" do
      image_path = Rails.root.join("spec/fixtures/files/logo_test_procedure.png")
      blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open(image_path),
        filename: "test.png",
        content_type: "image/png"
      )

      expect {
        ActiveStorage::Attachment.create!(
          name: "test",
          record: create(:dossier),
          blob: blob
        )
      }.not_to have_enqueued_job(ActiveStorage::AnalyzeJob)
    end
  end
end
