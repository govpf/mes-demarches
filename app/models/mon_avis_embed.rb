# frozen_string_literal: true

# Extrait le lien JDMA (« Je donne mon avis ») de confiance depuis le code
# `monavis_embed` collé par l'administrateur, afin de rendre notre propre
# bouton adaptatif au thème plutôt que l'unique image (claire OU sombre)
# choisie par l'admin. On ne garde QUE le lien ; l'image est fournie par l'app.
class MonAvisEmbed
  def initialize(embed)
    @embed = embed
  end

  # Retourne l'URL d'avis avec la source de tracking réécrite, ou nil si le
  # code est vide / invalide / pointe vers une URL non fiable.
  def link_href(source)
    href = extracted_href
    return if href.blank?
    return unless trusted?(href)

    href.gsub('nd_source=button', "nd_source=#{source}")
  end

  private

  def extracted_href
    return if @embed.blank?

    Nokogiri::HTML::DocumentFragment.parse(@embed).at_css('a')&.attr('href')&.strip
  rescue StandardError
    nil
  end

  def trusted?(href)
    MonAvisEmbedValidator::ALLOWED_SCHEME.match?(href) &&
      MonAvisEmbedValidator::DOMAIN_CHECKER.match?(href)
  end
end
