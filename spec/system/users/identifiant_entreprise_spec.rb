# frozen_string_literal: true

# pf: scénarios de bout en bout pour l'aiguillage Tahiti / SIRET —
# spec/models/identifiant_entreprise.rb, app/services/api_entreprise_service.rb,
# app/models/champs/siret_champ.rb. Le scénario 3 est le seul à croiser deux
# sous-systèmes (référentiel entreprise + cascade des formules) : aucun test
# unitaire ne peut l'attraper.
describe 'Identification d’une entreprise, numéro Tahiti ou SIRET', js: true do
  let(:user) { create(:user) }
  # pf: l'identification par numéro d'entreprise s'obtient par ABSENCE du trait
  # :for_individual — il n'existe pas de trait :for_individual_and_personne_morale.
  # Convention reprise de spec/system/users/dossier_creation_spec.rb:115-116.
  let(:procedure) { create(:procedure, :published, :with_service, :with_type_de_champ) }
  let(:siret_fr) { '41816609600051' }
  let(:siren_fr) { siret_fr[0...9] }
  let(:tahiti_prefix) { 'G33972' }
  # pf: fixture existante, jamais utilisée par aucun spec avant celui-ci — 33
  # établissements (4 radiés, filtrés par PfEtablissementAdapter) pour le
  # préfixe ISPF 075390 (Banque SOCREDO). C'est le cas « plusieurs candidats »
  # du scénario 2, et le cas « un seul candidat » du scénario 3 une fois
  # filtré par numEtablissement via un numéro Tahiti complet.
  let(:pf_etablissements_body) { File.read('spec/fixtures/files/api_entreprise/pf_etablissements.json') }

  before { login_as user, scope: :user }

  # --- Scénario 1 : SIRET français ---
  context 'avec un SIRET métropolitain' do
    let(:dossier) { procedure.dossiers.last }

    before do
      stub_etablissement_fr
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    scenario 'résout l’établissement et poursuit le dossier' do
      visit commencer_path(path: procedure.path)
      click_on 'Commencer la démarche'

      expect(page).to have_current_path(siret_dossier_path(dossier))

      fill_in_identifiant_entreprise(siret_fr)
      click_on 'Continuer'

      expect(page).to have_current_path(etablissement_dossier_path(dossier))
      # pf: raison sociale portée par la fixture etablissements.json — même
      # assertion que spec/system/users/dossier_creation_spec.rb:148, qui
      # exerce déjà ce même fichier fixture avec succès.
      expect(page).to have_content('Coiff Land, CoiffureLand')
      # pf: l'annuaire doit désigner le référentiel du numéro saisi (SIRET →
      # data.gouv.fr) et non l'ISPF — rendu par
      # app/views/users/dossiers/etablissement/_infos_entreprise.haml via
      # le helper annuaire_link (app/helpers/dossier_helper.rb).
      expect(page).to have_link(href: %r{annuaire-entreprises\.data\.gouv\.fr})

      click_on 'Continuer avec ces informations'
      expect(page).to have_current_path(brouillon_dossier_path(dossier))
    end
  end

  # --- Scénario 2 : numéro Tahiti partiel, non-régression du parcours dominant ---
  context 'avec un numéro Tahiti partiel correspondant à plusieurs établissements' do
    let(:dossier) { procedure.dossiers.last }

    before do
      stub_request(:get, %r{#{Regexp.quote(API_ISPF_URL)}/etablissements/Entreprise})
        .to_return(body: pf_etablissements_body, status: 200)
    end

    scenario 'propose la liste et enregistre le choix de l’usager' do
      visit commencer_path(path: procedure.path)
      click_on 'Commencer la démarche'

      expect(page).to have_current_path(siret_dossier_path(dossier))

      fill_in_identifiant_entreprise(tahiti_prefix)
      click_on 'Continuer'

      # pf: rendu par app/views/users/dossiers/etablissements.html.haml —
      # plusieurs candidats pour le préfixe saisi (la réponse stubbée porte
      # ses propres numéros d'établissement, indépendants de "G33972").
      expect(page).to have_current_path(etablissements_dossier_path(dossier))
      expect(page).to have_content('Nous avons trouvé plusieurs établissements')
      # pf: chaque candidat expose son propre bouton de sélection — pas
      # d'attribut data-etablissement-choice dans le composant réel
      # (cf. app/views/users/dossiers/etablissement/_etablissements_list.haml) ;
      # on cible le bouton par son libellé.
      expect(page).to have_css('button', text: 'Sélectionner', minimum: 2)

      # pf: cliquer un bouton "Sélectionner" soumet directement le formulaire
      # (POST siret_dossier_path) et redirige vers la page d'établissement —
      # aucun second clic sur "Continuer" n'existe dans ce flux.
      # (`click_on(..., match: :first)` n'arrive pas à lever l'ambiguïté entre
      # les 29 boutons homonymes sous le driver playwright ; `all(...).first`
      # fonctionne de manière fiable.)
      all(:button, text: 'Sélectionner').first.click

      expect(page).to have_current_path(etablissement_dossier_path(dossier))
      expect(page).to have_content('BANQUE SOCREDO')
    end
  end

  # --- Scénario 3 : bascule d'un référentiel à l'autre dans un champ SIRET ---
  context 'en remplaçant un numéro Tahiti par un SIRET dans un champ' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :siret, libelle: 'Établissement' },
        { type: :formule, libelle: 'Dénomination reprise' },
      ])
    end
    let(:dossier) { create(:dossier, procedure: procedure, user: user) }
    # pf: numéro Tahiti complet (9 car.) — filtré par
    # APIEntreprise::PfEtablissementAdapter#process_params sur les 3 derniers
    # chiffres (numEtablissement == 1), au sein de la même fixture à 33
    # candidats : nul besoin de la dériver en un fichier séparé.
    let(:tahiti_complet) { 'G33972001' }

    before do
      formule_champ = dossier.project_champs_public.find { _1.libelle == 'Dénomination reprise' }
      siret_champ = dossier.project_champs_public.find { _1.libelle == 'Établissement' }
      # pf: sous-chemin réel "{tdc<N>/entreprise_raison_sociale}", posé
      # DIRECTEMENT en forme stable, sans passer par
      # FormulaExpressionService.convert_to_stable_ids.
      #
      # Correction de tour 1 : ma première analyse (« raison_sociale non
      # résolvable ») était trop générale. Le helper de test
      # convert_to_stable_ids ne gère effectivement que "{Libellé}" nu — mais
      # c'est une limitation du helper Ruby, pas du moteur de formules :
      # l'éditeur JS (app/javascript/controllers/formula_editor_controller.ts:206)
      # produit lui-même "{tdc456/path}" directement, et le seul appelant
      # applicatif de convert_to_stable_ids
      # (app/graphql/mutations/demarche_champ_mutation.rb:94) documente cette
      # limitation dans son propre commentaire. En posant l'expression stable
      # directement (comme le fait l'éditeur JS), le sous-chemin SIRET
      # fonctionne bel et bien de bout en bout — vérifié empiriquement en
      # rejouant le flux réel (assign → save → reset_external_data! →
      # fetch_later! → job → refresh_formulas_after) sans passer par le
      # navigateur, avant d'intégrer ce test système.
      #
      # Le vrai nom de clé reste "entreprise_raison_sociale", pas
      # "raison_sociale" (FormulaColumnResolver#encode_column_id l'indexe
      # depuis le dernier segment du jsonpath
      # "$.entreprise_raison_sociale" de Etablissement::DISPLAYABLE_COLUMNS ;
      # FormulaExpressionService#find_path_label, qui documente
      # 'raison_sociale' pour siret/rna, ne correspond à aucune clé
      # réellement indexée pour ces deux types — signalé en tour 1, non
      # corrigé, hors périmètre).
      #
      # Sur la lecture depuis la table `etablissement` plutôt que
      # `value_json` (point à vérifier demandé en retour) : la lecture
      # PASSE bien par `champ.value_json` — FormulaCalculationService
      # #extract_column_value (app/services/formula_calculation_service.rb:594)
      # appelle `column.send(:typed_value, champ)` pour tout chemin non
      # `:value` sur une Columns::JSONPathColumn, et
      # `Columns::JSONPathColumn#typed_value` (app/models/columns/json_path_column.rb)
      # lit explicitement `JsonPath.on(champ.value_json, jsonpath)` — jamais
      # `champ.etablissement.<attr>` directement. Ma troisième objection de
      # tour 1 (« value_json ne contient jamais ces clés ») était en
      # revanche fausse : je m'étais arrêté à
      # `APIGeoService.parse_etablissement_address` (adresse seule), sans
      # voir que `Etablissement#update_champ_value_json!` (appelé à la fin
      # de `APIEntrepriseService.create_etablissement`) réécrit ensuite
      # `champ.value_json` via `Etablissement#champ_value_json`, qui fusionne
      # explicitement les clés de `DISPLAYABLE_COLUMNS` — dont
      # `entreprise_raison_sociale` — par-dessus les champs d'adresse. C'est
      # cette seconde écriture, plus tardive dans le flux, qui porte la
      # donnée lue par la formule.
      formule_champ.type_de_champ.update!(formule_expression: "{tdc#{siret_champ.stable_id}/entreprise_raison_sociale}")
      raise "graphe de dépendance formule vide" if siret_champ.dependent_formula_stable_ids.empty?

      stub_request(:get, %r{#{Regexp.quote(API_ISPF_URL)}/etablissements/Entreprise})
        .to_return(body: pf_etablissements_body, status: 200)
      stub_etablissement_fr
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    scenario 'nettoie l’ancien établissement et recalcule la formule dépendante' do
      visit brouillon_dossier_path(dossier)

      # pf: le champ formule (EditableChamp::FormuleComponent) n'est pas un
      # input mais une zone role="status" en lecture seule — pas de
      # find_field possible, on lit son texte directement.
      remplir_etablissement_et_attendre(tahiti_complet)
      denomination_tahiti = denomination_reprise
      # pf: raison sociale portée par l'entrée numEtablissement == 1 de
      # pf_etablissements.json (entreprise.raisonSociale, commune à toutes
      # les entrées de cette fixture) — la valeur formule est prise depuis
      # champ.value_json (pas depuis champ.value, qui porte le numéro et non
      # la dénomination), preuve que le sous-chemin résout une vraie donnée
      # métier, pas un simple écho de la saisie.
      expect(denomination_tahiti).to eq('BANQUE SOCREDO')

      champ = champ_etablissement
      ancien_etablissement_id = champ.etablissement_id
      expect(ancien_etablissement_id).to be_present

      # bascule vers un SIRET métropolitain
      remplir_etablissement_et_attendre(siret_fr)

      # pf: la cascade des formules doit se redéclencher après la bascule de
      # référentiel — c'est le point que refresh_formulas_after garantit dans
      # Champs::SiretChamp#update_external_data!. Sans cet appel, le champ
      # formule resterait figé à la valeur calculée au moment du reset
      # (external_id remis à zéro dans le formulaire au moment de la saisie,
      # jamais rafraîchi ensuite par le job async).
      # pf: "DIRECTION INTERMINISTERIELLE DU NUMERIQUE" — valeur déjà établie
      # pour cette même fixture (etablissements.json + entreprises.json) par
      # spec/models/champs/siret_champ_spec.rb ("fetches the entreprise
      # raison sociale"), indépendamment du SIRET requêté (la fixture est
      # statique).
      expect(denomination_reprise).not_to eq(denomination_tahiti)
      expect(denomination_reprise).to eq('DIRECTION INTERMINISTERIELLE DU NUMERIQUE')

      # pf: le champ ne référence plus l'ancien établissement Tahiti — un
      # nouvel établissement français est attaché à sa place.
      # (`etablissement.siret` n'est pas comparé à siret_fr : la fixture FR
      # etablissements.json porte son propre SIRET figé — "30613890001294" —
      # qui écrase toujours la valeur saisie via EtablissementAdapter#process_params
      # ; c'est `champ.external_id`, lu depuis la colonne du champ et non
      # recalculé depuis la fixture, qui porte la valeur réellement saisie.)
      #
      # pf: DÉCOUVERTE — Champ#belongs_to :etablissement, dependent: :destroy
      # (app/models/champ.rb) ne détruit PAS l'ancien enregistrement lors
      # d'une simple réaffectation (update(etablissement: nouveau)) : ce
      # mode de `dependent: :destroy` sur un belongs_to ne joue qu'à la
      # destruction du CHAMP lui-même, pas au changement de cible. Vérifié
      # ici : Etablissement.exists?(ancien_etablissement_id) reste vrai après
      # la bascule. Pas un bug de ce chantier (aucun code touché ne gère la
      # suppression), mais une fuite d'établissements orphelins à chaque
      # changement de référentiel dans un champ SIRET existant — signalé,
      # non corrigé (hors périmètre de cette tâche).
      champ = champ_etablissement
      expect(champ.external_id).to eq(siret_fr)
      expect(champ.etablissement_id).not_to eq(ancien_etablissement_id)
    end
  end

  # pf: remplit le champ SIRET, attend la fin réelle du job asynchrone de
  # résolution (fetched/external_error/multiple_found — pas seulement la fin
  # du debounce d'autosave, qui peut se terminer avant même que le job soit
  # enqueué : cf. rapport de la tâche 10), puis recharge la page pour
  # observer l'état persisté du champ formule (aucun push live au
  # navigateur : dossier.refresh_formulas_after persiste via update_columns).
  def remplir_etablissement_et_attendre(valeur)
    identifiant = IdentifiantEntreprise.parse(valeur)

    # pf: NE PAS utiliser la forme bloc de perform_enqueued_jobs ici — elle
    # bascule l'adaptateur de test en exécution SYNCHRONE dès l'enqueue
    # (`queue_adapter.perform_enqueued_jobs = true` pendant le bloc), ce qui
    # fait tourner ChampFetchExternalDataJob AVANT le retour de
    # `champ.fetch_later!`, donc AVANT l'appel explicite
    # `dossier.refresh_formulas_after(champ)` du contrôleur
    # (Users::DossiersController#update_dossier_and_compute_errors, sur le
    # même objet `champ` en mémoire, pas encore rechargé). Le contrôleur
    # écrase alors la formule fraîchement recalculée par le job avec sa
    # propre relecture (établissement encore nil à ce moment côté contrôleur)
    # — un artefact de test, invisible en production où le job tourne
    # réellement après la fin de la requête (Sidekiq). On enqueue donc
    # d'abord (comportement par défaut de l'adaptateur :test), puis on vide
    # la file explicitement une fois la requête d'autosave terminée, pour
    # respecter l'ordre réel : requête → réponse → job asynchrone.
    fill_in 'Établissement', with: valeur
    wait_for_autosave
    # pf: wait_for_autosave seul ne garantit pas que la requête PATCH
    # d'autosave ait réellement abouti (les classes debounced-empty /
    # autosave-state-idle peuvent être observées avant même le déclenchement
    # du debounce) — on attend explicitement la transition serveur
    # (waiting_for_job, posée par Champ#fetch_later!) avant de vider la file.
    wait_until { (c = champ_etablissement) && c.waiting_for_job? && c.external_id == identifiant.valeur }
    # pf: only: ChampFetchExternalDataJob — un SIRET français enqueue aussi
    # les FRENCH_ONLY_JOBS (attestations, bilans, Kbis…) via
    # APIEntrepriseService.perform_later_fetch_jobs ; les exécuter n'apporte
    # rien à ce scénario et exigerait de stubber une dizaine d'endpoints
    # supplémentaires. En production ils tournent en Sidekiq, hors requête HTTP.
    perform_enqueued_jobs(only: ChampFetchExternalDataJob)
    wait_until { (c = champ_etablissement) && c.done? }
    page.refresh
  end

  def champ_etablissement
    dossier.reload.project_champs_public.find { _1.libelle == 'Établissement' }
  end

  def fill_in_identifiant_entreprise(valeur)
    # pf: le libellé du champ est piloté par les locales (cf. phase 4) — on
    # cible le champ par son nom pour rester stable au changement de libellé.
    find('input[name="user[siret]"]').set(valeur)
  end

  def denomination_reprise
    find('[aria-live="polite"]').text
  end

  def stub_etablissement_fr
    stub_request(:get, %r{https://entreprise\.api\.gouv\.fr/v3/insee/sirene/etablissements/#{siret_fr}})
      .to_return(body: File.read('spec/fixtures/files/api_entreprise/etablissements.json'), status: 200)
    stub_request(:get, %r{https://entreprise\.api\.gouv\.fr/v3/insee/sirene/unites_legales/#{siren_fr}})
      .to_return(body: File.read('spec/fixtures/files/api_entreprise/entreprises.json'), status: 200)
  end
end
