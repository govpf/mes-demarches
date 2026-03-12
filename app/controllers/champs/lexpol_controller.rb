# frozen_string_literal: true

module Champs
  class LexpolController < Champs::ChampController
    skip_before_action :set_champ, only: [:preview_variables]

    def upsert
      use_service_account = should_use_service_account?
      apilexpol = APILexpol.new(current_user.email, service_siret, use_service_account)
      service = LexpolService.new(champ: @champ, dossier: @champ.dossier, apilexpol: apilexpol, user: current_user)

      force_create = params[:force_create].present?
      service.upsert_dossier(force_create: force_create)

      # pf: Message adapté selon le mode utilisé
      if use_service_account
        flash[:notice] = "Dossier Lexpol #{@champ.value.blank? ? 'créé' : 'mis à jour'} avec succès (compte de service)"
      else
        flash[:notice] = "Dossier Lexpol #{@champ.value.blank? ? 'créé' : 'mis à jour'} avec succès"
      end

    rescue JSON::ParserError => e
      Sentry.capture_message("Invalid Json received from Lexpol : #{e.message}")
      flash[:alert] = "Erreur de communication avec Lexpol"

    rescue APILexpol::LexpolAccessDenied => e
      # pf: Tentative de fallback si l'utilisateur n'a pas accès mais qu'on est super-admin
      if !use_service_account && super_admin_signed_in?
        Rails.logger.warn("Lexpol: fallback to service account for super-admin #{current_user.email}")

        begin
          apilexpol_fallback = APILexpol.new(current_user.email, service_siret, true)
          service_fallback = LexpolService.new(champ: @champ, dossier: @champ.dossier, apilexpol: apilexpol_fallback, user: current_user)
          service_fallback.upsert_dossier(force_create: force_create)

          flash[:notice] = "Dossier Lexpol #{@champ.value.blank? ? 'créé' : 'mis à jour'} avec succès (compte de service)"
        rescue APILexpol::LexpolAccessDenied => fallback_error
          Sentry.capture_exception(fallback_error)
          flash[:alert] = "Accès refusé à Lexpol. Votre compte (#{e.email_used}) et le compte de service (#{fallback_error.email_used}) " \
                          "n'ont pas les permissions nécessaires. Contactez votre administrateur."
        end
      else
        flash[:alert] = "Accès refusé à Lexpol avec le compte : #{e.email_used}. " \
                        "Vérifiez que ce compte est habilité dans Lexpol ou contactez votre administrateur."
      end

    rescue => e
      Sentry.capture_exception(e)
      mode = use_service_account ? "compte de service" : "votre compte (#{current_user.email})"
      flash[:alert] = "Impossible de #{@champ.value.blank? ? 'créer' : 'mettre à jour'} le dossier Lexpol avec #{mode}. #{e.message}"
    ensure
      redirect_back fallback_location: root_path
    end

    def preview_variables
      # pf: Récupérer le dossier et le type de champ sans passer par set_champ
      dossier = policy_scope(Dossier).includes(:champs, revision: [:revision_types_de_champ]).find(params[:dossier_id])
      type_de_champ = dossier.find_type_de_champ_by_stable_id(params[:stable_id])

      return render json: { error: 'Type de champ introuvable' }, status: :not_found unless type_de_champ

      temp_champ = build_temp_champ(dossier, type_de_champ)
      apilexpol = APILexpol.new(current_user.email, dossier.procedure&.service&.siret, should_use_test_user_for_dossier?(dossier))
      service = LexpolService.new(champ: temp_champ, dossier: dossier, apilexpol: apilexpol, user: current_user)

      variables = service.build_variables
      grouped = group_variables(variables, dossier)

      render json: { grouped_variables: grouped }
    rescue => e
      Sentry.capture_exception(e)
      render json: { error: 'Impossible de générer la prévisualisation' }, status: :unprocessable_entity
    end

    private

    def build_temp_champ(dossier, type_de_champ)
      # Créer un champ temporaire pour le service (sans le sauvegarder)
      # Note: instance_variable_set est utilisé car type_de_champ est une méthode calculée
      # sans setter. Acceptable ici car le champ est temporaire et non persisté.
      temp_champ = Champs::LexpolChamp.new(
        dossier: dossier,
        stable_id: type_de_champ.stable_id,
        private: type_de_champ.private?
      )
      temp_champ.instance_variable_set(:@type_de_champ, type_de_champ)
      temp_champ
    end

    def group_variables(variables, dossier)
      procedure = dossier.procedure
      column_labels = (procedure.dossier_columns_for_export + procedure.usager_columns_for_export).map(&:label)

      linked_service = LinkedDossierFieldsService.new(dossier, current_user)
      # Tous les suffixes (accessibles ou non) pour grouper correctement
      linked_suffixes = linked_service.linked_dossiers_info.map { |info| info[:suffixe] }

      metadonnees = variables.filter { |k, _v| column_labels.include?(k) }
      dossiers_lies = variables.filter { |k, _v| linked_suffixes.any? { |suffix| k.end_with?(" (#{suffix})") } }
      champs_formulaire = variables.except(*metadonnees.keys, *dossiers_lies.keys)

      {
        metadonnees: metadonnees.sort.to_h,
        champs_formulaire: champs_formulaire.sort.to_h,
        dossiers_lies: dossiers_lies.sort.to_h
      }
    end

    def should_use_test_user?
      # Utilise un compte de service pour :
      # - Les super admins (tests en production)
      # - Les révisions brouillon (développement)
      super_admin_signed_in? || @champ.dossier&.revision&.draft?
    end

    def should_use_test_user_for_dossier?(dossier)
      super_admin_signed_in? || dossier.revision&.draft?
    end

    # pf: Détermine si on doit utiliser le compte de service pour upsert
    # Utilise la révision du DOSSIER, pas de la procédure (un dossier peut être en test même si la procédure est publiée)
    # Pour les révisions draft : toujours utiliser le compte de service
    # Pour les révisions publiées : utiliser le compte personnel (fallback pour super-admins géré dans le rescue)
    def should_use_service_account?
      @champ.dossier&.revision&.draft?
    end

    # pf: Récupère le SIRET du service de la procédure
    def service_siret
      @champ.dossier&.procedure&.service&.siret
    end
  end
end
