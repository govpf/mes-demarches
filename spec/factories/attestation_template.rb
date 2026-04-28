# frozen_string_literal: true

FactoryBot.define do
  factory :attestation_template do
    title { 'title' }
    body { 'body' }
    json_body { nil }
    footer { 'footer' }
    activated { true }
    version { 1 }
    official_layout { true }
    label_direction { nil }
    label_logo { nil }
    kind { 'acceptation' }
    association :procedure
  end

  trait :refus do
    kind { 'refus' }
  end

  trait :v2 do
    version { 2 }
    body { nil }
    title { nil }
    label_logo { "Ministère des devs" }

    json_body do
      {
        "type" => "doc",
        "content" => [
          {
            "type" => "header", "content" => [
              { "type" => "headerColumn", "attrs" => { "textAlign" => "left" }, "content" => [{ "type" => "paragraph", "attrs" => { "textAlign" => "left" } }] },
              { "type" => "headerColumn", "attrs" => { "textAlign" => "left" }, "content" => [{ "type" => "paragraph", "attrs" => { "textAlign" => "left" } }] }
            ]
          },
          { "type" => "title", "attrs" => { "textAlign" => "center" }, "content" => [{ "text" => "Mon titre pour ", "type" => "text" }, { "type" => "mention", "attrs" => { "id" => "dossier_procedure_libelle", "label" => "libellé démarche" } }] },
          { "type" => "paragraph", "attrs" => { "textAlign" => "left" }, "content" => [{ "text" => "Dossier: n° ", "type" => "text" }, { "type" => "mention", "attrs" => { "id" => "dossier_number", "label" => "numéro du dossier" } }] },
          {
            "type" => "paragraph",
            "content" => [
              { "text" => "Nom: ", "type" => "text" }, { "type" => "mention", "attrs" => { "id" => "individual_last_name", "label" => "prénom" } }, { "text" => " ", "type" => "text" },
              { "type" => "mention", "attrs" => { "id" => "individual_first_name", "label" => "nom" } }, { "text" => " ", "type" => "text" }
            ]
          }
        ]
      }
    end
  end

  trait :with_files do
    logo { Rack::Test::UploadedFile.new('spec/fixtures/files/logo_test_procedure.png', 'image/png') }
    signature { Rack::Test::UploadedFile.new('spec/fixtures/files/logo_test_procedure.png', 'image/png') }
  end

  trait :with_gif_files do
    logo { Rack::Test::UploadedFile.new('./spec/fixtures/files/french-flag.gif', 'image/gif') }
    signature { Rack::Test::UploadedFile.new('./spec/fixtures/files/beta-gouv.gif', 'image/gif') }
  end

  # Traits pour les tests de migration v1→v2
  trait :v1_with_basic_formatting do
    version { 1 }
    title { 'Titre avec <b>formatage gras</b>' }
    body { 'Corps avec <i>italique</i> et <u>souligné</u>' }
    footer { 'Pied de page standard' }
    activated { true }
  end

  trait :v1_with_complex_formatting do
    version { 1 }
    title { 'Titre <strong>fort</strong> et <em>emphase</em>' }
    body { 'Texte <b><i>gras et italique</i></b> combinés' }
    footer { 'Footer avec <u>soulignage</u>' }
    activated { true }
  end

  trait :v1_with_tables do
    version { 1 }
    title { 'Attestation avec tableau' }
    body do
      '<p>Voici un tableau:</p>
       <table>
         <tr><th>Nom</th><th>Prénom</th></tr>
         <tr><td>Dupont</td><td>Jean</td></tr>
         <tr><td>Martin</td><td>Marie</td></tr>
       </table>
       <p>Fin du tableau</p>'
    end
    activated { true }
  end

  trait :v1_plain_text do
    version { 1 }
    title { 'Titre simple sans formatage' }
    body { 'Corps simple sans aucun formatage HTML' }
    footer { 'Pied de page simple' }
    activated { false }
  end

  trait :v1_empty do
    version { 1 }
    title { nil }
    body { nil }
    footer { '' }
    activated { false }
  end

  # États de publication pour tests
  trait :draft do
    state { 'draft' }
  end

  trait :published do
    state { 'published' }
  end
end
