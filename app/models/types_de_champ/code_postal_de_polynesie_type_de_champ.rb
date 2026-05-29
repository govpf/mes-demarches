# frozen_string_literal: true

class TypesDeChamp::CodePostalDePolynesieTypeDeChamp < TypesDeChamp::TextTypeDeChamp
  def paths
    paths = super
    paths.push({
      libelle: "#{libelle} (Commune)",
                 description: "#{description} (Commune)",
                 path: :commune,
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

  LABELS = ["", " (Commune)", " (Ile)", " (Archipel)"]

  def libelle_for_export(index)
    libelle + LABELS[index]
  end

  # pf: expose les sous-champs (commune, ile, archipel) comme JSONPathColumn
  # lues depuis value_json (cache peuplé par CodePostalDePolynesieChamp#on_value_change).
  # Cf. CommuneDePolynesieTypeDeChamp.
  def columns(procedure:, displayable: true, prefix: nil)
    super.concat([
      polynesie_json_column(procedure:, prefix:, path: 'commune', suffix: 'Commune', type: :text),
      polynesie_json_column(procedure:, prefix:, path: 'ile', suffix: 'Ile', type: :text),
      polynesie_json_column(procedure:, prefix:, path: 'archipel', suffix: 'Archipel', type: :text),
    ])
  end

  def champ_value(champ)
    city = APIGeo::API.commune_by_postal_code_city_label(champ.value)
    city ? city[:code_postal].to_s : ''
  end

  def champ_value_for_export(champ, path = :value)
    champ_value_for_tag(champ, path)
  end

  def champ_value_for_tag(champ, path = :value)
    if champ.value.present? && (city = APIGeo::API.commune_by_postal_code_city_label(champ.value))
      path = :code_postal if path == :value
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
