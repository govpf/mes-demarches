# frozen_string_literal: true

class PopulateReferentielMappingFromBaserow < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    TypeDeChamp.where(type_champ: 'referentiel_de_polynesie')
      .where.not(referentiel_id: nil)
      .find_each do |tdc|
        populate_mapping(tdc)
      rescue => e
        Rails.logger.error("Migration referentiel_mapping failed for TDC #{tdc.id}: #{e.message}")
      end
  end

  def down
    TypeDeChamp.where(type_champ: 'referentiel_de_polynesie')
      .update_all("options = jsonb_set(options, '{referentiel_mapping}', '{}')")
  end

  private

  def populate_mapping(tdc)
    referentiel = tdc.referentiel
    return unless referentiel.is_a?(Referentiels::BaserowReferentiel)

    config = referentiel.baserow_config
    return unless config

    field_metadata = ReferentielDePolynesie::BaserowAPI.fields(config)
    return unless field_metadata

    usager_names = ReferentielDePolynesie::BaserowAPI.field_names(field_metadata, config['Champs usager'])
    instructeur_names = ReferentielDePolynesie::BaserowAPI.field_names(field_metadata, config['Champs instructeur'])

    # Fetch sample row pour example_value
    service = Referentiels::BaserowService.new(referentiel:)
    service.validate_referentiel
    sample_row = referentiel.reload.last_response_body

    mapping = {}
    field_metadata.each_value do |meta|
      name = meta[:name]
      mapping["$.#{name}"] = {
        'type' => ReferentielDePolynesie::BaserowAPI.baserow_type_to_mapping_type(meta),
        'libelle' => name,
        'example_value' => sample_row&.dig(name)&.to_s,
        'prefill' => '0',
        'display_usager' => usager_names.include?(name) ? '1' : '0',
        'display_instructeur' => instructeur_names.include?(name) ? '1' : '0'
      }
    end

    # pf: préserver les prefill existants du mapping actuel
    existing_mapping = tdc.options&.dig('referentiel_mapping') || {}
    existing_mapping.each do |old_jsonpath, old_opts|
      # pf: ancien format $.row.Field → nouveau format $.Field
      new_jsonpath = old_jsonpath.sub(/^\$\.row\./, '$.')
      if mapping.key?(new_jsonpath) && old_opts['prefill'] == '1'
        mapping[new_jsonpath]['prefill'] = '1'
        mapping[new_jsonpath]['prefill_stable_id'] = old_opts['prefill_stable_id'] if old_opts['prefill_stable_id'].present?
      end
    end

    tdc.update!(referentiel_mapping: mapping)
  end
end
