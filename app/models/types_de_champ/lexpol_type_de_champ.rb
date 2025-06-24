# frozen_string_literal: true

class TypesDeChamp::LexpolTypeDeChamp < TypesDeChamp::TypeDeChampBase
  def paths
    paths = super
    paths.push({
      libelle: "#{libelle} (statut)",
      description: "#{description} (statut)",
      path: :lexpol_status,
      maybe_null: public? && !mandatory?
    })
    paths.push({
      libelle: "#{libelle} (lien dossier)",
      description: "#{description} (lien dossier)",
      path: :lexpol_dossier_url,
      maybe_null: public? && !mandatory?
    })
    paths.push({
      libelle: "#{libelle} (lien arrêté)",
      description: "#{description} (lien arrêté)",
      path: :lexpol_arrete_lien,
      maybe_null: public? && !mandatory?
    })
    paths
  end

  class << self
    def champ_value_for_api(champ, version = 2)
      champ.value
    end

    def champ_value_for_export(champ, path = :value)
      champ_value_for_tag(champ, path)
    end

    def champ_value_for_tag(champ, path = :value)
      case path
      when :value
        champ.value || '[NOR Lexpol non disponible]'
      when :lexpol_status
        champ.lexpol_status || '[statut Lexpol non disponible]'
      when :lexpol_dossier_url
        champ.lexpol_dossier_url || '[lien dossier Lexpol non disponible]'
      when :lexpol_arrete_lien
        champ.lexpol_arrete_lien || '[lien arrêté Lexpol non disponible]'
      else
        ''
      end
    end
  end

  def lexpol_mapping
    data && data['lexpol_mapping'] || ""
  end

  def lexpol_mapping=(value)
    self.data ||= {}
    self.data['lexpol_mapping'] = value
  end

  def lexpol_modele
    data && data['lexpol_modele'] || ""
  end

  def lexpol_modele=(value)
    self.data ||= {}
    self.data['lexpol_modele'] = value
  end
end
