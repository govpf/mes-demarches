# frozen_string_literal: true

# pf: Présentation de plusieurs pièces jointes pour attestation v2
class ChampPresentations::MultiplePieceJustificativePresentation < ChampPresentations::BasePresentation
  def initialize(attachments, champ: nil)
    @attachments = attachments
    @champ = champ
    @presentations = attachments.map.with_index do |attachment, index|
      ChampPresentations::PieceJustificativePresentation.from_attachment(attachment, champ: champ, index: index)
    end
  end

  def to_s
    # pf: concatenation sécurisée - échappe automatiquement les strings non-safe
    fragments = @presentations.map(&:to_s)
    ActionController::Base.helpers.safe_join(fragments, ', ')
  end

  # pf: éviter l'échappement HTML dans TagsSubstitutionConcern
  def html_safe?
    true
  end

  def to_tiptap_node
    if @presentations.size == 1
      # Une seule PJ → structure simple
      @presentations.first.to_tiptap_node
    else
      # pf: Plusieurs PJ → afficher côte à côte dans un paragraphe (plus compact et esthétique)
      {
        type: 'paragraph',
        attrs: { textAlign: 'center' }, # pf: centrer les images
        content: @presentations.flat_map.with_index do |presentation, i|
          node = presentation.to_tiptap_node
          # pf: ajouter un espace entre les images (sauf après la dernière)
          if i < @presentations.size - 1
            [node, { type: 'text', text: ' ' }]
          else
            [node]
          end
        end
      }
    end
  end

  def block_level?
    @presentations.size > 1 # Liste = block, item unique = inline
  end
end
