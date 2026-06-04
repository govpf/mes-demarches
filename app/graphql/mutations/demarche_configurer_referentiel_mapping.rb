# frozen_string_literal: true

# pf: configure le mapping d'un champ referentiel_de_polynesie (prefill / rapatriement) via le MCP.
module Mutations
  class DemarcheConfigurerReferentielMapping < Mutations::DemarcheChampMutation
    class ColonneInput < Types::BaseInputObject
      graphql_name 'McpReferentielColonneInput'
      argument :colonne, String, "Nom de la colonne Baserow.", required: true
      argument :prefill_stable_id, String, "Si fourni : pré-remplit ce champ.", required: false
      argument :display_usager, Boolean, required: false
      argument :display_instructeur, Boolean, required: false
      argument :libelle, String, required: false
    end

    description "Configurer le mapping d'un champ référentiel (pré-remplir / rapatrier)."

    argument :stable_id, String, "stable_id du champ référentiel.", required: true
    argument :colonnes, [ColonneInput], required: true

    def resolve(demarche:, stable_id:, colonnes:)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      coordinate, tdc = procedure.draft_revision.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if coordinate.nil?
      return { errors: ["Le champ \"#{tdc.libelle}\" n'est pas un référentiel de Polynésie."] } unless tdc.type_champ == 'referentiel_de_polynesie'

      # pf: graphql-ruby 2.x InputObject#to_h retourne des clés symboles snake_case
      # (:colonne, :prefill_stable_id, :display_usager, :display_instructeur, :libelle)
      # — compatible avec ce qu'attend Mcp::ReferentielMappingService#configurer!
      ::Mcp::ReferentielMappingService.new(tdc).configurer!(colonnes.map(&:to_h))
      { champ_stable_id: stable_id.to_s }
    rescue ::Mcp::ReferentielMappingService::BaserowIndisponible,
           ::Mcp::ReferentielMappingService::ColonneInconnue,
           ::Mcp::ReferentielMappingService::CibleInvalide => e
      { errors: [e.message] }
    end
  end
end
