# frozen_string_literal: true

class TypesDeChamp::NumeroDnTypeDeChamp < TypesDeChamp::TypeDeChampBase
  def paths
    paths = super
    paths.push({
      libelle: "#{libelle} (Date de naissance)",
      description: "#{description} (Date de naissance)",
      path: :date_de_naissance,
      example: Date.today,
      maybe_null: public? && !mandatory?,
    })
    paths
  end

  # pf: expose la date de naissance comme JSONPathColumn (lue depuis value_json,
  # où NumeroDnChamp stocke déjà numero_dn + date_de_naissance via store_accessor).
  # Aligne le DN sur le pattern columns d'upstream (cf. siret) : rend la date de
  # naissance disponible aux filtres, tableaux instructeur, exports template ET
  # formules ({Numéro DN/date_de_naissance}).
  def columns(procedure:, displayable: true, prefix: nil)
    super.push(
      Columns::JSONPathColumn.new(
        procedure_id: procedure.id,
        stable_id:,
        tdc_type: type_champ,
        label: [prefix, libelle, 'Date de naissance'].compact.join(' – '),
        type: :date,
        jsonpath: '$.date_de_naissance',
        displayable: true,
        mandatory: mandatory?
      )
    )
  end

  def champ_value(champ)
    champ.numero_dn
  end

  def champ_value_for_export(champ, path = :value)
    case path
    when :value
      champ.numero_dn
    when :date_de_naissance
      champ.date_de_naissance&.to_date
    end
  end

  def champ_value_for_tag(champ, path = :value)
    case path
    when :value
      champ.numero_dn || ''
    when :date_de_naissance
      champ.date_de_naissance ? I18n.l(champ.date_de_naissance.to_date, format: '%d %B %Y') : ''
    end
  end
end
