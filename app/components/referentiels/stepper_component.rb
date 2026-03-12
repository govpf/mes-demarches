# frozen_string_literal: true

class Referentiels::StepperComponent < ViewComponent::Base
  attr_reader :referentiel, :type_de_champ, :procedure, :step_component

  def initialize(referentiel:, type_de_champ:, procedure:, step_component:)
    @referentiel = referentiel
    @type_de_champ = type_de_champ
    @procedure = procedure
    @step_component = step_component
  end

  def step_state
    "Étape #{current_step} sur #{step_count}"
  end

  def step_title
    if step_component == Referentiels::NewFormComponent || (step_component == Referentiels::ConfigurationErrorComponent && referentiel.exact_match?)
      "Requête"
    elsif step_component == Referentiels::MappingFormComponent
      "Réponse et mapping"
    elsif step_component == Referentiels::PrefillAndDisplayComponent
      "Pré remplissage des champs et/ou affichage des données récupérées"
    elsif step_component == Referentiels::AutocompleteConfigurationComponent || (step_component == Referentiels::ConfigurationErrorComponent && referentiel.autocomplete?)
      "Configuration de l'autocomplétion"
    end
  end

  def next_step_title
    if step_component == Referentiels::NewFormComponent && referentiel.needs_autocomplete_configuration?
      "Configuration de l'autocomplétion"
    elsif step_component == Referentiels::NewFormComponent || step_component == Referentiels::AutocompleteConfigurationComponent
      "Réponse et mapping"
    elsif step_component == Referentiels::MappingFormComponent
      "Pré remplissage des champs et/ou affichage des données récupérées"
    end
  end

  def current_step
    return 1 if step_component.in?([Referentiels::NewFormComponent, Referentiels::ConfigurationErrorComponent])

    if referentiel.needs_autocomplete_configuration?
      case step_component
      when Referentiels::AutocompleteConfigurationComponent then 2
      when Referentiels::MappingFormComponent then 3
      when Referentiels::PrefillAndDisplayComponent then 4
      end
    else
      case step_component
      when Referentiels::MappingFormComponent then 2
      when Referentiels::PrefillAndDisplayComponent then 3
      end
    end
  end

  def step_count
    referentiel.needs_autocomplete_configuration? ? 4 : 3
  end
end
