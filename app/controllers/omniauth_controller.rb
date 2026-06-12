# frozen_string_literal: true

class OmniauthController < ApplicationController
  before_action :redirect_to_login_if_connection_aborted, only: [:callback]
  before_action :securely_retrieve_fci, only: [:merge, :merge_with_existing_account, :merge_with_new_account, :mail_merge_with_existing_account, :resend_and_renew_merge_confirmation, :send_email_merge_request, :merge_using_provider_email]
  before_action :securely_retrieve_fci_from_email_merge_token, only: [:merge_using_email_link]
  before_action :set_user_by_confirmation_token, only: [:confirm_email]

  def login
    provider = provider_param
    # already checked in routes.rb but brakeman complains
    if OmniAuthService.enabled?(provider)
      # pf: sécurité (F2) — state/nonce stockés en session pour validation au callback
      state = SecureRandom.hex(16)
      nonce = SecureRandom.hex(16)
      session[:omniauth_state] = state
      session[:omniauth_nonce] = nonce
      redirect_to OmniAuthService.authorization_uri(provider, state:, nonce:), allow_other_host: true
    else
      redirect_to new_user_session_path
    end
  end

  def callback
    provider = provider_param
    return redirect_to(new_user_session_path) unless valid_omniauth_state?

    @fci = OmniAuthService.find_or_retrieve_user_informations(provider, params[:code])

    if @fci.user.nil?
      preexisting_unlinked_user = User.find_by(email: sanitize(@fci.email_france_connect))

      if preexisting_unlinked_user.nil?
        @fci.create_merge_token!
        @provider = provider
        render :choose_email
      elsif !preexisting_unlinked_user.can_openid_connect?(provider)
        @fci.destroy
        redirect_to new_user_session_path, alert: t('errors.messages.omniauth.forbidden_html', reset_link: new_user_password_path, provider: t("omniauth.provider.#{provider}"))
      else
        redirect_to omniauth_merge_path(provider, @fci.create_merge_token!)
      end
    else
      user = @fci.user

      if user.can_openid_connect?(provider)
        @fci.update(updated_at: Time.zone.now)
        connect_user(provider, user)
      else # same behaviour as redirect nicely with message when instructeur/administrateur
        @fci.destroy
        redirect_to new_user_session_path, alert: t('errors.messages.omniauth.forbidden_html', reset_link: new_user_password_path, provider: t("omniauth.provider.#{provider}"))
      end
    end

  rescue Rack::OAuth2::Client::Error => e
    Rails.logger.error e.message
    redirect_error_connection(provider)
  end

  def merge
    @provider = provider_param
  end

  def merge_with_existing_account
    # pf: utilisation de l'email depuis @fci comme dans FranceConnect
    user = User.find_by(email: sanitize(@fci.email_france_connect))
    provider = provider_param

    if user.present? && user.valid_for_authentication? { user.valid_password?(password_params) }
      if !user.can_openid_connect?(provider)
        return destroy_fci_and_redirect_to_login(@fci)
      else
        @fci.safely_update_user(user: user)
        user.update!(email_verified_at: Time.current)

        flash.notice = t('omniauth.flash.connection_done', application_name: Current.application_name, provider: t("omniauth.provider.#{provider}"))
        connect_user(provider, user)
      end
    else
      flash.alert = t('omniauth.flash.invalid_password')
      redirect_to omniauth_merge_path(provider, @fci.merge_token)
    end
  end

  def mail_merge_with_existing_account
    user = User.find_by(email: sanitize(@fci.email_france_connect))
    provider = provider_param
    if user.can_openid_connect?(provider)
      @fci.safely_update_user(user: user)
      user.update!(email_verified_at: Time.current)

      flash.notice = t('omniauth.flash.connection_done', application_name: Current.application_name, provider: t("omniauth.provider.#{provider}"))
      connect_user(provider, user)
    else # same behaviour as redirect nicely with message when instructeur/administrateur
      destroy_fci_and_redirect_to_login(@fci)
    end
  end

  def merge_with_new_account
    user = User.find_by(email: sanitized_email_params)
    provider = provider_param

    if user.nil?
      @fci.safely_associate_user!(sanitized_email_params)
      @fci.user.update!(email_verified_at: Time.current)

      flash.notice = t('omniauth.flash.connection_done', application_name: Current.application_name, provider: t("omniauth.provider.#{provider}"))
      connect_user(provider, @fci.user)
    else
      # L'email appartient à un autre utilisateur, envoyer un email de confirmation
      @fci.update(requested_email: sanitized_email_params)

      @fci.create_email_merge_token!
      provider = provider_param

      UserMailer.omniauth_merge_confirmation(@fci.email_france_connect, @fci.email_merge_token, @fci.email_merge_token_created_at, provider)
        .deliver_later

      redirect_to root_path, notice: t('omniauth.flash.confirmation_mail_sent')
    end
  end

  def resend_and_renew_merge_confirmation
    merge_token = @fci.create_merge_token!
    provider = provider_param
    UserMailer.omniauth_merge_confirmation(@fci.email_france_connect, @fci.email_merge_token, @fci.email_merge_token_created_at, provider).deliver_later
    redirect_to omniauth_merge_path(provider:, merge_token:),
                notice: t('omniauth.flash.confirmation_mail_sent')
  end

  def send_email_merge_request
    @fci.update(requested_email: sanitized_email_params)
    provider = provider_param

    @fci.create_email_merge_token!
    UserMailer.omniauth_merge_confirmation(
      sanitized_email_params,
      @fci.email_merge_token,
      @fci.email_merge_token_created_at,
      provider
    )
      .deliver_later

    redirect_to root_path, notice: t('omniauth.flash.confirmation_mail_sent')
  end

  def merge_using_provider_email
    @fci.safely_associate_user!(@fci.email_france_connect)
    @fci.user.update!(email_verified_at: Time.current)
    provider = provider_param

    flash.notice = t('omniauth.flash.connection_done', application_name: Current.application_name, provider: t("omniauth.provider.#{provider}"))
    connect_user(provider, @fci.user)
  end

  def merge_using_email_link
    user = User.find_by(email: @fci.requested_email)
    provider = provider_param

    if user.present? && !user.can_openid_connect?(provider)
      return destroy_fci_and_redirect_to_login(@fci)
    end

    if user.nil?
      @fci.safely_associate_user!(@fci.requested_email)
    else
      @fci.safely_update_user(user:)
    end

    @fci.user.update(email_verified_at: Time.zone.now)

    flash.notice = t('omniauth.flash.connection_done', application_name: Current.application_name, provider: t("omniauth.provider.#{provider}"))
    connect_user(provider, @fci.user)
  end

  def confirm_email
    if @user.confirmation_sent_at && 2.days.ago < @user.confirmation_sent_at
      @user.update(email_verified_at: Time.zone.now, confirmation_token: nil)
      @user.after_confirmation
      redirect_to destination_path(@user), notice: I18n.t('omniauth.flash.email_confirmed')
      return
    end

    fci = FranceConnectInformation.find_by(user: @user)

    if fci
      fci.send_custom_confirmation_instructions(provider_type: :omniauth)
      redirect_to root_path, notice: I18n.t('omniauth.flash.confirmation_mail_resent')
    else
      redirect_to root_path, alert: I18n.t('omniauth.flash.confirmation_mail_resent_error')
    end
  end

  private

  def securely_retrieve_fci
    @fci = FranceConnectInformation.find_by(merge_token: merge_token_params)
    provider = provider_param

    if @fci.nil? || !@fci.valid_for_merge?
      flash.alert = t('omniauth.flash.merger_token_expired', application_name: Current.application_name, provider: t("omniauth.provider.#{provider}"))

      redirect_to root_path
    end
  end

  def securely_retrieve_fci_from_email_merge_token
    @fci = FranceConnectInformation.find_by(email_merge_token: params[:email_merge_token])
    provider = provider_param

    if @fci.nil? || !@fci.valid_for_email_merge?
      flash.alert = t('omniauth.flash.merger_token_expired', application_name: Current.application_name, provider: t("omniauth.provider.#{provider}"))

      redirect_to root_path
    else
      @fci.delete_email_merge_token!
    end
  end

  def redirect_to_login_if_connection_aborted
    if params[:code].blank?
      redirect_to new_user_session_path
    end
  end

  # pf: sécurité (F2) — valide le state OAuth contre la valeur stockée en session au
  # login (anti-CSRF). Usage unique : la valeur de session est purgée à la lecture.
  def valid_omniauth_state?
    expected_state = session.delete(:omniauth_state)
    received_state = params[:state]

    expected_state.present? &&
      received_state.present? &&
      ActiveSupport::SecurityUtils.secure_compare(received_state, expected_state)
  end

  def connect_user(provider, user)
    if user_signed_in?
      sign_out :user
    end

    sign_in user

    user.update_attribute('loged_in_with_france_connect', User.loged_in_with_france_connects.fetch(provider))

    redirect_to stored_location_for(current_user) || root_path(current_user)
  end

  def provider_param
    params[:provider]
  end

  def redirect_error_connection(provider)
    flash.alert = t("errors.messages.omniauth.connexion", provider: t("omniauth.provider.#{provider}"))
    redirect_to(new_user_session_path)
  end

  def destroy_fci_and_redirect_to_login(fci)
    fci.destroy
    redirect_to new_user_session_path, alert: t('errors.messages.omniauth.forbidden_html', reset_link: new_user_password_path, provider: t("omniauth.provider.#{provider_param}"))
  end

  def set_user_by_confirmation_token
    @user = User.find_by(confirmation_token: params[:token])

    if @user.nil?
      return redirect_to root_path, alert: I18n.t('omniauth.flash.user_not_found')
    end

    if user_signed_in? && current_user != @user
      sign_out :user
      redirect_to new_user_session_path, alert: I18n.t('omniauth.flash.redirect_new_user_session')
    end
  end

  def destination_path(user) = stored_location_for(user) || root_path(user)

  def merge_token_params
    params[:merge_token]
  end

  def password_params
    params[:password]
  end

  def sanitized_email_params
    sanitize(params[:email])
  end

  # pf: harmonisation avec France Connect pour maintenir la cohérence UX
  def sanitize(string)
    string&.gsub(/[[:space:]]/, ' ')&.strip&.downcase
  end
end
