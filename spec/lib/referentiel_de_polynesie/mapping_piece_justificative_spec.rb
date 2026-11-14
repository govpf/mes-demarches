# frozen_string_literal: true

describe ReferentielDePolynesie::MappingPieceJustificative do
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :referentiel_de_polynesie, libelle: 'Association', table_id: '24' },
      { type: :piece_justificative, libelle: 'Statuts' },
      { type: :titre_identite, libelle: 'Identité' },
      { type: :piece_justificative, libelle: 'Pièce d’identité', nature: 'TITRE_IDENTITE' },
      { type: :text, libelle: 'Nom' },
      { type: :repetition, libelle: 'Membres', children: [{ type: :piece_justificative, libelle: 'Pièce du membre' }] },
    ])
  end
  let(:revision) { procedure.draft_revision }
  let(:tdc) { -> (libelle) { revision.types_de_champ.find { _1.libelle == libelle } } }
  let(:referentiel_tdc) { tdc.('Association') }

  def erreurs(mapping) = described_class.erreurs(type_de_champ: referentiel_tdc, mapping:, revision:)
  def pj(stable_id, **opts) = { 'type' => 'piece_justificative', 'prefill' => '1', 'prefill_stable_id' => stable_id.to_s }.merge(opts)

  before { allow(ReferentielDePolynesie::API).to receive(:colonnes_reference_pj).with('24').and_return(['Statuts']) }

  it 'accepte une colonne de référence vers une PJ' do
    expect(erreurs('$.Statuts' => pj(tdc.('Statuts').stable_id))).to eq([])
  end

  it 'ne consulte pas Baserow pour un mapping sans PJ' do
    expect(erreurs('$.Nom' => { 'type' => 'string', 'prefill' => '1', 'prefill_stable_id' => tdc.('Nom').stable_id.to_s })).to eq([])
    expect(ReferentielDePolynesie::API).not_to have_received(:colonnes_reference_pj)
  end

  it 'règle 1 : refuse le type PJ sur une colonne non marquée' do
    expect(erreurs('$.Nom' => pj(tdc.('Statuts').stable_id)).first).to include('« Nom »')
  end

  it 'règle 2 : refuse l’affichage d’une référence' do
    expect(erreurs('$.Statuts' => { 'type' => 'piece_justificative', 'prefill' => '0', 'display_usager' => '1' })).not_to be_empty
    expect(erreurs('$.Statuts' => { 'type' => 'piece_justificative', 'prefill' => '0', 'display_instructeur' => '1' })).not_to be_empty
  end

  it 'règle 3 : refuse une colonne texte vers une PJ ou un titre d’identité' do
    expect(erreurs('$.Nom' => { 'type' => 'string', 'prefill' => '1', 'prefill_stable_id' => tdc.('Statuts').stable_id.to_s })).not_to be_empty
    expect(erreurs('$.Nom' => { 'type' => 'string', 'prefill' => '1', 'prefill_stable_id' => tdc.('Identité').stable_id.to_s })).not_to be_empty
  end

  it 'règle 4 : refuse une référence vers autre chose qu’une PJ' do
    expect(erreurs('$.Statuts' => pj(tdc.('Nom').stable_id))).not_to be_empty
    expect(erreurs('$.Statuts' => pj(tdc.('Identité').stable_id))).not_to be_empty
    expect(erreurs('$.Statuts' => pj(tdc.('Pièce d’identité').stable_id))).not_to be_empty
  end

  it 'règle 5 : refuse une PJ dans un bloc répétable quand le référentiel est à la racine' do
    expect(erreurs('$.Statuts' => pj(tdc.('Pièce du membre').stable_id))).not_to be_empty
  end

  it 'ignore une cible conservée alors que le préremplissage est décoché' do
    expect(erreurs('$.Nom' => { 'type' => 'string', 'prefill' => '0', 'prefill_stable_id' => tdc.('Statuts').stable_id.to_s })).to eq([])
  end
end
