Flipflop.configure do
  strategy :cookie,
    secure: Rails.env.production?,
    httponly: true
  strategy :active_record
  strategy :user_preference
  strategy :default

  group :champs do
    feature :champ_integer_number,
      title: "Champ nombre entier"
  end

  feature :web_hook

  feature :operation_log_serialize_subject
  feature :download_as_zip_enabled
  feature :bypass_email_login_token,
    default: Rails.env.test?

  group :development do
    feature :mini_profiler_enabled,
      default: Rails.env.development?
    feature :xray_enabled,
      default: Rails.env.development?
  end

  group :production do
    feature :insee_api_v3,
      default: true
    feature :pre_maintenance_mode
    feature :maintenance_mode
  end

  if Rails.env.test?
    # It would be nicer to configure this in administrateur_spec.rb in #feature_enabled?,
    # but that results in a FrozenError: can't modify frozen Hash

    feature :test_a
    feature :test_b
  end
end
