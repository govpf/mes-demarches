module DossierHelper
  include EtablissementHelper

  def button_or_label_class(dossier)
    if dossier.accepte?
      'accepted'
    elsif dossier.sans_suite?
      'without-continuation'
    elsif dossier.refuse?
      'refused'
    end
  end

  def highlight_if_unseen_class(seen_at, updated_at)
    if updated_at.present? && seen_at&.<(updated_at)
      "highlighted"
    end
  end

  def url_for_dossier(dossier)
    if dossier.brouillon?
      brouillon_dossier_path(dossier)
    else
      dossier_path(dossier)
    end
  end

  def url_for_new_dossier(revision)
    new_dossier_url(procedure_id: revision.procedure.id, brouillon: revision.draft? ? true : nil)
  end

  def dossier_form_class(dossier)
    classes = ['form']
    if autosave_available?(dossier)
      classes << 'autosave-enabled'
    end
    classes.join(' ')
  end

  def autosave_available?(dossier)
    dossier.brouillon?
  end

  def dossier_submission_is_closed?(dossier)
    dossier.brouillon? && dossier.procedure.close?
  end

  def dossier_display_state(dossier_or_state, lower: false)
    state = dossier_or_state.is_a?(Dossier) ? dossier_or_state.state : dossier_or_state
    display_state = Dossier.human_attribute_name("state.#{state}")
    lower ? display_state.downcase : display_state
  end

  def dossier_legacy_state(dossier)
    case dossier.state
    when Dossier.states.fetch(:en_construction)
      'initiated'
    when Dossier.states.fetch(:en_instruction)
      'received'
    when Dossier.states.fetch(:accepte)
      'closed'
    when Dossier.states.fetch(:refuse)
      'refused'
    when Dossier.states.fetch(:sans_suite)
      'without_continuation'
    else
      dossier.state
    end
  end

  def status_badge(state)
    status_text = dossier_display_state(state, lower: true)
    status_class = state.tr('_', '-')
    tag.span(status_text, class: "label #{status_class} ")
  end

  def deletion_reason_badge(reason)
    if reason.present?
      status_text = I18n.t(reason, scope: [:activerecord, :attributes, :deleted_dossier, :reason])
      status_class = reason.tr('_', '-')
    else
      status_text = I18n.t(:unknown, scope: [:activerecord, :attributes, :deleted_dossier, :reason])
      status_class = 'unknown'
    end

    tag.span(status_text, class: "label #{status_class} ")
  end

  def demandeur_dossier(dossier)
    if dossier.procedure.for_individual?
      "#{dossier&.individual&.nom} #{dossier&.individual&.prenom}"
    else
      if dossier.etablissement.present?
        raison_sociale_or_name(dossier.etablissement)
      else
        ""
      end
    end
  end

  def safe_expiration_date(dossier)
    l(dossier.expiration_date, format: '%d/%m/%Y')
  end

  def annuaire_link(siren)
    return 'https://www.ispf.pf/bases/Repertoires/Entreprises/Recherche.aspx' if siren.blank?

    "https://www.ispf.pf/bases/Repertoires/Entreprises/Detail.aspx?numtah=#{siren}"
  end

  def exports_list(exports, statut = nil)
    if statut
      Export::FORMATS.map do |item|
        export = exports
          .fetch(item.fetch(:format))
          .fetch(:statut)
          .fetch(statut, nil)
        item.merge(export: export)
      end
    else
      Export::FORMATS_WITH_TIME_SPAN.map do |item|
        export = exports
          .fetch(item.fetch(:format))
          .fetch(:time_span_type)
          .fetch(item.fetch(:time_span_type), nil)
        item.merge(export: export)
      end
    end
  end
end
