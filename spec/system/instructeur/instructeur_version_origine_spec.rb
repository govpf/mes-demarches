# frozen_string_literal: true

describe 'Instructeur — version d’origine d’un dossier déposé', js: true do
  let(:procedure) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :text, libelle: 'Raison sociale' },
      { type: :piece_justificative, libelle: 'Liste des produits' },
    ], instructeurs: [instructeur])
  end
  # pf: le cahier des charges upstream utilise `create(:instructeur, procedures: [procedure])`,
  # qui lève `ActiveRecord::HasManyThroughNestedAssociationsAreReadonly` sur ce fork —
  # `Instructeur#procedures` passe par `unordered_groupe_instructeurs`, elle-même
  # un `has_many :through`, et un through imbriqué est en lecture seule côté Rails.
  # On câble dans le sens supporté par la factory `:procedure` (`instructeurs:` +
  # `assign_to_procedure`, cf. spec/factories/procedure.rb), déjà utilisé à la Task 2.
  let(:instructeur) { create(:instructeur) }
  let(:dossier) { create(:dossier, :en_construction, :with_populated_champs, procedure:) }
  let(:tdc_pj) { procedure.active_revision.types_de_champ_public.find(&:piece_justificative?) }

  before do
    # L'usager remplit le formulaire, pièce jointe incluse.
    # :with_populated_champs a créé les lignes `champs` : on attache le fichier
    # sur celle du champ pièce jointe.
    champ_pj = dossier.champs.find_by(stable_id: tdc_pj.stable_id)
    champ_pj.piece_justificative_file.attach(
      io: StringIO.new('contenu du tableur'),
      filename: 'liste-produits.xlsx',
      # on ne veut pas déclencher l'antivirus dans les tests
      metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
    )

    # Le dépôt est postérieur à la saisie
    dossier.update_columns(en_construction_at: Time.current, submitted_revision_id: dossier.revision_id)

    # L'admin supprime le champ pièce jointe et republie
    procedure.draft_revision.remove_type_de_champ(tdc_pj.stable_id)
    procedure.publish_revision!(procedure.administrateurs.first)
    dossier.reload.rebase!

    login_as instructeur.user, scope: :user
  end

  scenario 'l’instructeur retrouve la pièce jointe du champ supprimé' do
    visit instructeur_dossier_path(procedure, dossier)

    # le champ supprimé n'est plus dans le formulaire courant
    expect(page).not_to have_content('Liste des produits')

    # la bannière propose la version d'origine
    expect(page).to have_content('Il ne s’agit pas de la version d’origine déposée par l’usager')
    click_on 'Afficher la version d’origine'

    # le champ supprimé et son fichier réapparaissent
    expect(page).to have_content('Liste des produits')
    expect(page).to have_link('liste-produits.xlsx')
  end

  scenario 'aucune bannière quand la révision n’a pas changé depuis le dépôt' do
    autre_dossier = create(:dossier, :en_construction, :with_populated_champs, procedure:)
    autre_dossier.update_columns(submitted_revision_id: autre_dossier.revision_id)

    visit instructeur_dossier_path(procedure, autre_dossier)

    expect(page).not_to have_content('Afficher la version d’origine')
  end

  scenario 'la bannière n’apparaît ni côté usager, ni en boucle sur la page « version d’origine »' do
    # Côté usager, le dossier doit s'aligner sur la version officielle
    # courante, pas exposer un historique : jamais de bannière, même si la
    # révision a changé depuis le dépôt (c'est le même dossier que le
    # scénario ci-dessus, avec le même champ supprimé).
    login_as dossier.user, scope: :user
    visit demande_dossier_path(dossier)

    expect(page).to have_content('Raison sociale')
    expect(page).not_to have_content('Afficher la version d’origine')

    # La page « version d'origine » elle-même ne doit pas afficher la
    # bannière : le before_action `dossier_with_submitted_revision` réassigne
    # @dossier.revision = @dossier.submitted_revision avant le rendu, ce qui
    # rend `revision_changed_since_submitted?` faux à ce moment précis. Sans
    # test, une régression future qui romprait cet enchaînement (par exemple
    # en déplaçant l'affectation après le rendu, ou en la retirant) ferait
    # boucler la bannière sur elle-même sans qu'aucun test ne s'en aperçoive.
    login_as instructeur.user, scope: :user
    visit original_instructeur_dossier_path(procedure, dossier)

    expect(page).to have_content('Liste des produits')
    expect(page).not_to have_content('Afficher la version d’origine')
  end
end
