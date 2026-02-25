# frozen_string_literal: true

class MigrateReferentielDePolynesieToBaserowReferentiel < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    table_ids = TypeDeChamp
      .where(type_champ: 'referentiel_de_polynesie')
      .pluck(Arel.sql("options->>'table_id'"))
      .compact
      .uniq
      .filter { |id| id.to_i > 0 }

    say "Found #{table_ids.size} unique table_ids to migrate"

    # Créer un BaserowReferentiel pour chaque table_id unique
    referentiel_by_table_id = {}

    table_ids.each do |table_id|
      referentiel = Referentiels::BaserowReferentiel.find_or_create_by!(url: "baserow://#{table_id}") do |r|
        r.name = SecureRandom.uuid
      end
      referentiel_by_table_id[table_id.to_s] = referentiel.id
      say "Created/found BaserowReferentiel ##{referentiel.id} for table_id #{table_id}"
    end

    # Lier chaque TypeDeChamp à son BaserowReferentiel
    updated_count = 0
    TypeDeChamp.where(type_champ: 'referentiel_de_polynesie').find_each do |tdc|
      table_id = tdc.options&.dig('table_id')&.to_s
      next if table_id.blank? || table_id.to_i <= 0

      referentiel_id = referentiel_by_table_id[table_id]
      next if referentiel_id.blank?

      # Utiliser update_column pour éviter les callbacks et validations
      tdc.update_column(:referentiel_id, referentiel_id)
      updated_count += 1
    end

    say "Linked #{updated_count} TypeDeChamp records to BaserowReferentiel"
  end

  def down
    # Supprimer les liens (on garde les Referentiels pour sécurité des données)
    TypeDeChamp.where(type_champ: 'referentiel_de_polynesie').update_all(referentiel_id: nil)
    say "Unlinked all referentiel_de_polynesie TypeDeChamp from BaserowReferentiel"

    # Optionnel : supprimer les BaserowReferentiel créés (commenté par sécurité)
    # Referentiels::BaserowReferentiel.destroy_all
  end
end
