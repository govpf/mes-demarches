# frozen_string_literal: true

# Migration pour convertir min/max vers range_date/start_date/end_date pour les champs Date
#
# Contexte :
# - PF utilisait :min et :max dans TypeDeChamp.options pour les dates
# - Upstream utilise :range_date, :start_date, :end_date
# - Les deux systèmes coexistaient, créant une double validation
#
# Cette migration convertit automatiquement les attributs pour tous les champs existants

class MigrateDateMinMaxToRangeDate < ActiveRecord::Migration[7.0]
  def up
    # Récupérer tous les TypeDeChamp de type date ou datetime
    # qui ont des options min ou max
    TypeDeChamp.where(type_champ: ['date', 'datetime']).find_each do |tdc|
      next if tdc.options.blank?

      options = tdc.options.dup
      changed = false

      # Si min ou max présent, activer range_date et convertir
      if options.key?('min') || options.key?('max')
        # Activer range_date
        options['range_date'] = '1'

        # Convertir 'min' en 'start_date' si présent
        if options.key?('min')
          options['start_date'] = options.delete('min')
          changed = true
        end

        # Convertir 'max' en 'end_date' si présent
        if options.key?('max')
          options['end_date'] = options.delete('max')
          changed = true
        end

        # Sauvegarder seulement si des changements ont été faits
        if changed
          tdc.update_column(:options, options)
          puts "✅ TypeDeChamp ##{tdc.id} (#{tdc.libelle}) migré : min/max → start_date/end_date"
        end
      end
    end
  end

  def down
    # Rollback : renommer start_date/end_date vers min/max
    TypeDeChamp.where(type_champ: ['date', 'datetime']).find_each do |tdc|
      next if tdc.options.blank?

      options = tdc.options.dup
      changed = false

      # Convertir 'start_date' en 'min'
      if options.key?('start_date')
        options['min'] = options.delete('start_date')
        changed = true
      end

      # Convertir 'end_date' en 'max'
      if options.key?('end_date')
        options['max'] = options.delete('end_date')
        changed = true
      end

      # Supprimer range_date et date_in_past (pas dans l'ancien système PF)
      if options.key?('range_date')
        options.delete('range_date')
        changed = true
      end

      if options.key?('date_in_past')
        options.delete('date_in_past')
        changed = true
      end

      if changed
        tdc.update_column(:options, options)
        puts "⬅️  TypeDeChamp ##{tdc.id} (#{tdc.libelle}) rollback : start_date/end_date → min/max"
      end
    end
  end
end
