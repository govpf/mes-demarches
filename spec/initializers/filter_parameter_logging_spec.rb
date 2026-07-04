# frozen_string_literal: true

RSpec.describe 'filter_parameter_logging' do
  # pf: sécurité (F6) — les paramètres PII spécifiques PF (numéro DN, date de naissance)
  # passent en query string / POST sur les routes de vérification DN et doivent être
  # filtrés de la ligne `Parameters:` des logs Rails.
  #
  # On vérifie le comportement de filtrage plutôt que la forme brute de
  # config.filter_parameters : selon l'état d'initialisation (precompile_filter_parameters),
  # Rails peut renvoyer la liste de symboles ou des Regexp précompilées. Tester via
  # ActiveSupport::ParameterFilter est insensible à cette différence.
  it 'filtre les paramètres PII spécifiques Polynésie française' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    [:dn, :ddn, :numero_dn, :date_de_naissance].each do |param|
      filtered = filter.filter(param.to_s => 'valeur sensible')

      expect(filtered[param.to_s]).to eq('[FILTERED]'), "le paramètre #{param} devrait être filtré des logs"
    end
  end
end
