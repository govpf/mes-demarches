# frozen_string_literal: true

# pf: logique de configuration du mapping d'un champ referentiel_de_polynesie pour le MCP.
# Colonnes via Baserow (source supposée posée), validation d'éligibilité des cibles de
# pré-remplissage (réutilise la constante MAPPING_TYPE_TO_TYPE_DE_CHAMP + primitifs de
# coordonnée stables), build des entrées et nettoyage des colonnes disparues.
module Mcp
  class ReferentielMappingService
    class BaserowIndisponible < StandardError; end
    class ColonneInconnue < StandardError; end
    class CibleInvalide < StandardError; end

    def initialize(type_de_champ)
      @tdc = type_de_champ
      @draft = type_de_champ.revisions.last
    end

    # [{ nom:, type_mapping: }]
    def colonnes
      baserow_fields.map { |_id, f| { nom: f[:name] || f['name'], type_mapping: mapping_type_for(f) } }
    end

    def mapping_actuel
      @tdc.safe_referentiel_mapping
    end

    # colonnes_config: [{ colonne:, prefill_stable_id?, display_usager?, display_instructeur?, libelle? }]
    def configurer!(colonnes_config)
      cols_by_name = baserow_fields.values.index_by { |f| f[:name] || f['name'] }

      nouvelles = colonnes_config.each_with_object({}) do |cfg, acc|
        nom = cfg[:colonne].to_s
        field = cols_by_name[nom]
        raise ColonneInconnue, "Colonne « #{nom} » absente du référentiel Baserow." if field.nil?

        type_mapping = mapping_type_for(field)
        entry = { 'type' => type_mapping, 'libelle' => (cfg[:libelle].presence || nom) }

        if cfg[:prefill_stable_id].present?
          valider_cible!(cfg[:prefill_stable_id].to_s, type_mapping)
          entry['prefill'] = '1'
          entry['prefill_stable_id'] = cfg[:prefill_stable_id].to_s
        else
          entry['prefill'] = '0'
          entry['display_usager'] = cfg[:display_usager] ? '1' : '0'
          entry['display_instructeur'] = cfg[:display_instructeur] ? '1' : '0'
        end

        acc["$.#{nom}"] = entry
      end

      cleaned = prune_disparues(@tdc.safe_referentiel_mapping, cols_by_name.keys)
      @tdc.update!(referentiel_mapping: cleaned.deep_merge(nouvelles))
      @tdc
    end

    private

    def baserow_fields
      engine = ReferentielDePolynesie::API.engine
      raise BaserowIndisponible, "Baserow n'est pas configuré." if engine.nil?

      config = engine.config(@tdc.table_id)
      raise BaserowIndisponible, "Référentiel Baserow introuvable (table_id=#{@tdc.table_id})." if config.nil?

      fields = engine.fields(config)
      raise BaserowIndisponible, 'Impossible de récupérer les colonnes du référentiel Baserow.' if fields.nil?

      fields
    end

    # pf: baserow_type_to_mapping_type est une méthode de classe sur BaserowAPI
    def mapping_type_for(field)
      ReferentielDePolynesie::BaserowAPI.baserow_type_to_mapping_type(field)
    end

    def prune_disparues(mapping, noms_existants)
      cles_valides = noms_existants.map { |n| "$.#{n}" }
      mapping.reject { |jsonpath, _| jsonpath.start_with?('$.') && cles_valides.exclude?(jsonpath) }
    end

    # pf: éligibilité = type compatible (constante upstream) + cible située après le référentiel
    # dans le bon scope (public→public-après|privé ; privé→privé-après). Primitifs coordinate.* stables.
    def valider_cible!(stable_id, type_mapping)
      cible = eligible_target_tdcs.find { _1.stable_id.to_s == stable_id }
      raise CibleInvalide, "Le champ cible (#{stable_id}) doit être situé après le référentiel et de visibilité compatible." if cible.nil?

      allowed = Referentiels::ReferentielPrefillComponent::MAPPING_TYPE_TO_TYPE_DE_CHAMP[type_mapping.to_sym] || []
      unless allowed.include?(cible.type_champ)
        raise CibleInvalide, "Le type « #{cible.type_champ} » du champ cible n'est pas compatible avec la colonne (#{type_mapping}). Types compatibles : #{allowed.join(', ')}."
      end
    end

    def eligible_target_tdcs
      coordinate = @draft.coordinate_for(@tdc)
      coords =
        if @tdc.public?
          roots_after(coordinate, @draft.revision_types_de_champ.filter { _1.public? && _1.root? }) +
            @draft.revision_types_de_champ.filter { _1.private? && _1.root? }
        else
          roots_after(coordinate, @draft.revision_types_de_champ.filter { _1.private? && _1.root? })
        end
      coords.map(&:type_de_champ).reject { _1.stable_id == @tdc.stable_id }
    end

    def roots_after(coordinate, scoped_root_coordinates)
      scoped_root_coordinates.filter { _1.position > coordinate.position }
    end
  end
end
