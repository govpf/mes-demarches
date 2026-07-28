# frozen_string_literal: true

class Procedure::EstimatedDelayComponent < ApplicationComponent
  delegate :distance_of_time_in_words, to: :helpers

  def initialize(procedure:)
    @procedure = procedure
    @fastest, @mean, @slow = @procedure.stats_usual_traitement_time
  end

  def estimation_present?
    @fastest && @mean && @slow
  end

  def render?
    return false if @procedure.declarative_accepte?

    estimation_present?
  end

  # pf: on ne déduplique pas les durées. Le zip sur le tableau dédupliqué décalait les
  # libellés : avec 1 mois / 1 mois / 2 mois, la durée du tiers le plus long était
  # présentée comme celle du tiers intermédiaire, sous-estimant le pire cas.
  # Les trois durées sont croissantes par construction (centiles de tiers consécutifs
  # d'un tableau trié), donc l'ordre rapides / intermédiaires / longs est toujours
  # exact. Seul le cas où les trois coïncident donne une ligne unique, sans
  # distinction de rapidité.
  def cleaned_nearby_estimation
    estimations = [@fastest, @mean, @slow].map { distance_of_time_in_words(_1) }

    if estimations.uniq.one?
      yield(estimations.first, 'single_html')
    else
      estimations.zip(['fast_html', 'mean_html', 'slow_html']).each do |estimation, i18n_key|
        yield(estimation, i18n_key)
      end
    end
  end
end
