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

    # pf: ligne de configuration de la table (table méta Baserow) avec le même cache court :
    # l’éditeur de champs la lit pour chaque carte référentiel (BaserowReferentiel#ready?), ce qui
    # coûtait un appel HTTP par carte à chaque affichage.
    def config(domain_id)
      return nil if domain_id.to_i <= 0 || engine.nil?

      cached = Rails.cache.fetch("referentiel_de_polynesie/config/#{domain_id}", expires_in: DLNUF_CONFIG_TTL) do
        engine.config(domain_id) || :none
      end
      cached == :none ? nil : cached
    end

    def dlnuf_config(domain_id)
      return nil if domain_id.to_i <= 0 || engine.nil?

      cached = Rails.cache.fetch("referentiel_de_polynesie/dlnuf_config/#{domain_id}", expires_in: DLNUF_CONFIG_TTL) do
        engine.dlnuf_config(domain_id) || :none # pf: sentinel — Rails.cache ne mémorise pas nil
      end
      appliquer_memorisation_dlnuf(domain_id, cached == :none ? nil : cached)
    end

    def search(domain_id, term, drop_down_other: false)
      return [] if domain_id.to_i <= 0
      engine&.search(domain_id, term, drop_down_other: drop_down_other) || []
    end

    def search_with_data(domain_id, term, drop_down_other: false, scopes: [])
      return [] if domain_id.to_i <= 0
      engine&.search_with_data(domain_id, term, drop_down_other:, scopes:) || []
    end

    # pf: cascade — colonnes de la table (nom, type, options de sélection) avec le même cache
    # court que dlnuf_config : sert à l'éditeur admin, au endpoint #search et au composant.
    def table_fields(domain_id)
      return nil if domain_id.to_i <= 0 || engine.nil?

      cached = Rails.cache.fetch("referentiel_de_polynesie/table_fields/#{domain_id}", expires_in: DLNUF_CONFIG_TTL) do
        engine.table_fields(domain_id) || :none
      end
      cached == :none ? nil : cached
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

    private

    # pf: DLNUF — mémorisation anti-bascule (contrat 2026-11-06-contrat-referentiel-dlnuf.md §3.4),
    # appliquée APRÈS le cache : une table vue en DLNUF sur une démarche publiée qui ne l'est plus
    # (marqueur retiré, Baserow muet) est refusée au lieu d'être servie en catalogue.
    def appliquer_memorisation_dlnuf(domain_id, resultat)
      case resultat
      when Hash
        Referentiels::BaserowReferentiel.memoriser_dlnuf!(domain_id)
        resultat
      when nil
        return nil unless Referentiels::BaserowReferentiel.dlnuf_vu?(domain_id)

        Sentry.capture_message('ReferentielDePolynesie: bascule de mode DLNUF', extra: { domain_id: })
        :invalid
      else
        resultat
      end
    end
  end
end
