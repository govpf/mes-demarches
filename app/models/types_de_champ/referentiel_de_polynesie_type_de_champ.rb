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

  # pf: colonnes affichées à l’instructeur (referentiel_mapping) pour les tags et les exports.
  # Le sous-chemin du tag est la colonne Baserow (clé de value_json) ; le libellé personnalisé ne
  # sert qu’à l’affichage. La colonne « Champs instructeur » de la table méta n’est plus lue :
  # T20260917migrateBaserowMetaColumnsToMappingTask a figé son contenu dans le mapping.
  def paths
    paths = super

    referentiel_mapping_displayable_for_instructeur.each do |jsonpath, opts|
      column = jsonpath.delete_prefix('$.')
      label = opts[:libelle].presence || column
      paths << {
        libelle: "#{libelle} (#{label})",
        description: "#{description} (#{label})",
        path: column.to_sym,
        maybe_null: public? && !mandatory?,
      }
    end

    paths
  end
end
