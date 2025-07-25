# frozen_string_literal: true

class MigrateTableRowSelectorToReferentielDePolynesie < ActiveRecord::Migration[7.0]
  def up
    # Migrer les types_de_champ de table_row_selector vers referentiel_de_polynesie
    say "Migration des TypeDeChamp de table_row_selector vers referentiel_de_polynesie..."

    migrated_count = TypeDeChamp.where(type_champ: 'table_row_selector').update_all(type_champ: 'referentiel_de_polynesie')
    say "#{migrated_count} TypeDeChamp migrés."

    # Migrer les champs de Champs::TableRowSelectorChamp vers Champs::ReferentielDePolynesieChamp
    say "Migration des Champs de TableRowSelectorChamp vers ReferentielDePolynesieChamp..."

    safety_assured do
      execute <<-SQL.squish
        UPDATE champs#{' '}
        SET type = 'Champs::ReferentielDePolynesieChamp'
        WHERE type = 'Champs::TableRowSelectorChamp'
      SQL
    end

    say "Champs migrés avec succès."

    # Vérification de la migration
    remaining_types = TypeDeChamp.where(type_champ: 'table_row_selector').count
    remaining_champs = Champ.where(type: 'Champs::TableRowSelectorChamp').count

    if remaining_types > 0 || remaining_champs > 0
      raise "Migration incomplète: #{remaining_types} TypeDeChamp et #{remaining_champs} Champs restants"
    end

    say "Migration terminée avec succès!"
  end

  def down
    # Rollback : reconvertir vers table_row_selector
    say "Rollback: reconversion vers table_row_selector..."

    TypeDeChamp.where(type_champ: 'referentiel_de_polynesie').update_all(type_champ: 'table_row_selector')

    safety_assured do
      execute <<-SQL.squish
        UPDATE champs#{' '}
        SET type = 'Champs::TableRowSelectorChamp'
        WHERE type = 'Champs::ReferentielDePolynesieChamp'
      SQL
    end

    say "Rollback terminé."
  end
end
