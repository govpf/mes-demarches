# frozen_string_literal: true

class FormulaExpressionService
  class << self
    def convert_to_stable_ids(expression, revision)
      return ['', []] if expression.blank?

      dependencies = []
      stable_expr = expression.gsub(/\{([^}]+)\}/) do |match|
        libelle = $1.strip
        tdc = find_type_de_champ_by_libelle(libelle, revision)

        if tdc
          dependencies << tdc.stable_id
          "{tdc#{tdc.stable_id}}"
        else
          match # Garde l'original si pas trouvé
        end
      end

      [stable_expr, dependencies]
    end

    def convert_to_libelles(stable_expression, revision)
      return '' if stable_expression.blank?

      # pf: Support both new format ({tdc123}, {tdc123/path}) and old format ({123})
      stable_expression.gsub(/\{([^}]+)\}/) do |match|
        ref = $1.strip

        # New format: {tdc123} or {tdc123/path}
        if ref.match?(/^tdc(\d+)(\/.*)?/)
          stable_id = ref.match(/^tdc(\d+)/)[1].to_i
          path_match = ref.match(/^tdc\d+\/(.*)/)
          path = path_match ? path_match[1] : nil
          tdc = find_type_de_champ_by_stable_id(stable_id, revision)

          if tdc && path
            # Sub-property: find the label for the path
            path_label = find_path_label(tdc, path)
            path_label ? "{#{path_label}}" : match
          elsif tdc
            "{#{tdc.libelle}}"
          else
            match
          end
        # Old format: {123}
        elsif ref.match?(/^\d+$/)
          stable_id = ref.to_i
          tdc = find_type_de_champ_by_stable_id(stable_id, revision)
          tdc ? "{#{tdc.libelle}}" : match
        else
          # System columns like {dossier_number} - keep as is
          match
        end
      end
    end

    private

    def find_type_de_champ_by_libelle(libelle, revision)
      revision.types_de_champ.find { |tdc| tdc.libelle&.strip&.casecmp?(libelle.strip) }
    end

    def find_type_de_champ_by_stable_id(stable_id, revision)
      revision.types_de_champ.find { |tdc| tdc.stable_id == stable_id }
    end

    # pf: Find the human-readable label for a sub-property path
    def find_path_label(tdc, path)
      case tdc.type_champ
      when 'numero_dn'
        { 'date_de_naissance' => 'Date de naissance' }[path]
      when 'code_postal_de_polynesie'
        { 'commune' => 'Commune', 'ile' => 'Île', 'archipel' => 'Archipel' }[path]
      when 'referentiel_de_polynesie'
        # For referentiels, the path IS the column name (it's already the label)
        path
      when 'siret', 'rna'
        { 'code_naf' => 'Code NAF', 'raison_sociale' => 'Raison sociale', 'adresse' => 'Adresse' }[path]
      else
        nil
      end
    end
  end
end
