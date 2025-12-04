# frozen_string_literal: true

# Migration pour renommer les attributs PF min/max vers min_number/max_number
#
# Contexte :
# - PF utilisait :min et :max dans TypeDeChamp.options
# - Upstream utilise :min_number et :max_number
# - 13 champs en production utilisent actuellement min/max
#
# Cette migration renomme automatiquement les attributs pour tous les champs existants

class MigrateMinMaxToMinNumberMaxNumber < ActiveRecord::Migration[7.0]
  def up
    # Récupérer tous les TypeDeChamp de type integer_number ou decimal_number
    # qui ont des options min ou max
    TypeDeChamp.where(type_champ: ['integer_number', 'decimal_number']).find_each do |tdc|
      next if tdc.options.blank?

      options = tdc.options.dup
      changed = false

      # Renommer 'min' en 'min_number' si présent
      if options.key?('min')
        options['min_number'] = options.delete('min')
        changed = true
      end

      # Renommer 'max' en 'max_number' si présent
      if options.key?('max')
        options['max_number'] = options.delete('max')
        changed = true
      end

      # Activer range_number si min_number ou max_number est présent
      if options.key?('min_number') || options.key?('max_number')
        options['range_number'] = '1'
        changed = true
      end

      # Sauvegarder seulement si des changements ont été faits
      if changed
        tdc.update_column(:options, options)
        puts "✅ TypeDeChamp ##{tdc.id} (#{tdc.libelle}) migré : min/max → min_number/max_number"
      end
    end
  end

  def down
    # Rollback : renommer min_number/max_number vers min/max
    TypeDeChamp.where(type_champ: ['integer_number', 'decimal_number']).find_each do |tdc|
      next if tdc.options.blank?

      options = tdc.options.dup
      changed = false

      # Renommer 'min_number' en 'min'
      if options.key?('min_number')
        options['min'] = options.delete('min_number')
        changed = true
      end

      # Renommer 'max_number' en 'max'
      if options.key?('max_number')
        options['max'] = options.delete('max_number')
        changed = true
      end

      # Supprimer range_number et positive_number (pas dans l'ancien système PF)
      if options.key?('range_number')
        options.delete('range_number')
        changed = true
      end

      if options.key?('positive_number')
        options.delete('positive_number')
        changed = true
      end

      if changed
        tdc.update_column(:options, options)
        puts "⬅️  TypeDeChamp ##{tdc.id} (#{tdc.libelle}) rollback : min_number/max_number → min/max"
      end
    end
  end
end
