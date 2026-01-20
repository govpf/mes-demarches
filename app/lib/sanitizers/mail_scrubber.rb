# frozen_string_literal: true

module Sanitizers
  class MailScrubber < Rails::Html::PermitScrubber
    def initialize
      super
      # pf: préserve les liens et images dans les emails (notamment liens de téléchargement dans motivations)
      # Note: config/application.rb:52 retire globalement 'a' et 'img' des tags autorisés pour la sécurité
      # MailScrubber les ré-autorise uniquement pour les emails système (safe car générés par instructeurs)
      self.tags = Rails.application.config.action_view.sanitized_allowed_tags + ['a', 'img']
      self.attributes = Rails.application.config.action_view.sanitized_allowed_attributes + ['href', 'src', 'target', 'rel', 'alt']
    end

    def skip_node?(node)
      node.text?
    end
  end
end
