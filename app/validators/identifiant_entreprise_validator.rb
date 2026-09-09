# frozen_string_literal: true

# pf: valide un identifiant d'entreprise, Tahiti (ISPF) ou SIRET (API Entreprise).
#
# Remplace l'ancien app/validators/siret_validator.rb, qui portait le même nom
# de classe que la gem siret_validator d'upstream : si un merge réintroduit la
# gem au Gemfile, elle définit la constante au boot et le fichier applicatif est
# ignoré, désactivant silencieusement la validation des numéros Tahiti. Le nom
# distinct supprime définitivement cette collision.
#
# Utilisé par : Service, Siret, Champs::SiretChamp.
class IdentifiantEntrepriseValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    identifiant = IdentifiantEntreprise.parse(value)
    return if identifiant.valide?

    record.errors.add(attribute, identifiant.erreur)
  end
end
