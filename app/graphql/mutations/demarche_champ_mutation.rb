# frozen_string_literal: true

# pf: classe de base des mutations MCP de construction de structure de démarche.
# Factorise l'argument `demarche`, le format de retour, et la résolution + autorisation
# de la procédure. Le contrôle `write_access` du token est assuré par BaseMutation#ready?.
module Mutations
  class DemarcheChampMutation < Mutations::BaseMutation
    argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true

    field :champ_stable_id, String, "Le stable_id du champ concerné.", null: true
    field :errors, [Types::ValidationErrorType], null: true

    private

    # Retourne [procedure, nil] si autorisée, sinon [nil, "message d'erreur"].
    def find_authorized_procedure(demarche)
      number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
      procedure = Procedure.find_by(id: number)

      return [nil, "La démarche \"#{number}\" n'existe pas."] if procedure.nil?
      return [nil, "Vous n'avez pas accès à la démarche \"#{number}\"."] unless context.authorized_demarche?(procedure)

      [procedure, nil]
    end

    REFERENTIEL_SOURCE_KEYS = %w[table_id mode hint].freeze
    # pf: champs dérivés inférés automatiquement par validate_expression — silencieusement ignorés
    # si Claude les passe quand même (via .passthrough() sur le schéma MCP).
    DERIVED_OPTIONS = %w[formule_output_type formule_deps].freeze

    # pf: pour un champ RDP, extrait table_id/mode/hint des options et configure la source
    # (BaserowReferentiel) via le service. Ces attributs vivent sur le BaserowReferentiel lié,
    # pas dans le jsonb options — ils ne passent donc PAS par appliquer_options! (qui les
    # rejetterait pour mode/hint, et qui ne sait pas faire le dual-write pour table_id).
    # Retourne [options_restantes, erreur|nil].
    def extraire_et_appliquer_source_referentiel!(type_de_champ, options)
      return [options, nil] unless type_de_champ.type_champ == 'referentiel_de_polynesie'
      return [options, nil] if options.blank?

      opts = options.to_h.deep_dup
      source = {}
      REFERENTIEL_SOURCE_KEYS.each do |k|
        source[k] = opts.delete(k) if opts.key?(k)
        source[k] = opts.delete(k.to_sym) if opts.key?(k.to_sym)
      end
      return [options, nil] if source.empty?

      ::Mcp::ReferentielMappingService.new(type_de_champ).configurer_source!(
        table_id: source['table_id'],
        mode:     source['mode'],
        hint:     source['hint']
      )
      [opts, nil]
    rescue ::Mcp::ReferentielMappingService::SourceInvalide, ::Mcp::ReferentielMappingService::BaserowIndisponible => e
      [options, e.message]
    end

    # pf: valide + normalise + applique un blob d'options sur un type de champ.
    # Réutilise TypeDeChamp::OPTS_BY_TYPE (map canonique, options standard + PF) pour
    # rejeter toute clé non autorisée. Retourne nil si OK, ou un message d'erreur.
    # N'applique que sur le tdc (en mémoire) ; l'appelant doit sauvegarder.
    def appliquer_options!(type_de_champ, options, revision)
      return nil if options.blank?

      unless options.is_a?(Hash)
        return "Le paramètre « options » doit être un objet JSON (clé/valeur), reçu : #{options.class}."
      end

      options = options.reject { |k, _| DERIVED_OPTIONS.include?(k.to_s) }

      allowed = TypeDeChamp::OPTS_BY_TYPE.fetch(type_de_champ.type_champ) { [] }.map(&:to_s)
      unknown = options.keys.map(&:to_s) - allowed
      if unknown.any?
        return "Options non autorisées pour le type « #{type_de_champ.type_champ} » : #{unknown.join(', ')}." \
               " Options valides : #{allowed.empty? ? '(aucune)' : allowed.join(', ')}."
      end

      normalized = options.to_h.to_h do |key, value|
        normalized_value = case value
        when true then '1'
        when false then '0'
        when Numeric then value.to_s
        else value
        end
        [key.to_s, normalized_value]
      end

      # pf: pour une formule, convertir les références libellé {Libellé} en tokens stable_id
      # {tdcNNN} (forme canonique). Sans ça, validate_expression ne détecte aucune dépendance
      # (formule_deps['champs'] vide) → aucun déclencheur de recalcul et la formule reste inerte
      # jusqu'à une ré-édition dans l'UI. convert_to_stable_ids garde les références inconnues
      # telles quelles (idempotent pour un {tdcNNN} déjà converti).
      if type_de_champ.formule? && normalized['formule_expression'].present?
        converted, = FormulaExpressionService.convert_to_stable_ids(normalized['formule_expression'], revision)
        normalized['formule_expression'] = converted
      end

      type_de_champ.editable_options = normalized
      nil
    end
  end
end
