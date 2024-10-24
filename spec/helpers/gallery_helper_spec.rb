RSpec.describe GalleryHelper, type: :helper do
  let(:procedure) { create(:procedure_with_dossiers) }
  let(:type_de_champ_pj) { create(:type_de_champ_piece_justificative, stable_id: 3, libelle: 'Justificatif de domicile', procedure:) }
  let(:champ_pj) { create(:champ_piece_justificative, type_de_champ: type_de_champ_pj) }
  let(:blob_info) do
    {
      filename: file.original_filename,
      byte_size: file.size,
      checksum: Digest::SHA256.file(file.path),
      content_type: file.content_type,
      # we don't want to run virus scanner on this file
      metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
    }
  end
  let(:blob) do
    blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_info)
    blob.upload(file)
    blob
  end
  let(:attachment) { ActiveStorage::Attachment.create(name: "test", blob: blob, record: champ_pj) }

  describe ".variant_url_for" do
    subject { variant_url_for(attachment) }

    context "when attachment can be represented with a variant" do
      let(:file) { fixture_file_upload('spec/fixtures/files/logo_test_procedure.png', 'image/png') }

      it { expect { subject }.to change { ActiveStorage::VariantRecord.count }.by(1) }
      it { is_expected.not_to eq("apercu-indisponible.png") }
    end

    context "when attachment cannot be represented with a variant" do
      let(:file) { fixture_file_upload('spec/fixtures/files/instructeurs-file.csv', 'text/csv') }

      it { expect { subject }.not_to change { ActiveStorage::VariantRecord.count } }
      it { is_expected.to eq("apercu-indisponible.png") }
    end
  end

  describe ".preview_url_for" do
    subject { preview_url_for(attachment) }

    context "when attachment can be represented with a preview" do
      let(:file) { fixture_file_upload('spec/fixtures/files/RIB.pdf', 'application/pdf') }

      it { expect { subject }.to change { ActiveStorage::VariantRecord.count }.by(1) }
      it { is_expected.not_to eq("pdf-placeholder.png") }
    end

    context "when attachment cannot be represented with a preview" do
      let(:file) { fixture_file_upload('spec/fixtures/files/instructeurs-file.csv', 'text/csv') }

      it { expect { subject }.not_to change { ActiveStorage::VariantRecord.count } }
      it { is_expected.to eq("pdf-placeholder.png") }
    end
  end
end
