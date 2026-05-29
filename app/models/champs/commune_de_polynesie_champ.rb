# frozen_string_literal: true

class Champs::CommuneDePolynesieChamp < Champs::TextChamp
  # pf: value_json = cache normalisé des sous-champs (commune, ile, code_postal,
  # archipel), dérivés de `value` via APIGeo. Permet aux JSONPathColumn (filtres,
  # tableaux instructeur, exports template, formules) de lire ces sous-champs.
  # APIGeo reste la source (cf. type.champ_value_for_tag) ; value_json en est le
  # cache, peuplé à la sauvegarde et rattrapé par PopulateCommunePolynesieValueJSONTask.
  store_accessor :value_json, :archipel, :ile, :code_postal, :commune
  before_save :on_value_change, if: :should_refresh_after_value_change?

  def self.options
    APIGeo::API.communes_de_polynesie
  end

  def island = type_de_champ.champ_value_for_tag(self, :ile)

  def postal_code = type_de_champ.champ_value_for_tag(self, :code_postal)

  def name = type_de_champ.champ_value_for_tag(self, :value)

  def archipelago = archipel

  def self.disabled_options
    options.filter { |v| (v =~ /^--.*--$/).present? }
  end

  def archipel?
    archipel.present?
  end

  private

  def on_value_change
    if value.blank?
      self.archipel = self.ile = self.code_postal = self.commune = nil
      return
    end

    city = APIGeo::API.commune_by_city_postal_code(value)

    if city.present?
      self.archipel = city[:archipel]
      self.ile = city[:ile]
      self.code_postal = city[:code_postal]
      self.commune = city[:commune]
    else
      self.archipel = self.ile = self.code_postal = self.commune = nil
    end
  end

  def should_refresh_after_value_change?
    # pf: rafraîchir le cache value_json si pas encore peuplé (ile absente) ou
    # si la commune sélectionnée a changé.
    ile.blank? || value_changed?
  end
end
