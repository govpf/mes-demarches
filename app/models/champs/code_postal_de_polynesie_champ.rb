# frozen_string_literal: true

class Champs::CodePostalDePolynesieChamp < Champs::TextChamp
  # pf: value_json = cache normalisé des sous-champs (commune, ile, code_postal,
  # archipel), dérivés de `value` via APIGeo. Cf. CommuneDePolynesieChamp.
  store_accessor :value_json, :archipel, :ile, :code_postal, :commune
  before_save :on_value_change, if: :should_refresh_after_value_change?

  def self.options
    APIGeo::API.codes_postaux_de_polynesie
  end

  def island = type_de_champ.champ_value_for_tag(self, :ile)

  def postal_code = type_de_champ.champ_value_for_tag(self, :value)

  def name = type_de_champ.champ_value_for_tag(self, :commune)

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

    city = APIGeo::API.commune_by_postal_code_city_label(value)

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
    ile.blank? || value_changed?
  end
end
