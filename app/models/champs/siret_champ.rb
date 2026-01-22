# frozen_string_literal: true

class Champs::SiretChamp < Champ
  include SiretChampEtablissementFetchableConcern

  validate :validate_siret_or_tahiti, if: :validate_champ_value?

  def search_terms
    etablissement.present? ? etablissement.search_terms : [value]
  end

  def mandatory_blank?
    mandatory? && value.blank?
  end

  private

  # pf: Unified validation for both SIRET (14 chars) and Tahiti numbers (9+ chars)
  def validate_siret_or_tahiti
    return if value.blank?

    # pf: Remove spaces and hyphens (Tahiti numbers can be formatted as 123456-789)
    cleaned_value = value.gsub(/[[:space:]-]/, "")

    # pf: Handle different number formats
    case cleaned_value.length
    when 0..8
      # pf: Partial Tahiti numbers - require selection from list
      errors.add(:value, "doit avoir 9 chiffres. Sélectionnez un établissement.") if etablissement.blank?
    when 9
      # pf: Complete Tahiti number (9 chars) - validate existence
      validate_etablissement_existence(cleaned_value)
    when 10..13
      # Invalid length for both SIRET and Tahiti
      errors.add(:value, :length)
    when 14
      validate_french_siret(cleaned_value)
    else
      errors.add(:value, :length)
    end
  end

  # pf: Validation for Tahiti numbers (9 chars) and partial SIRET
  def validate_etablissement_existence(siret_value)
    return if etablissement.present?

    errors.add(:value, :not_found)
  end

  def validate_french_siret(siret_value)
    return if etablissement.present?

    # pf: use custom SiretValidator instead of siret_validator gem
    # because Tahiti numbers (6 or 9 chars) are not supported by upstream gem
    validator = SiretValidator.new(attributes: { value: true })
    validator.validate_each(self, :value, siret_value)

    if errors.empty?
      errors.add(:value, :not_found)
    end
  end
end
