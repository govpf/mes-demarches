# frozen_string_literal: true

class DataSources::ReferentielDePolynesieController < ApplicationController
  before_action :authenticate_logged_user!

  def search
    @params = search_params
    table = @params[:table]
    dlnuf = ReferentielDePolynesie::API.dlnuf_config(table)
    drop_down_other = ActiveModel::Type::Boolean.new.cast(@params[:drop_down_other])

    if dlnuf == :invalid
      # pf: fail-closed — champ propriétaire mort : refuser d'exposer, JAMAIS de repli en
      # catalogue ouvert (les données personnelles seraient déclassées en liste publique)
      Sentry.capture_message('ReferentielDePolynesie: champ propriétaire invalide', extra: { table: })
      render json: { message: 'Configuration du référentiel invalide' }, status: :unprocessable_entity
    elsif dlnuf.present?
      dossier = authorized_dossier
      return if performed?

      # pf: DLNUF — scope = mail du TITULAIRE (dossier.user), pas l'utilisateur connecté :
      # un invité doit préremplir avec les données du titulaire. Jamais lu depuis le client.
      email = dossier.user&.email&.downcase
      if email.blank?
        render json: [] # pf: fail-closed silencieux (dossier orphelin prefillé, etc.)
      else
        results = ReferentielDePolynesie::API.search_with_data(
          table, @params[:q], drop_down_other:, scope: { field_id: dlnuf[:field_id], value: email }
        )
        render json: encrypted_results(results)
      end
    elsif table.blank? || @params[:q].blank?
      render json: { message: "table & q parameters are required" }, status: :bad_request
    else
      results = ReferentielDePolynesie::API.search_with_data(table, @params[:q], drop_down_other:)
      render json: encrypted_results(results)
    end
  end

  private

  # pf: autorisation DLNUF — le dossier doit être accessible à current_user via
  # DossierPolicy::Scope (propriétaire, invité, instructeur assigné — l'ancre de scope
  # reste le mail du titulaire). La clause preview du Scope étant globale, on exige en
  # plus qu'un dossier de preview appartienne à current_user : sinon n'importe quel
  # usager pourrait ancrer le scope sur le mail de l'admin d'une autre démarche.
  def authorized_dossier
    dossier = policy_scope(Dossier).find_by(id: @params[:dossier_id])
    if dossier.nil? || (dossier.for_procedure_preview? && dossier.user != current_user)
      render json: { message: 'Accès refusé' }, status: :forbidden
      return nil
    end
    dossier
  end

  def encrypted_results(results)
    results.map do |r|
      data = r[:row_data].present? ? message_encryptor_service.encrypt_and_sign(r[:row_data].to_json, purpose: :storage, expires_in: 1.hour) : ""
      r.slice(:label, :value).merge(data:)
    end
  end

  def search_params = params.permit(:table, :q, :drop_down_other, :dossier_id)
end
