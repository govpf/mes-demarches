# frozen_string_literal: true

# pf: unique analyse des références {…} d'une expression de formule.
# Formes reconnues : {tdcN}, {tdcN/chemin}, {tdcN/sub_M} et {colonne_systeme}.
# Le format hérité {123} n'est pas une référence de champ (stable_id nil).
module FormulaReferences
  PATTERN = /\{([^}]+)\}/
  CHAMP_PATTERN = %r{\Atdc(\d+)(?:/(.*))?\z}m
  SUB_PATTERN = /\Asub_(\d+)\z/

  Ref = Data.define(:raw, :stable_id, :sub_stable_id, :path) do
    def champ? = !stable_id.nil?

    def sub_champ? = !sub_stable_id.nil?
  end

  class << self
    def scan(expression)
      expression.to_s.scan(PATTERN).map { |(raw)| parse(raw.strip) }
    end

    def stable_ids(expression)
      scan(expression).filter_map(&:stable_id).uniq.sort
    end

    # Remplace chaque référence par le résultat du bloc, appelé avec (ref, match).
    def gsub(expression)
      expression.gsub(PATTERN) do |match|
        yield parse(Regexp.last_match(1).strip), match
      end
    end

    private

    def parse(raw)
      champ = CHAMP_PATTERN.match(raw)
      return Ref.new(raw:, stable_id: nil, sub_stable_id: nil, path: nil) if champ.nil?

      suffix = champ[2]
      sub = suffix && SUB_PATTERN.match(suffix)
      Ref.new(
        raw:,
        stable_id: champ[1].to_i,
        sub_stable_id: sub ? sub[1].to_i : nil,
        path: sub ? nil : suffix
      )
    end
  end
end
