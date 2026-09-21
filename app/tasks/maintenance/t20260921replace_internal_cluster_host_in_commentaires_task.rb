# frozen_string_literal: true

module Maintenance
  class T20260921replaceInternalClusterHostInCommentairesTask < MaintenanceTasks::Task
    # Documentation : pf: remplace, dans le corps des commentaires, l'hôte interne du cluster
    # (*.svc.cluster.local, avec port éventuel) par l'hôte public APP_HOST.
    # Origine : quand un robot acceptait un dossier via l'API GraphQL en appelant le nom de service
    # interne, Current.host prenait cette valeur et le commentaire miroir du mail de décision
    # (« Email automatique ») était généré avec des liens dossier / attestation inaccessibles.
    # Le flux est corrigé dans API::V2::BaseController (Current.host forcé à APP_HOST) ;
    # cette task répare l'historique. Le schéma (http/https) et le chemin sont conservés.

    include RunnableOnDeployConcern
    include StatementsHelpersConcern

    run_on_first_deploy

    INTERNAL_HOST_SUFFIX = '.svc.cluster.local'
    INTERNAL_URL_HOST = %r{(https?://)[a-z0-9.-]+#{Regexp.escape(INTERNAL_HOST_SUFFIX)}(?::\d+)?}i

    def collection
      Commentaire.where("body LIKE ?", "%#{INTERNAL_HOST_SUFFIX}%")
    end

    def process(commentaire)
      fixed_body = commentaire.body.gsub(INTERNAL_URL_HOST) { "#{Regexp.last_match(1)}#{ENV['APP_HOST']}" }
      return if fixed_body == commentaire.body

      # update_columns : pas de touch du dossier ni de mise à jour d'updated_at, c'est une réparation de données
      commentaire.update_columns(body: fixed_body)
    end
  end
end
