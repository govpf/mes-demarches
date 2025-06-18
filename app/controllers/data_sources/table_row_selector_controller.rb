# frozen_string_literal: true

class DataSources::TableRowSelectorController < ApplicationController
  before_action :authenticate_logged_user!

  def search
    @params = search_params
    if bad_parameters
      render json: { message: "table & q parameters are required" }, status: 400
    else
      render json: TableRowSelector::API.search(@params[:table], @params[:q])
    end
  end

  def bad_parameters
    @params[:table].blank? || @params[:q].blank?
  end

  def search_params = params.permit(:table, :q)
end
