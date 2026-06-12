# frozen_string_literal: true

RSpec.describe 'filter_parameter_logging' do
  # pf: sécurité (F6) — les paramètres PII spécifiques PF (numéro DN, date de naissance)
  # passent en query string / POST sur les routes de vérification DN et doivent être
  # filtrés de la ligne `Parameters:` des logs Rails.
  it 'filtre les paramètres PII spécifiques Polynésie française' do
    filters = Rails.application.config.filter_parameters

    expect(filters).to include(:dn, :ddn, :numero_dn, :date_de_naissance)
  end
end
