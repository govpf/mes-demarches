# frozen_string_literal: true

# pf: lot C DLNUF — un blob rattaché à deux dossiers (préremplissage par référence, comme le clone)
# survit à la suppression du dossier source et au remplacement de la pièce source ; il n'est
# supprimé qu'au dernier rattachement.
RSpec.describe 'Blob partagé entre deux dossiers' do
  include ActiveJob::TestHelper

  let(:procedure_a) { create(:procedure, :published, types_de_champ_public: [{ type: :piece_justificative }]) }
  let(:procedure_b) { create(:procedure, :published, types_de_champ_public: [{ type: :piece_justificative }]) }
  let(:dossier_a) { create(:dossier, :en_construction, :with_populated_champs, procedure: procedure_a) }
  let(:dossier_b) { create(:dossier, :brouillon, procedure: procedure_b) }
  let(:champ_a) { dossier_a.project_champs_public.first }
  let(:champ_b) { dossier_b.champ_for_update(procedure_b.active_revision.types_de_champ_public.first, updated_by: :api) }
  let(:blob) { champ_a.piece_justificative_file.blobs.first }

  before do
    expect(blob).to be_present
    ClonePiecesJustificativesService.clone_attachments(champ_a, champ_b)
    champ_b.save!
    expect(champ_b.reload.piece_justificative_file.blobs.map(&:id)).to eq([blob.id])
  end

  def blob_intact? = ActiveStorage::Blob.exists?(blob.id) && blob.service.exist?(blob.key)

  it 'survit à la suppression du dossier source (purge_discarded)' do
    dossier_a.update!(hidden_by_user_at: Time.zone.now, hidden_by_reason: :user_request)
    perform_enqueued_jobs { Dossier.find(dossier_a.id).purge_discarded }

    expect(Dossier.exists?(dossier_a.id)).to be(false)
    expect(blob_intact?).to be(true)
    expect(Champ.find(champ_b.id).piece_justificative_file.first.download).to be_present
  end

  it 'survit au remplacement de la pièce source (purge_later)' do
    perform_enqueued_jobs { champ_a.piece_justificative_file.first.purge_later }

    expect(blob_intact?).to be(true)
  end

  it 'est supprimé quand le dernier rattachement disparaît' do
    perform_enqueued_jobs do
      dossier_a.destroy!
      Dossier.find(dossier_b.id).destroy!
    end

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end
end
