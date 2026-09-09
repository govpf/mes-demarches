# frozen_string_literal: true

describe APIEntreprise::API, 'recipient_for' do
  let(:api) { described_class.new(procedure.id) }
  let(:cible) { '41816609600051' }
  let(:siret_par_defaut) { '13000582000019' }

  # pf: API_ENTREPRISE_DEFAULT_SIRET n'est definie que dans le .env local, absent
  # en CI — ENV.fetch y leverait KeyError. On la stube donc plutot que de dependre
  # de l'environnement, d'autant que spec/lib/api_entreprise/api_spec.rb:121
  # l'ecrase globalement sans la restaurer.
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('API_ENTREPRISE_DEFAULT_SIRET').and_return(siret_par_defaut)
  end

  subject { api.send(:recipient_for, cible) }

  # pf: le recipient identifie l'administration demandeuse. API Entreprise exige
  # un SIRET francais a 14 chiffres et refuse tout autre format en 422/00210.
  context 'quand le service porte un numero Tahiti' do
    let(:procedure) { create(:procedure, service: create(:service, siret: 'G33972001')) }

    it 'retombe sur le SIRET par defaut plutot que d’envoyer un numero Tahiti' do
      expect(subject).to eq(siret_par_defaut)
      expect(IdentifiantEntreprise.parse(subject)).to be_siret
    end
  end

  context 'quand le service porte un SIRET francais' do
    let(:procedure) { create(:procedure, service: create(:service, siret: '30613890001294')) }

    it 'utilise le SIRET du service' do
      expect(subject).to eq('30613890001294')
    end
  end

  context 'quand le service n’a pas de numero' do
    # pf: un Service ne peut plus etre cree sans numero, mais d'anciennes lignes
    # en base en portent — on reproduit ce cas en contournant la validation.
    let(:service) { create(:service).tap { _1.update_columns(siret: nil) } }
    let(:procedure) { create(:procedure, service:) }

    it 'retombe sur le SIRET par defaut' do
      expect(subject).to eq(siret_par_defaut)
    end
  end
end
