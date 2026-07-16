# frozen_string_literal: true

class Dossiers::JdmaButtonComponent < ApplicationComponent
  def initialize(procedure:)
    @procedure = procedure
  end

  def render?
    href.present?
  end

  def href
    @href ||= MonAvisEmbed.new(@procedure.monavis_embed).link_href("site")
  end
end
