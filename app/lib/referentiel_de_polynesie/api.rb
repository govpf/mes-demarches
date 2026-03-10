# frozen_string_literal: true

class ReferentielDePolynesie::API
  class << self
    def available_tables
      engine&.available_tables || []
    end

    def search(domain_id, term, drop_down_other: false)
      return [] if domain_id.to_i <= 0
      engine&.search(domain_id, term, drop_down_other: drop_down_other) || []
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
