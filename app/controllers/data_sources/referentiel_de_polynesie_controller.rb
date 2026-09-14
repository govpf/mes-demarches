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
      return render json: { message: 'Configuration du référentiel invalide' }, status: :unprocessable_entity
    end

    scopes = []
    dossier = nil

    if dlnuf.present?
      dossier = authorized_dossier
      return if performed?

      # pf: DLNUF — scope = mail du TITULAIRE (dossier.user), pas l'utilisateur connecté :
      # un invité doit préremplir avec les données du titulaire. Jamais lu depuis le client.
      email = dossier.user&.email&.downcase
      return render json: [] if email.blank? # pf: fail-closed silencieux (dossier orphelin prefillé, etc.)

      scopes << { field_id: dlnuf[:field_id], type: 'equal', value: email }
    end

    if @params[:stable_id].present?
      dossier ||= authorized_dossier
      return if performed?

      filter = contextual_filter_for(dossier, table)
      return if performed?

      if filter.configured?
        scope = contextual_scope(filter, table)
        # pf: cascade fail-closed — pilote vide, config invalide ou option introuvable → liste
        # vide, jamais la table entière
        return render json: [] if scope.nil?

        scopes << scope
      end
    end

    if scopes.empty? && (table.blank? || @params[:q].blank?)
      render json: { message: "table & q parameters are required" }, status: :bad_request
    else
      results = ReferentielDePolynesie::API.search_with_data(table, @params[:q], drop_down_other:, scopes:)
      render json: encrypted_results(results)
    end
  end

  private

  # pf: autorisation DLNUF / cascade — le dossier doit être accessible à current_user via
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

  # pf: cascade — le stable_id doit désigner un referentiel_de_polynesie de la révision du
  # dossier ET porter la table demandée (sinon un client pourrait filtrer une autre table
  # avec la config d'un autre champ).
  def contextual_filter_for(dossier, table)
    tdc = dossier.revision.types_de_champ.find { _1.stable_id == @params[:stable_id].to_i }
    if tdc.nil? || !tdc.referentiel_de_polynesie? || tdc.table_id != table.to_s
      render json: { message: 'Champ invalide pour cette table' }, status: :bad_request
      return nil
    end

    ReferentielDePolynesie::ContextualFilter.for(type_de_champ: tdc, dossier:, row_id: @params[:row_id])
  end

  def contextual_scope(filter, table)
    if filter.invalid?
      Sentry.capture_message('ReferentielDePolynesie: filtre contextuel invalide', extra: { table:, stable_id: @params[:stable_id] })
      return nil
    end
    return nil if filter.pilot_value.blank?

    filter.baserow_scope(ReferentielDePolynesie::API.table_fields(table))
  end

  def encrypted_results(results)
    results.map do |r|
      data = r[:row_data].present? ? message_encryptor_service.encrypt_and_sign(r[:row_data].to_json, purpose: :storage, expires_in: 1.hour) : ""
      r.slice(:label, :value).merge(data:)
    end
  end

  # pf: cascade — :pilot_version est un simple cache-buster côté client (digest de la valeur du
  # pilote) ; il n'est jamais lu ici, le scope étant recalculé côté serveur à chaque requête.
  def search_params = params.permit(:table, :q, :drop_down_other, :dossier_id, :stable_id, :row_id, :pilot_version)
end
