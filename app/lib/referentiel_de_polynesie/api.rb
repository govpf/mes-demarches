# frozen_string_literal: true

class ReferentielDePolynesie::API
  class << self
    # pf: DLNUF — config « champ propriétaire » avec cache court. TTL 5 min : compromis entre
    # charge Baserow (1 appel config + 1 appel fields par table) et fenêtre de scope obsolète
    # après un changement de la colonne « Champ propriétaire » (toléré, cf. devis §7).
    DLNUF_CONFIG_TTL = 5.minutes

    def available_tables
      engine&.available_tables || []
    end

    def dlnuf_config(domain_id)
      return nil if domain_id.to_i <= 0 || engine.nil?

      cached = Rails.cache.fetch("referentiel_de_polynesie/dlnuf_config/#{domain_id}", expires_in: DLNUF_CONFIG_TTL) do
        engine.dlnuf_config(domain_id) || :none # pf: sentinel — Rails.cache ne mémorise pas nil
      end
      cached == :none ? nil : cached
    end

    def search(domain_id, term, drop_down_other: false)
      return [] if domain_id.to_i <= 0
      engine&.search(domain_id, term, drop_down_other: drop_down_other) || []
    end

    def search_with_data(domain_id, term, drop_down_other: false, scope: nil)
      return [] if domain_id.to_i <= 0
      engine&.search_with_data(domain_id, term, drop_down_other:, scope:) || []
    end

    def fetch_row(external_id)
      table, id = external_id.split(':')
      engine&.fetch_row(table, id) || {}
    end

    def find_by_exact_value(domain_id, term)
      return {} if domain_id.to_i <= 0
      engine&.find_by_exact_value(domain_id, term) || {}
    end

    def engine
      @engine ||= ENV['API_BASEROW_URL'].present? ? ReferentielDePolynesie::BaserowAPI : nil
    end
  end
end
