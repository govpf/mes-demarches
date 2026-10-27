# frozen_string_literal: true

class API::Public::V1::JSONDescriptionProceduresController < API::Public::V1::BaseController
  skip_before_action :check_content_type_is_json
  before_action :retrieve_procedure

  def show
    render json: procedure_graph_ql_schema, status: 200
  end

  private

  def retrieve_procedure
    @procedure = Procedure.publiees_ou_brouillons.opendata.find_with_path(params[:path]).first
    render_not_found("procedure", params[:path]) if @procedure.blank?
  end

  def procedure_graph_ql_schema
    API::V2::Schema.execute(API::V2::StoredQuery.get('ds-query-v2'),
      variables: {
        demarche: { "number": @procedure.id },
        includeRevision: true,
      },
      context: unauthenticated_context,
      operation_name: "getDemarcheDescriptor")
      .to_h.dig("data", "demarcheDescriptor").to_json
  end

  def unauthenticated_context
    {
      administrateur_id: nil,
      procedure_ids: [],
      write_access: false,
      remote_ip: request.remote_ip,
    }
  end
end
