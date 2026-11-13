# frozen_string_literal: true

require 'rails_helper'

describe ReferentielDePolynesie::Marqueur do
  def parse(texte) = described_class.parse(texte)

  it { expect(parse(nil)).to be_nil }
  it { expect(parse('')).to be_nil }
  it { expect(parse("Texte libre\nsans marqueur")).to be_nil }

  it 'lit la ligne machine après une ligne humaine' do
    expect(parse("Référentiel DLNUF : lignes effacées.\nmes-demarches: referentiel=DLNUF; proprietaire=12345"))
      .to eq('referentiel' => 'DLNUF', 'proprietaire' => '12345')
  end

  it 'ignore la casse du préfixe et des clés, et les espaces' do
    expect(parse("  MES-DEMARCHES:  Referentiel = dlnuf ;PROPRIETAIRE=7 "))
      .to eq('referentiel' => 'dlnuf', 'proprietaire' => '7')
  end

  it 'conserve les clés inconnues sans erreur' do
    expect(parse('mes-demarches: referentiel=archive; futur=x')).to include('referentiel' => 'archive')
  end

  it 'ignore les segments vides' do
    expect(parse('mes-demarches: referentiel=archive;;')).to eq('referentiel' => 'archive')
  end

  it 'accepte contrat=1' do
    expect(parse('mes-demarches: referentiel=archive; contrat=1')).to include('contrat' => '1')
  end

  it('refuse une version de contrat inconnue') { expect(parse('mes-demarches: contrat=2')).to eq(:invalid) }
  it('refuse deux lignes marqueur') { expect(parse("mes-demarches: referentiel=archive\nmes-demarches: referentiel=DLNUF")).to eq(:invalid) }
  it('refuse une paire sans =') { expect(parse('mes-demarches: referentiel DLNUF')).to eq(:invalid) }
  it('refuse une clé vide') { expect(parse('mes-demarches: =DLNUF')).to eq(:invalid) }
  it('refuse une ligne vide après le préfixe') { expect(parse('mes-demarches:')).to eq(:invalid) }
  it('refuse un préfixe mal formé') { expect(parse('mes-demarches : referentiel=DLNUF')).to eq(:invalid) }
end
