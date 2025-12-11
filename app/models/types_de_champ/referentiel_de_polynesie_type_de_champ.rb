# frozen_string_literal: true

class TypesDeChamp::ReferentielDePolynesieTypeDeChamp < TypesDeChamp::TypeDeChampBase
  # pf: support des tags avec colonnes personnalisées (ex: --commune/code_postal--)
  def champ_value_for_tag(champ, path = :value)
    path == :value ? champ.value : (champ.referentiel_item_value(path.to_s) || '')
  end

  # pf: même logique pour les exports
  alias champ_value_for_export champ_value_for_tag

  # pf: support colonnes Baserow dynamiques pour tags/exports
  def paths
    @paths ||= begin
      paths = super

      Champ.where(stable_id:)
        .where.not(data: nil)
        .where("data ? 'instructeur_fields'")
        .first&.data&.dig("instructeur_fields")&.each do |column|
          paths << {
            libelle: "#{libelle} (#{column})",
            description: "#{description} (#{column})",
            path: column.to_sym,
            maybe_null: public? && !mandatory?
          }
        end

      paths
    end
  end
end
