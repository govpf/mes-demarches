# frozen_string_literal: true

class TypesDeChamp::CommuneDePolynesieTypeDeChamp < TypesDeChamp::TextTypeDeChamp
  def paths
    paths = super
    paths.push({
      libelle: "#{libelle} (Code postal)",
                 description: "#{description} (Code postal)",
                 path: :code_postal,
                 example: 1,
                 maybe_null: public? && !mandatory?,
    })
    paths.push({
      libelle: "#{libelle} (Ile)",
                 description: "#{description} (Ile)",
                 path: :ile,
                 example: "",
                 maybe_null: public? && !mandatory?,
    })
    paths.push({
      libelle: "#{libelle} (Archipel)",
                 description: "#{description} (Archipel)",
                 path: :archipel,
                 example: "",
                 maybe_null: public? && !mandatory?,
    })
    paths
  end

  def libelle_for_export(index)
    [libelle, "#{libelle} (Code postal)", "#{libelle} (Ile)", "#{libelle} (Archipel)"][index]
  end

  # pf: expose les sous-champs (code_postal, ile, archipel) comme JSONPathColumn
  # lues depuis value_json (cache peuplé par CommuneDePolynesieChamp#on_value_change).
  # Rend ces sous-champs disponibles aux filtres, tableaux instructeur, exports
  # template et formules ({Commune/ile}, etc.) — aligné sur le pattern siret.
  def columns(procedure:, displayable: true, prefix: nil)
    super.concat([
      polynesie_json_column(procedure:, prefix:, path: 'code_postal', suffix: 'Code postal', type: :integer),
      polynesie_json_column(procedure:, prefix:, path: 'ile', suffix: 'Ile', type: :text),
      polynesie_json_column(procedure:, prefix:, path: 'archipel', suffix: 'Archipel', type: :text),
    ])
  end

  def champ_value(champ)
    city = APIGeo::API.commune_by_city_postal_code(champ.value)
    city ? city[:commune] : ''
  end

  def champ_value_for_export(champ, path = :value)
    champ_value_for_tag(champ, path)
  end

  def champ_value_for_tag(champ, path = :value)
    if champ.value.present? && (city = APIGeo::API.commune_by_city_postal_code(champ.value))
      path = :commune if path == :value
      city[path]
    else
      ''
    end
  end

  private

  def polynesie_json_column(procedure:, prefix:, path:, suffix:, type:)
    Columns::JSONPathColumn.new(
      procedure_id: procedure.id,
      stable_id:,
      tdc_type: type_champ,
      label: [prefix, libelle, suffix].compact.join(' – '),
      type:,
      jsonpath: "$.#{path}",
      displayable: true,
      mandatory: mandatory?
    )
  end
end
