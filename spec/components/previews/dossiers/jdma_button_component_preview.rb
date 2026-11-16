# frozen_string_literal: true

class Dossiers::JdmaButtonComponentPreview < ViewComponent::Preview
  def default
    procedure = Procedure.new(monavis_embed: '<a href="https://jedonnemonavis.numerique.gouv.fr/Demarches/123?nd_source=button&key=abc"><img src="https://jedonnemonavis.numerique.gouv.fr/static/bouton-bleu-clair.svg" alt="Je donne mon avis" /></a>')
    render(Dossiers::JdmaButtonComponent.new(procedure:))
  end
end
