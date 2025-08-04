# frozen_string_literal: true

# pf: navigation contextuelle entre personas pour améliorer l'UX des créateurs de formulaires
module ContextualNavigationConcern
  extend ActiveSupport::Concern

  included do
    helper_method :contextual_persona_enabled?
    helper_method :contextual_redirect_path_for_profile
  end

  private

  def contextual_persona_enabled?
    return false unless current_user
    Flipper.enabled?(:contextual_persona_navigation, current_user)
  end

  def contextual_redirect_path_for_profile(target_profile)
    return nil unless contextual_persona_enabled?

    context = current_context_info
    return nil if context.empty?

    case target_profile
    when :instructeur
      build_instructeur_contextual_path(context)
    when :user
      build_user_contextual_path(context)
    when :administrateur
      build_administrateur_contextual_path(context)
    else
      nil
    end
  rescue StandardError
    nil
  end

  def current_context_info
    @current_context_info ||= begin
      case controller_path
      when /^users\/dossiers/
        { type: :dossier, id: params[:id] }
      when /^instructeurs\/dossiers/
        { type: :dossier, id: params[:dossier_id] }
      when /^instructeurs\/procedures/
        if params[:dossier_id].present?
          { type: :dossier, id: params[:dossier_id] }
        else
          { type: :procedure, id: params[:procedure_id] }
        end
      when /^administrateurs\/procedures/
        { type: :procedure, id: params[:id] || params[:procedure_id] }
      else
        {}
      end
    end
  end

  def build_instructeur_contextual_path(context)
    case context[:type]
    when :dossier
      if can_access_dossier_as_instructeur?(context[:id])
        dossier = Dossier.find(context[:id])
        instructeur_dossier_path(procedure_id: dossier.procedure.id, dossier_id: context[:id])
      end
    when :procedure
      if can_access_procedure_as_instructeur?(context[:id])
        instructeur_procedure_path(procedure_id: context[:id])
      end
    end
  end

  def build_user_contextual_path(context)
    if context[:type] == :dossier && can_access_dossier_as_user?(context[:id])
      dossier_path(context[:id])
    end
  end

  def build_administrateur_contextual_path(context)
    procedure_id = case context[:type]
    when :procedure
      context[:id]
    when :dossier
      Dossier.find_by(id: context[:id])&.procedure&.id
    end

    if procedure_id && can_access_procedure_as_administrateur?(procedure_id)
      admin_procedure_path(procedure_id)
    end
  end

  def can_access_dossier_as_instructeur?(dossier_id)
    return false unless instructeur_signed_in?

    dossier = Dossier.find_by(id: dossier_id)
    return false unless dossier

    current_instructeur.procedures.exists?(id: dossier.procedure.id)
  end

  def can_access_dossier_as_user?(dossier_id)
    return false unless user_signed_in?
    current_user.dossiers.exists?(id: dossier_id)
  end

  def can_access_procedure_as_administrateur?(procedure_id)
    return false unless administrateur_signed_in?
    current_administrateur.procedures.exists?(id: procedure_id)
  end

  def can_access_procedure_as_instructeur?(procedure_id)
    return false unless instructeur_signed_in?
    current_instructeur.procedures.exists?(id: procedure_id)
  end
end
