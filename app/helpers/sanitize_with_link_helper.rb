# frozen_string_literal: true

module SanitizeWithLinkHelper
  # pf: harmonisation avec France Connect pour maintenir la cohérence UX
  def sanitize_with_link(value)
    # pf: keep 'img' tag in addition to upstream 'a' tag
    tags = Rails.configuration.action_view.sanitized_allowed_tags + ['a', 'img']

    allowed_attributes = Rails.configuration.action_view.sanitized_allowed_attributes || Set.new
    attributes = allowed_attributes + [
      'aria-controls', 'data-fr-opened', 'data-fr-js-modal-button', 'href', 'class'
    ]

    sanitize(value, tags:, attributes:)
  end
end
