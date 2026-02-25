# frozen_string_literal: true

module ApplicationHelper
  APP_HOST = ENV['APP_HOST']
  APP_HOST_LEGACY = ENV['APP_HOST_LEGACY']
  REGEXP_REPLACE_TRAILING_EXTENSION = /(\.\w+)+$/.freeze
  REGEXP_REPLACE_WORD_SEPARATOR = /[\s_-]+/.freeze

  def app_host_legacy?(request)
    return false if APP_HOST_LEGACY.blank?

    Regexp.new(APP_HOST_LEGACY).match?(request.base_url)
  end

  def auto_switch_domain?(request, user_signed_in)
    switch_domain_enabled?(request) && !user_signed_in && app_host_legacy?(request)
  end

  def switch_domain_enabled?(request)
    request.params.key?(:switch_domain) || Flipper.enabled?(:switch_domain, Current.user)
  end

  def html_lang
    I18n.locale.to_s
  end

  def active_locale_link(locale)
    link_to save_locale_path(locale:), {
      method: :post,
      class: "fr-translate__language fr-nav__link",
      hreflang: locale,
      lang: locale,
      "aria-current": I18n.locale == locale ? "true" : nil
    }.compact do
      yield
    end
  end

  def flash_class(level, sticky: false, fixed: false)
    class_names = []

    case level
    when 'notice'
      class_names << 'alert-success fr-icon-success-line fr-icon--sm fr-text--sm fr-mb-0'
    when 'alert', 'error'
      class_names << 'alert-danger fr-icon-error-line fr-icon--sm fr-text--sm fr-mb-0'
    end
    if sticky
      class_names << 'sticky'
    end
    if fixed
      class_names << 'alert-fixed'
    end
    class_names.join(' ')
  end

  def flash_role(level)
    return "status" if level == "notice"

    'alert'
  end

  def current_email
    current_user&.email ||
      current_instructeur&.email ||
      current_administrateur&.email ||
      current_gestionnaire&.email
  end

  def staging?
    Rails.application.config.ds_env == 'staging'
  end

  def contact_link(title, options = {})
    tags, type, dossier_id = options.values_at(:tags, :type, :dossier_id)
    options.except!(:tags, :type, :dossier_id)

    params = { tags: Array.wrap(tags), type: type, dossier_id: dossier_id }.compact
    link_to title, contact_url(params), options
  end

  def root_path_for_profile(nav_bar_profile)
    case nav_bar_profile
    when :instructeur
      instructeur_procedures_path
    when :user
      dossiers_path
    else
      root_path
    end
  end

  def root_path_info_for_profile(nav_bar_profile)
    case nav_bar_profile
    when :administrateur
      [admin_procedures_path, t("admin", scope: "layouts.root_path_link_title")]
    when :gestionnaire
      [gestionnaire_groupe_gestionnaires_path, t("gestionnaire", scope: "layouts.root_path_link_title")]
    when :instructeur
      [instructeur_procedures_path, t("instructeur", scope: "layouts.root_path_link_title")]
    when :user
      [dossiers_path, t("user", scope: "layouts.root_path_link_title")]
    else
      [root_path, t("default", scope: "layouts.root_path_link_title")]
    end
  end

  def try_format_date(date)
    date.present? ? I18n.l(date, format: :long) : ''
  end

  def try_format_datetime(datetime, format: nil)
    datetime.present? ? I18n.l(datetime, format:) : ''
  end

  def try_parse_format_date(date)
    date.then { Date.parse(_1) rescue nil }&.then { I18n.l(_1) }
  end

  def try_format_mois_effectif(etablissement)
    if etablissement.entreprise_effectif_mois.present? && etablissement.entreprise_effectif_annee.present?
      [etablissement.entreprise_effectif_mois, etablissement.entreprise_effectif_annee].join('/')
    else
      ''
    end
  end

  def human_date(date)
    today = Date.current

    case date
    when today
      I18n.t('dates.today')
    when today - 1
      I18n.t('dates.yesterday')
    when (today - 6)..(today - 2)
      I18n.t('dates.days_ago', count: (today - date).to_i)
    else
      I18n.l(date, format: :long)
    end
  end

  def show_outdated_browser_banner?
    !BrowserSupport.supported?(browser)
  end

  def external_link_attributes
    { target: "_blank", rel: "noopener noreferrer" }
  end

  def new_tab_suffix(title)
    [title, I18n.t('utils.new_tab')].compact.join(' — ')
  end

  def download_details(attachment)
    "#{attachment.filename.extension.upcase} – #{number_to_human_size(attachment.byte_size)}"
  end

  def dsfr_icon(classes, *options)
    sm = options.include?(:sm)
    mr = options.include?(:mr)

    tag.span(class: class_names(classes, 'fr-icon--sm': sm, 'fr-mr-1v': mr),
             "aria-hidden" => true)
  end

  def acronymize(str)
    str.gsub(REGEXP_REPLACE_TRAILING_EXTENSION, '')
      .split(REGEXP_REPLACE_WORD_SEPARATOR)
      .map { |word| word[0].upcase }
      .join
  end

  def asterisk = render(EditableChamp::AsteriskMandatoryComponent.new)

  def add_pdf_draft_warning(pdf, dossier)
    return unless dossier.revision.draft?

    pdf.pad_top(20) do
      pdf.fill_color "AA3300"
      pdf.font 'marianne', style: :bold, size: 12 do
        pdf.text "DÉMARCHE EN TEST"
      end

      pdf.font 'marianne', size: 10 do
        pdf.text "Ce dossier est déposé sur une démarche en test par l’administration."
        pdf.text "Il peut être supprimé à tout moment et sans préavis, même après avoir été accepté."
      end
      pdf.fill_color "000000"
    end
  end

  # pf: helpers pour les titres d'onglet navigateur compacts
  # Format cible : "Page · 123(I) · mes-Démarches"

  # Abréviation du rôle utilisateur pour les titres d'onglet
  def title_role_abbreviation
    profile = controller.try(:nav_bar_profile) || controller.try(:fallback_nav_bar_profile)
    case profile
    when :administrateur then 'A'
    when :instructeur then 'I'
    when :expert then 'E'
    when :gestionnaire then 'G'
    when :user then 'U'
    when :superadmin then 'S'
    else nil # profil non authentifié (guest)
    end
  end

  # Titre d'onglet pour les pages liées à une procédure
  # Ex: procedure_tab_title(@procedure, "Champs") → "Champs · 123(A)"
  # Ex: procedure_tab_title(@procedure) → "123(I)"
  def procedure_tab_title(procedure, page_name = nil)
    role = title_role_abbreviation
    label = role ? "#{procedure.id}(#{role})" : procedure.id.to_s
    page_name ? "#{page_name} · #{label}" : label
  end

  # Titre d'onglet pour les pages liées à un dossier
  # RGPD : affiche le prénom seul (pas le nom complet) pour éviter la fuite dans les analytics
  # Ex: dossier_tab_title(@dossier, "Demande") → "Demande · 605256 (Pierre)"
  # Ex: dossier sans identité → "Demande · 605256"
  def dossier_tab_title(dossier, page_name)
    owner = dossier.owner_first_name
    label = owner.present? ? "#{dossier.id} (#{owner})" : dossier.id.to_s
    "#{page_name} · #{label}"
  end

  # pf: sanitization HTML spécifique pour attestation v2
  def attestation_v2_sanitize(html)
    config = Rails.application.config.attestation_v2
    ActionController::Base.helpers.sanitize(
      html,
      tags: config[:allowed_tags],
      attributes: config[:allowed_attributes]
    )
  end
end
