# frozen_string_literal: true

class Referentiels::ReferentielDisplayComponent < Referentiels::MappingFormBase
  def display_mapping
    # pf: lot C DLNUF — une référence de pièce justificative n'est jamais affichée
    (type_de_champ.referentiel_mapping_displayable || {}).reject { |_jsonpath, opts| opts[:type].to_s == 'piece_justificative' }
  end

  def display_tag_for(jsonpath, attribute_name)
    id = "#{jsonpath.parameterize}-#{attribute_name.parameterize}"
    tag.div(class: "fr-checkbox-group") do
      safe_join([
        hidden_field_tag(attribute_name(jsonpath, attribute_name), "0"),
        check_box_tag(attribute_name(jsonpath, attribute_name), "1", lookup_existing_value(jsonpath, attribute_name) == "1", class: "fr-checkbox", id:),
        tag.label(for: id, class: "fr-label", aria: { hidden: true }) { sanitize("&nbsp;") },
      ])
    end
  end

  def render?
    display_mapping.any?
  end
end
