# frozen_string_literal: true

describe ReferentielDePolynesie::PrefillPieceJustificative do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:procedure_source) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :piece_justificative, libelle: 'Statuts' },
      { type: :titre_identite, libelle: 'Identité' },
      { type: :repetition, libelle: 'Membres', children: [{ type: :piece_justificative, libelle: 'Pièce du membre' }] },
    ])
  end
  let(:source) { create(:dossier, :en_construction, :with_populated_champs, procedure: procedure_source, user:) }
  let(:tdc_source) { -> (libelle) { source.revision.types_de_champ.find { _1.libelle == libelle } } }
  let(:champ_source) { source.project_champ(tdc_source.('Statuts')) }

  let(:procedure_cible) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :referentiel_de_polynesie, libelle: 'Association', table_id: '24' },
      { type: :piece_justificative, libelle: 'Statuts' },
    ])
  end
  let(:dossier) { create(:dossier, :brouillon, procedure: procedure_cible, user:) }
  let(:referentiel_champ) { dossier.project_champs_public.find { _1.libelle == 'Association' } }
  let(:tdc_cible) { procedure_cible.active_revision.types_de_champ.find { _1.libelle == 'Statuts' } }
  let(:cible) { dossier.champ_for_update(tdc_cible, updated_by: :api) }

  let(:dlnuf) { { field_id: 9, field_name: 'Email', field_type: 'email' } }
  let(:reference) { "md:#{source.id}:#{tdc_source.('Statuts').stable_id}" }

  before do
    allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with('24').and_return(dlnuf)
    champ_source.piece_justificative_file.attach(io: StringIO.new('second'), filename: 'second.pdf', content_type: 'application/pdf')
    champ_source.save!
  end

  def call(ref = reference) = described_class.new(referentiel_champ:, cible:, reference: ref).call
  def blob_ids(champ) = Champ.find(champ.id).piece_justificative_file.blobs.map(&:id).sort
  def source_blob_ids = champ_source.reload.piece_justificative_file.blobs.map(&:id).sort

  it 'rattache tous les fichiers du champ source (mêmes blobs) et pose prefilled' do
    expect(call).to eq(:rattache)
    expect(blob_ids(cible)).to eq(source_blob_ids)
    expect(source_blob_ids.size).to eq(2)
    expect(Champ.find(cible.id).prefilled).to be(true)
  end

  it 'exclut un blob infecté' do
    infecte = champ_source.piece_justificative_file.blobs.last
    infecte.update_column(:virus_scan_result, ActiveStorage::VirusScanner::INFECTED)
    call
    expect(blob_ids(cible)).to eq(source_blob_ids - [infecte.id])
  end

  context 'hors DLNUF' do
    let(:dlnuf) { nil }

    it { expect(call).to eq(:non_dlnuf) }
  end

  it 'refuse une référence illisible' do
    expect(call('md:abc:12')).to eq(:reference_illisible)
    expect(call("md:#{source.id}:1:ligne avec espace")).to eq(:reference_illisible)
  end

  it 'ne rattache rien depuis un dossier inexistant, en brouillon ou identique à la cible' do
    expect(call("md:0:#{tdc_source.('Statuts').stable_id}")).to eq(:source_introuvable)
    source.update_column(:state, 'brouillon')
    expect(call).to eq(:source_introuvable)
    expect(call("md:#{dossier.id}:#{tdc_cible.stable_id}")).to eq(:source_introuvable)
  end

  it 'ne rattache rien depuis un dossier terminé supprimé par l’usager' do
    source.update_columns(state: 'accepte', processed_at: Time.zone.now, hidden_by_user_at: Time.zone.now, hidden_by_reason: 'user_request')
    expect(call).to eq(:source_introuvable)
    expect(blob_ids(cible)).to eq([])
  end

  it 'refuse le dossier d’un autre titulaire et alerte' do
    source.update_column(:user_id, create(:user).id)
    allow(Sentry).to receive(:capture_message)
    expect(call).to eq(:autre_titulaire)
    expect(Sentry).to have_received(:capture_message).with(/autre titulaire/, extra: hash_including(:cible_dossier_id, :source_dossier_id))
  end

  it 's’arrête sans exception ni alerte si le titulaire source n’a plus de compte' do
    source.update_column(:user_id, nil)
    allow(Sentry).to receive(:capture_message)
    expect(call).to eq(:autre_titulaire)
    expect(Sentry).not_to have_received(:capture_message)
  end

  it 'ne rattache pas un titre d’identité' do
    expect(call("md:#{source.id}:#{tdc_source.('Identité').stable_id}")).to eq(:vide)
    expect(blob_ids(cible)).to eq([])
  end

  it 'lit la pièce d’une ligne de bloc répétable' do
    tdc_membre = tdc_source.('Pièce du membre')
    row_id = source.repetition_row_ids(tdc_source.('Membres')).first
    attendu = source.project_champ(tdc_membre, row_id:).piece_justificative_file.blobs.map(&:id)
    expect(call("md:#{source.id}:#{tdc_membre.stable_id}:#{row_id}")).to eq(:rattache)
    expect(blob_ids(cible)).to eq(attendu.sort)
  end

  it 'remplace une cible déjà préremplie' do
    cible.piece_justificative_file.attach(io: StringIO.new('ancien'), filename: 'ancien.pdf', content_type: 'application/pdf')
    cible.update!(prefilled: true)
    perform_enqueued_jobs { expect(call).to eq(:rattache) }
    expect(blob_ids(cible)).to eq(source_blob_ids)
  end

  it 'ne touche pas une cible remplie à la main' do
    cible.piece_justificative_file.attach(io: StringIO.new('manuel'), filename: 'manuel.pdf', content_type: 'application/pdf')
    cible.update!(prefilled: false)
    avant = blob_ids(cible)
    expect(call).to eq(:cible_manuelle)
    expect(blob_ids(cible)).to eq(avant)
  end

  it 'vide une cible préremplie quand la référence est vide' do
    call
    perform_enqueued_jobs { expect(call('')).to eq(:vide) }
    expect(blob_ids(cible)).to eq([])
    expect(Champ.find(cible.id).prefilled).to be(false)
  end
end
