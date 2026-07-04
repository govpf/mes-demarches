# frozen_string_literal: true

class DataSources::ReferentielDePolynesieController < ApplicationController
  before_action :authenticate_logged_user!

  def search
    @params = search_params
    if bad_parameters
      render json: { message: "table & q parameters are required" }, status: 400
    else
      drop_down_other = ActiveModel::Type::Boolean.new.cast(@params[:drop_down_other])
      results = ReferentielDePolynesie::API.search_with_data(@params[:table], @params[:q], drop_down_other:)
      render json: results.map { |r|
        data = r[:row_data].present? ? message_encryptor_service.encrypt_and_sign(r[:row_data].to_json, purpose: :storage, expires_in: 1.hour) : ""
        r.slice(:label, :value).merge(data:)
      }
    end
  end

  def bad_parameters
    @params[:table].blank? || @params[:q].blank?
  end

  def search_params = params.permit(:table, :q, :drop_down_other)
end
