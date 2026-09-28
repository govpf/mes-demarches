# frozen_string_literal: true

# pf: source de vérité unique des colonnes système référençables dans une
# formule : identifiant stocké dans formule_expression ↔ Column ↔ déclencheur
# de recalcul. Partagée par l'éditeur (autocomplete), FormulaColumnResolver
# (validation + calcul), FormulaExpressionService (réaffichage en libellés) et
# FormuleTypeDeChamp (formule_deps has_state / has_identite). Avant, chacun
# avait sa propre liste : l'éditeur proposait {self_created_at} que le resolver
# ne connaissait pas (« Colonne inconnue ») et que l'affichage ne retraduisait pas.
#
# Liste blanche : une colonne n'y entre que si la formule reste à jour, c'est-à-
# dire si sa valeur est figée ou si un déclencheur de recalcul existe :
#   :frozen   — ne change plus une fois la formule calculée ;
#   :state    — formule_deps['has_state'] : recalcul après transition d'état
#               (DossierFormulaRefreshConcern, filtré sur STATE_TIMESTAMP_COLUMNS) ;
#   :identite — formule_deps['has_identite'] : recalcul après update_identite /
#               update_siret (refresh_formulas_with_identite_dependents).
# Exclues faute de déclencheur : colonnes d'instruction (suiveurs, labels,
# groupe instructeur) et dates mouvantes (updated_at, last_champ_updated_at,
# expired_at…), archived, motivation.
class FormulaSystemColumns
  # [table, colonne] => [identifiant, déclencheur]. Les identifiants
  # dossier_* / individual_* / entreprise_* sont historiques (formules déjà
  # enregistrées) ; les autres suivent l'encodage générique "<table>_<colonne>".
  COLUMNS = {
    ['self', 'id'] => ['dossier_number', :frozen],
    ['self', 'created_at'] => ['self_created_at', :frozen],
    ['self', 'state'] => ['dossier_state', :state],
    ['self', 'depose_at'] => ['dossier_depose_at', :state],
    ['self', 'en_construction_at'] => ['dossier_en_construction_at', :state],
    ['self', 'en_instruction_at'] => ['dossier_en_instruction_at', :state],
    ['self', 'processed_at'] => ['dossier_processed_at', :state],
    ['individual', 'gender'] => ['individual_gender', :identite],
    ['individual', 'prenom'] => ['individual_first_name', :identite],
    ['individual', 'nom'] => ['individual_last_name', :identite],
    ['self', 'mandataire_first_name'] => ['self_mandataire_first_name', :identite],
    ['self', 'mandataire_last_name'] => ['self_mandataire_last_name', :identite],
    ['self', 'for_tiers'] => ['self_for_tiers', :identite],
    ['etablissement', 'entreprise_siren'] => ['entreprise_siren', :identite],
    ['etablissement', 'siret'] => ['entreprise_siret', :identite],
    ['etablissement', 'entreprise_raison_sociale'] => ['entreprise_raison_sociale', :identite],
  }.freeze

  # Les autres colonnes etablissement, encodées "etablissement_<colonne>" :
  # update_siret les recalcule (has_identite), et
  # Etablissement#update_champ_value_json! relance toutes les formules.
  ETABLISSEMENT_PREFIX = 'etablissement_'

  TRIGGER_BY_ID = COLUMNS.values.to_h.freeze

  # Préfixes des identifiants ci-dessus : distinguent une expression déjà
  # encodée d'une expression en libellés (FormulaValidator, et en miroir
  # formula_editor_controller.ts#convertToColumnIds).
  ID_PREFIXES = ['dossier_', 'individual_', 'entreprise_', 'self_', ETABLISSEMENT_PREFIX].freeze

  class << self
    # Identifiant de formule d'une colonne système, nil si hors liste blanche.
    def formula_id(column)
      return "#{ETABLISSEMENT_PREFIX}#{column.column}" if column.table == 'etablissement' && !COLUMNS.key?(key(column))

      COLUMNS[key(column)]&.first
    end

    # Déclencheur de recalcul d'un identifiant de formule (nil si inconnu).
    def trigger(id)
      TRIGGER_BY_ID[id] || (:identite if id.start_with?(ETABLISSEMENT_PREFIX))
    end

    # L'expression référence-t-elle une colonne système de ce déclencheur ?
    def references_trigger?(expression, trigger)
      expression.to_s.scan(/\{([^}]+)\}/).any? { |(ref)| trigger(ref.strip) == trigger }
    end

    # { identifiant de formule => Column } pour les colonnes de la procédure.
    def index(procedure)
      procedure.columns
        .filter { _1.is_a?(Columns::DossierColumn) }
        .each_with_object({}) do |column, index|
          id = formula_id(column)
          index[id] ||= column if id
        end
    end

    private

    def key(column) = [column.table, column.column.to_s]
  end
end
