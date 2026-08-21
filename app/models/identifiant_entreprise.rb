# frozen_string_literal: true

# pf: source unique de vérité pour la nature d'un identifiant d'entreprise.
#
# Deux référentiels cohabitent :
# - le numéro Tahiti de l'ISPF (référentiel i-taiete), 6 à 9 caractères
# - le SIRET métropolitain (API Entreprise), 14 chiffres
#
# Avant ce value object, la règle était réimplémentée dans sept fichiers avec
# quatorze comparaisons de longueur divergentes. Tout site qui doit savoir
# « Tahiti ou SIRET ? » passe désormais par ici.
class IdentifiantEntreprise
  # Les trois expressions sont mutuellement exclusives par construction :
  # elles n'acceptent pas les mêmes longueurs.
  TAHITI_PARTIEL = /\A[0-9A-Z]\d{5,7}\z/ # 6 à 8 car. : G33972, G339720, G3397200
  TAHITI_COMPLET = /\A[0-9A-Z]\d{8}\z/   # 9 car.     : G33972001
  SIRET          = /\A\d{14}\z/          # 14 chiffres

  # Seule exception à la règle de Luhn parmi les SIRET français.
  LA_POSTE_SIREN = '356000000'

  ANNUAIRE_ISPF = 'https://www.ispf.pf/rte'
  ANNUAIRE_FR   = 'https://annuaire-entreprises.data.gouv.fr/etablissement'

  attr_reader :valeur

  def self.parse(saisie)
    new(saisie.to_s.gsub(/[[:space:]-]/, '').upcase)
  end

  def initialize(valeur)
    @valeur = valeur
    freeze
  end

  # --- nature (mutuellement exclusifs) ---

  def tahiti_partiel? = valeur.match?(TAHITI_PARTIEL)

  def tahiti_complet? = valeur.match?(TAHITI_COMPLET)

  def siret? = valeur.match?(SIRET) && luhn_valide?

  # --- dérivés ---

  def tahiti? = tahiti_partiel? || tahiti_complet?

  def valide? = tahiti? || siret?

  # :checksum quand le format est bon mais la clé de Luhn fausse,
  # :length dans tous les autres cas d'invalidité.
  def erreur
    return nil if valide?
    return :checksum if valeur.match?(SIRET)
    :length
  end

  def source
    return :ispf if tahiti?
    return :api_entreprise if siret?
    nil
  end

  def adapter_klass
    case source
    when :ispf then APIEntreprise::PfEtablissementAdapter
    when :api_entreprise then APIEntreprise::EtablissementAdapter
    end
  end

  def i18n_key
    case source
    when :ispf then :tahiti
    when :api_entreprise then :siret
    end
  end

  def format_lisible
    if siret?
      "#{valeur[0..2]} #{valeur[3..5]} #{valeur[6..8]} #{valeur[9..]}"
    elsif tahiti? && valeur.length > 6
      "#{valeur[0..5]}-#{valeur[6..]}"
    else
      valeur
    end
  end

  def annuaire_url
    if tahiti_complet?
      "#{ANNUAIRE_ISPF}/attestation/#{valeur[0..5]}/#{valeur[6..]}"
    elsif siret?
      "#{ANNUAIRE_FR}/#{valeur}"
    else
      ANNUAIRE_ISPF
    end
  end

  private

  def luhn_valide?
    return true if valeur[0..8] == LA_POSTE_SIREN

    somme = valeur.reverse.each_char.map(&:to_i).each_with_index.sum do |chiffre, index|
      double = index.odd? ? chiffre * 2 : chiffre
      double < 10 ? double : double - 9
    end
    (somme % 10).zero?
  end
end
