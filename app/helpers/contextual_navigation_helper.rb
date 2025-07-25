# frozen_string_literal: true

# pf: helper pour la navigation contextuelle entre personas
module ContextualNavigationHelper
  def contextual_or_default_path_for_profile(target_profile)
    if contextual_persona_enabled?
      contextual_path = contextual_redirect_path_for_profile(target_profile)
      return contextual_path if contextual_path
    end

    # Fallback vers le comportement existant
    default_path_for_profile(target_profile)
  end

  private

  def default_path_for_profile(target_profile)
    case target_profile
    when :user
      dossiers_path
    when :instructeur
      instructeur_procedures_path
    when :administrateur
      admin_procedures_path
    else
      root_path
    end
  end
end
