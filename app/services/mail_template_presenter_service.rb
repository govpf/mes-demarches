# frozen_string_literal: true

class MailTemplatePresenterService
  include ActionView::Helpers::SanitizeHelper
  include ActionView::Helpers::TextHelper
  include ChampHelper

  def self.create_commentaire_for_state(dossier, state)
    if dossier.procedure.accuse_lecture? && Dossier::TERMINE.include?(state)
      CommentaireService.create!(CONTACT_EMAIL, dossier, body: I18n.t('layouts.mailers.accuse_lecture.commentaire_html', service: dossier.procedure.service&.nom))
    else
      service = new(dossier, state)
      body = ["<p>[#{service.safe_subject}]</p>", service.safe_body].join('')
      CommentaireService.create!(CONTACT_EMAIL, dossier, body: body)
    end
  end

  def safe_body
    # pf: préserve les liens HTML existants (téléchargements dans motivations) + auto-link URLs brutes
    body_text = @email_template.body_for_dossier(@dossier)

    # Étape 1 : Sanitize en préservant les <a> et <img> (MailScrubber)
    sanitized_text = sanitize(body_text, scrubber: Sanitizers::MailScrubber.new)

    # Étape 2 : Auto-link les URLs brutes (pas encore en <a>)
    auto_linked_text = Anchored::Linker.auto_link(sanitized_text, target: '_blank', rel: 'noopener') do |link_href|
      truncate(link_href, length: 60)
    end

    # Étape 3 : Gestion des espaces insécables pour éviter de casser le layout
    auto_linked_text.gsub!(/ (\S{15})/, ' \1') if auto_linked_text.present?

    # Étape 4 : Formatage final avec <p>
    simple_format(auto_linked_text, {}, sanitize: false)
  end

  def safe_subject
    Nokogiri::HTML.parse(truncate(@email_template.subject_for_dossier(@dossier), length: 100)).text
  end

  def initialize(dossier, state)
    @dossier = dossier
    @email_template = dossier.email_template_for(state)
  end
end
