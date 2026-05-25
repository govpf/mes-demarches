# frozen_string_literal: true

class BackfillFormuleDeps < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # pf: Backfill formule_deps Hash sur les TDC formule existants. La logique
  # de calcul est dupliquée en inline (pas d'appel au model) pour rester
  # indépendante du code applicatif au moment du run.
  #
  # Note: has_clock est calculé ici par regex et NON via l'AST Dentaku (la
  # version "vraie" via AST est dans FormuleTypeDeChamp#validate_expression).
  # Conséquence: une formule contenant une fonction clock dans un littéral
  # string (ex: CONCATENER("L'AGE(x)", {Nom})) sera marquée has_clock=true
  # à tort jusqu'à sa prochaine sauvegarde, qui recalculera proprement via
  # l'AST et corrigera le flag. Acceptable vu le volume et la rareté du cas.

  CLOCK_PATTERN    = /\b(AUJOURDHUI|MAINTENANT|AGE|EST_PASSEE|EST_FUTURE)\s*\(/
  TDC_PATTERN      = /\{tdc(\d+)(?:\/[^}]+)?\}/
  STATE_PATTERN    = /\{dossier_(?:depose|en_construction|en_instruction|processed)_at\}/
  IDENTITE_PATTERN = /\{(?:individual_|entreprise_)/

  def up
    TypeDeChamp.where(type_champ: 'formule').find_each do |tdc|
      opts = tdc.options || {}
      expr = opts['formule_expression'].to_s

      deps = { 'champs' => expr.scan(TDC_PATTERN).flatten.map(&:to_i).uniq.sort }
      deps['has_clock']    = true if expr.match?(CLOCK_PATTERN)
      deps['has_state']    = true if expr.match?(STATE_PATTERN)
      deps['has_identite'] = true if expr.match?(IDENTITE_PATTERN)

      new_opts = opts.merge('formule_deps' => deps)

      # pf: update_column saute les callbacks — pas de cascade de recalcul ni
      # de re-validation. On veut écrire la donnée brute sans déclencher
      # validate_expression (qui pourrait planter sur des formules cassées en
      # base et bloquer toute la migration).
      tdc.update_column(:options, new_opts)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
