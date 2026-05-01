# frozen_string_literal: true

# pf: Configuration de sanitization HTML pour attestation v2
# Permet les nouveaux éléments HTML pour les pièces jointes et tableaux

Rails.application.configure do
  config.attestation_v2 = {
    allowed_tags: %w[
      p div span strong em u s mark br
      ul ol li
      h1 h2 h3 h4 h5 h6
      header footer
      img a table tr td th thead tbody
      figure figcaption
    ],
    allowed_attributes: %w[
      class style
      src alt width height
      href target rel
      colspan rowspan
    ],
  }
end
