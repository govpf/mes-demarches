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
      # Plusieurs PJ → liste
      {
        type: 'bulletList',
        content: @presentations.map do |presentation|
          {
            type: 'listItem',
            content: [
              {
                type: 'paragraph',
                            content: [presentation.to_tiptap_node]
              }
            ]
          }
        end
      }
    end
  end

  def block_level?
    @presentations.size > 1 # Liste = block, item unique = inline
  end
end
