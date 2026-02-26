# frozen_string_literal: true

class TypesDeChamp::ReferentielDePolynesieTypeDeChamp < TypesDeChamp::TypeDeChampBase
  # pf: support des tags avec colonnes personnalisées (ex: --commune/code_postal--)
  def champ_value_for_tag(champ, path = :value)
    return champ.value if path == :value

    # pf: mode upstream — lire depuis value_json
    if champ.value_json.present?
      jsonpath = "$.#{path}"
      return (champ.value_json[jsonpath] || '').to_s
    end

    # pf: fallback legacy
    champ.referentiel_item_value(path.to_s) || ''
  end

  # pf: même logique pour les exports
  alias champ_value_for_export champ_value_for_tag

  # pf: support colonnes Baserow dynamiques pour tags/exports
  def paths
    paths = super

    # pf: mode upstream — dériver depuis referentiel_mapping
    mapping = referentiel_mapping_displayable_for_instructeur
    if mapping.present?
      mapping.each do |jsonpath, opts|
        column = opts[:libelle] || jsonpath.delete_prefix('$.')
        paths << {
          libelle: "#{libelle} (#{column})",
          description: "#{description} (#{column})",
          path: column.to_sym,
          maybe_null: public? && !mandatory?
        }
      end
      return paths
    end

    # pf: fallback legacy
    instructeur_fields = fetch_instructeur_fields
    instructeur_fields&.each do |column|
      paths << {
        libelle: "#{libelle} (#{column})",
        description: "#{description} (#{column})",
        path: column.to_sym,
        maybe_null: public? && !mandatory?
      }
    end

    paths
  end

  private

  def fetch_instructeur_fields
    return [] if table_id.blank? || table_id.to_i <= 0

    Rails.cache.fetch("referentiel_de_polynesie/instructeur_fields/#{table_id}", expires_in: 1.hour) do
      fetch_instructeur_fields_from_baserow
    end
  end

  def fetch_instructeur_fields_from_baserow
    engine = ReferentielDePolynesie::API.engine
    unless engine
      Rails.logger.warn("ReferentielDePolynesie: Baserow non configuré (table_id=#{table_id})")
      return []
    end

    config = engine.config(table_id)
    unless config
      Rails.logger.error("ReferentielDePolynesie: config introuvable (table_id=#{table_id})")
      return []
    end

    model = engine.fields(config)
    unless model
      Rails.logger.error("ReferentielDePolynesie: échec récupération fields (table_id=#{table_id})")
      return []
    end

    engine.field_names(model, config['Champs instructeur']) || []
  rescue StandardError => e
    Rails.logger.error("ReferentielDePolynesie: erreur inattendue (table_id=#{table_id}): #{e.class} - #{e.message}")
    []
  end
end
