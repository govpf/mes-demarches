# frozen_string_literal: true

module Maintenance
  class T20261106reinitialiserMemorisationDlnufTask < MaintenanceTasks::Task
    # Documentation: pf: DLNUF — remet à zéro la mémorisation du mode DLNUF d'une table Baserow
    # (contrat docs/superpowers/specs/2026-11-06-contrat-referentiel-dlnuf.md §3.4). À lancer à
    # la main, après vérification, quand une table a été passée en DLNUF par erreur sur une
    # démarche publiée et ramenée en archive. Volontairement hors de Baserow : la mémorisation
    # protège contre une modification de la table, elle ne peut donc pas être levée depuis la table.
    attribute :table_id, :integer
    validates :table_id, presence: true, numericality: { greater_than: 0 }

    def collection
      Referentiels::BaserowReferentiel.pour_table(table_id)
    end

    def process(referentiel)
      ancienne = referentiel.dlnuf_vu_le
      return if ancienne.blank?

      referentiel.update_column(:autocomplete_configuration, referentiel.autocomplete_configuration.except('dlnuf_vu_le'))
      Rails.logger.warn("ReferentielDePolynesie: mémorisation DLNUF retirée (référentiel #{referentiel.id}, table #{table_id}, mémorisée le #{ancienne})")
    end
  end
end
