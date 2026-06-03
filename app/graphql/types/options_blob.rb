# frozen_string_literal: true

# pf: scalaire JSON générique pour transmettre un objet d'options arbitraire (validé
# côté serveur contre les clés autorisées du type de champ). Utilisé par le MCP.
module Types
  class OptionsBlob < Types::BaseScalar
    description "Objet JSON arbitraire (clé/valeur)."

    def self.coerce_input(value, _context)
      value
    end

    def self.coerce_result(value, _context)
      value
    end
  end
end
