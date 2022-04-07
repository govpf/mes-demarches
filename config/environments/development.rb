require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Verifies that versions and hashed value of the package contents in the project's package.json
  config.webpacker.check_yarn_integrity = true

  # In the development environment your application's code is reloaded any time
  # it changes. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  config.public_file_server.enabled = true
  config.public_file_server.headers = { 'Cache-Control' => 'public, max-age=3600' }

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  config.active_storage.service = case ENV.fetch('OUTSCALE_STEP', "")
  when '-1'
    :local
  when '3'
    :s3_mirror
  when '2'
    :s3_mirror
  when '1'
    :local_mirror
  when '0'
    :local_mirror
  when '4'
    :s3
  else
    ENV.fetch("ACTIVE_STORAGE_SERVICE", 'local').to_sym
  end

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # Asset digests allow you to set far-future HTTP expiration dates on all assets,
  # yet still be able to expire them through the digest params.
  config.assets.digest = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Adds additional error checking when serving assets at runtime.
  # Checks for improperly declared sprockets dependencies.
  # Raises helpful error messages.
  config.assets.raise_runtime_errors = true

  # Action Mailer settings
  config.action_mailer.delivery_method = :letter_opener

  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST") }
  config.action_mailer.asset_host = "http://" + ENV.fetch("APP_HOST")

  Rails.application.routes.default_url_options = {
    host: ENV.fetch("APP_HOST"),
    protocol: :http
  }

  # Use Content-Security-Policy-Report-Only headers
  config.content_security_policy_report_only = true

  # Raises error for missing translations
  # config.action_view.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # We use the async adapter by default, but delayed_job can be set using
  # RAILS_QUEUE_ADAPTER=delayed_job bin/rails server
  config.active_job.queue_adapter = ENV.fetch('RAILS_QUEUE_ADAPTER', 'async').to_sym

  # Use an evented file watcher to asynchronously detect changes in source code,
  # routes, locales, etc. This feature depends on the listen gem.
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  config.hosts << ENV.fetch("APP_HOST")
end
