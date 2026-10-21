# frozen_string_literal: true

describe TypesDeChampEditor::ChampComponent, type: :component do
  describe 'render' do
    let(:component) { described_class.new(coordinate:, upper_coordinates: []) }
    let(:routing_rules_stable_ids) { [] }
    let(:ineligibilite_rules_used?) { false }

    before do
      Flipper.enable_actor(:engagement_juridique_type_de_champ, procedure)
      allow_any_instance_of(Procedure).to receive(:stable_ids_used_by_routing_rules).and_return(routing_rules_stable_ids)
      # pf visa & tefenua champs are activated via Flipper which requires current_user which is not active in these tests
      allow_any_instance_of(TypesDeChampEditor::ChampComponent).to receive(:filter_featured_type_champ).and_return(true)
      allow_any_instance_of(ProcedureRevisionTypeDeChamp).to receive(:used_by_ineligibilite_rules?).and_return(ineligibilite_rules_used?)
      render_inline(component)
    end

    describe 'tdc dropdown' do
      let(:procedure) { create(:procedure, types_de_champ_public:) }
      let(:types_de_champ_public) { [{ type: :drop_down_list, libelle: 'Votre ville', options: ['Paris', 'Lyon', 'Marseille'] }] }
      let(:tdc) { procedure.draft_revision.types_de_champ.first }
      let(:coordinate) { procedure.draft_revision.coordinate_for(tdc) }

      context 'drop down tdc not used for routing' do
        it do
          expect(page).not_to have_text(/utilisé pour\nle routage/)
          expect(page).not_to have_css("select[disabled=\"disabled\"]")
        end
      end

      context 'drop down tdc used for routing' do
        let(:routing_rules_stable_ids) { [tdc.stable_id] }

        it do
          expect(page).to have_css("select[disabled=\"disabled\"]")
          expect(page).to have_text(/utilisé pour\nle routage/)
        end
      end

      context 'drop down tdc used for ineligibilite_rules' do
        let(:ineligibilite_rules_used?) { true }

        it do
          expect(page).to have_css("select[disabled=\"disabled\"]")
          expect(page).to have_text(/l’eligibilité des dossiers/)
        end
      end

      context 'tdc used for prefill' do
        let(:types_de_champ_public) do
          [
            {
              type: :referentiel,
              stable_id: 1,
              referentiel: create(:api_referentiel, :exact_match, :with_exact_match_response),
              referentiel_mapping: {
                '$.jsonpath' => {
                  'prefill' => '1',
                  'type' => 'drop_down_list',
                  'prefill_stable_id' => 2,
                },
              },
            },
            { type: :drop_down_list, stable_id: 2, libelle: 'Votre ville', options: ['Paris', 'Lyon'] },
          ]
        end
        let(:coordinate) { procedure.draft_revision.coordinate_and_tdc(2).first }
        it do
          expect(page).to have_text(/Champ prérempli/)
        end
      end
    end

    describe 'tdc ej' do
      let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :text }], types_de_champ_private: [{ type: :text }]) }

      context 'when coordinate public' do
        let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.first }

        it 'does not include Engagement Juridique' do
          expect(page).not_to have_css('option', text: "Engagement Juridique")
        end
      end

      context 'when coordinate private' do
        let(:coordinate) { procedure.draft_revision.revision_types_de_champ_private.first }

        it 'includes Engagement Juridique' do
          expect(page).to have_css('option', text: "Engagement Juridique")
        end
      end
    end

    describe 'tdc explication' do
      let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :explication }]) }
      let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.first }
      it 'includes an uploader for notice_explicative' do
        expect(page).to have_css('label', text: 'Notice explicative')
        expect(page).to have_css('input[type=file]')
      end
    end

    describe 'select champ position' do
      let(:tdc) { procedure.draft_revision.types_de_champ.first }
      let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.first }
      let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :text, libelle: 'a' }]) }
      it 'does not have select to move champs' do
        expect(page).to have_css("select##{ActionView::RecordIdentifier.dom_id(coordinate, :move_and_morph)}")
      end
    end

    describe 'tdc formule' do
      let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :formule, libelle: 'Calcul TVA', formule_expression: '{Prix HT} * 1.20' }]) }
      let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.first }

      it 'displays formula expression field when champ type is formule' do
        expect(page).to have_field('Expression de la formule', type: 'textarea', with: '{Prix HT} * 1.20')
      end

      it 'shows the AI helper banner' do
        expect(page).to have_text('Besoin d’aide pour écrire cette formule ?')
        expect(page).to have_button('Préparer la demande pour une IA')
        expect(page).to have_link('Voir la documentation')
      end

      it 'has proper HTML attributes for accessibility' do
        expect(page).to have_css('textarea[rows="3"]')
        expect(page).to have_css('textarea.fr-input')
        expect(page).to have_css('textarea[placeholder*="Montant HT"]')
      end
    end
  end

  describe 'formule feature flag' do
    it 'has formule in FEATURE_FLAGS' do
      expect(TypeDeChamp::FEATURE_FLAGS[:formule]).to eq(:formule)
    end
  end

  # pf: la liste de colonnes alimente l'autocomplete de l'éditeur formule.
  # Pour l'agrégat sur bloc répétable, on expose le bloc + des sous-chemins
  # composites "Bloc/Sous-champ" (slash), et on RETIRE les sous-champs-ligne
  # "Bloc – Sous-champ" (tiret) hors du bloc (inutiles, source de confusion).
  describe '#available_columns_for_formula avec bloc répétable' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        {
          type: :repetition, libelle: 'Facture', children: [
            { type: :integer_number, libelle: 'Prix HT' },
          ],
        },
        { type: :formule, libelle: 'Total' },
      ])
    end
    let(:formule_tdc) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Total' } }
    let(:coordinate) { procedure.draft_revision.coordinate_for(formule_tdc) }
    let(:component) { described_class.new(coordinate:, upper_coordinates: []) }
    let(:columns) { component.available_columns_for_formula }

    it 'expose le bloc comme colonne agrégable' do
      bloc = columns.find { _1[:label] == 'Facture' }
      expect(bloc).to be_present
      expect(bloc[:id]).to match(/\Atdc\d+\z/)
    end

    it 'expose le sous-champ en label composite "Facture/Prix HT" (slash)' do
      bloc = columns.find { _1[:label] == 'Facture' }
      sub = bloc[:paths].find { _1[:label] == 'Facture/Prix HT' }
      expect(sub).to be_present
      expect(sub[:path]).to match(/\Asub_\d+\z/)
    end

    it 'ne propose PAS la référence-ligne "Facture – Prix HT" (tiret) hors du bloc' do
      labels = columns.map { _1[:label] }
      expect(labels).not_to include(a_string_matching(/Facture – Prix HT|Facture - Prix HT/))
    end
  end

  # pf: une annotation privée peut agréger tout bloc public, quelle que soit sa
  # position (positions publiques et privées numérotées séparément).
  describe '#available_columns_for_formula pour une annotation privée et un bloc public' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :text, libelle: 'Nom' },
        { type: :repetition, libelle: 'Certificats', children: [{ type: :integer_number, libelle: 'Nombre de colis' }] },
      ], types_de_champ_private: [
        { type: :formule, libelle: 'Total des colis' },
      ])
    end
    let(:formule_tdc) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Total des colis' } }
    let(:coordinate) { procedure.draft_revision.coordinate_for(formule_tdc) }
    let(:component) { described_class.new(coordinate:, upper_coordinates: []) }

    it 'expose le sous-champ "Certificats/Nombre de colis"' do
      bloc = component.available_columns_for_formula.find { _1[:label] == 'Certificats' }
      expect(bloc[:paths].map { _1[:label] }).to include('Certificats/Nombre de colis')
    end
  end

  # pf: seules les colonnes système de la liste blanche (scalaires stables)
  # sont proposées, avec l'identifiant que le resolver sait résoudre.
  describe '#available_columns_for_formula avec colonnes système' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :formule, libelle: 'Total' }]) }
    let(:formule_tdc) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Total' } }
    let(:coordinate) { procedure.draft_revision.coordinate_for(formule_tdc) }
    let(:component) { described_class.new(coordinate:, upper_coordinates: []) }
    let(:columns) { component.available_columns_for_formula }
    let(:ids) { columns.map { _1[:id] } }

    it 'propose la date de création sous l’identifiant self_created_at' do
      expect(columns).to include(a_hash_including(id: 'self_created_at', label: 'Date de création'))
    end

    it 'conserve les identifiants historiques' do
      expect(ids).to include('dossier_number', 'dossier_depose_at')
    end

    it 'propose la date de passage en construction (recalculée à la transition)' do
      expect(ids).to include('dossier_en_construction_at')
    end

    it 'ne propose pas les colonnes d’instruction ni les dates mouvantes' do
      expect(ids).not_to include('followers_instructeurs_email', 'groupe_instructeur_id', 'dossier_labels_label_id', 'self_updated_at', 'self_last_champ_updated_at', 'self_expired_at', 'self_archived', 'self_motivation')
    end

    it 'n’expose aucune colonne sans identifiant' do
      expect(columns).to all(include(:id))
    end

    it 'n’expose que des identifiants résolubles' do
      resolver = FormulaColumnResolver.new(procedure.draft_revision)
      ids.each { |id| expect(resolver.resolve(id)).not_to be_nil, "#{id} non résolu" }
    end
  end

  describe 'ACCEPTED_TYPES' do
    it 'contains expected conversions' do
      expect(described_class::ACCEPTED_TYPES).to include(
        "checkbox" => ["yes_no", "text", "textarea", "formatted"],
        "civilite" => ["text", "textarea", "formatted"],
        "date" => ["datetime", "text", "textarea", "formatted"],
        "datetime" => ["date", "text", "textarea", "formatted"],
        "decimal_number" => ["integer_number", "text", "textarea", "formatted"],
        "drop_down_list" => ["multiple_drop_down_list", "text", "textarea", "formatted"],
        "email" => ["text", "textarea", "formatted"],
        "formatted" => ["textarea", "text", "email", "phone"],
        "integer_number" => ["decimal_number", "text", "textarea", "formatted"],
        "multiple_drop_down_list" => ["drop_down_list", "text", "textarea", "formatted"],
        "phone" => ["text", "textarea", "formatted"],
        "text" => ["textarea", "formatted", "email", "phone", "decimal_number", "integer_number"],
        "textarea" => ["text", "formatted"],
        "yes_no" => ["checkbox", "text", "textarea", "formatted"]
      )
    end
  end

  describe 'hide old titre_identite in creation list' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :text }]) }
    let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.first }
    let(:component) { described_class.new(coordinate:, upper_coordinates: []) }

    it 'does not list Titre identité' do
      render_inline(component)
      expect(page).not_to have_css('option', text: 'Titre identité')
    end
  end

  # pf: la liste des modèles Lexpol est commune à tous les admins de la démarche :
  # elle est lue avec le compte de service du numéro Tahiti du service, et non plus
  # réservée aux super admins.
  describe 'sélection du modèle Lexpol' do
    let(:procedure) { create(:procedure, :with_service, types_de_champ_public: [{ type: :lexpol, libelle: 'Arrêté' }]) }
    let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.first }
    let(:component) { described_class.new(coordinate:, upper_coordinates: []) }
    let(:user) { create(:user, email: 'admin@mes-demarches.gov.pf') }
    let(:numero_tahiti) { '003970' }
    let(:service_emails) { { numero_tahiti => 'redacteur.geda@service.gov.pf' } }
    let(:api_lexpol) { instance_double(APILexpol) }

    before do
      procedure.service.update_column(:siret, numero_tahiti)
      allow(APILexpol).to receive(:service_emails).and_return(service_emails)
      allow_any_instance_of(described_class).to receive(:filter_featured_type_champ).and_return(true)
      allow_any_instance_of(described_class).to receive(:current_user).and_return(user)
      allow_any_instance_of(described_class).to receive(:current_super_admin).and_return(nil)
    end

    context 'quand un compte de service est configuré pour le numéro Tahiti' do
      before do
        allow(APILexpol).to receive(:new).with(user.email, numero_tahiti, true).and_return(api_lexpol)
        allow(api_lexpol).to receive(:get_models).and_return([['Arrêté de subvention', 'M42']])
      end

      it 'liste les modèles du compte de service pour un admin non super admin' do
        render_inline(component)
        expect(page).to have_css('option[value="M42"]', text: 'Arrêté de subvention')
      end
    end

    context 'quand le modèle configuré n’est pas visible du compte de service' do
      before do
        coordinate.type_de_champ.update!(lexpol_modele: 'M99')
        allow(APILexpol).to receive(:new).with(user.email, numero_tahiti, true).and_return(api_lexpol)
        allow(api_lexpol).to receive(:get_models).and_return([['Arrêté de subvention', 'M42']])
      end

      it 'conserve le modèle sélectionné pour que l’autosave ne l’efface pas, et prévient' do
        render_inline(component)
        expect(page).to have_css('select[name$="[lexpol_modele]"] option[selected][value="M99"]', text: 'Modèle M99 (non accessible)')
        expect(page).to have_css('option[value="M42"]', text: 'Arrêté de subvention')
        expect(page).to have_text('Le modèle M99 n’est pas accessible avec le compte de service (redacteur.geda@service.gov.pf)')
        expect(page).to have_text('Les dossiers de test échoueront')
      end
    end

    context 'quand le modèle configuré est dans la liste' do
      before do
        coordinate.type_de_champ.update!(lexpol_modele: 'M42')
        allow(APILexpol).to receive(:new).and_return(api_lexpol)
        allow(api_lexpol).to receive(:get_models).and_return([['Arrêté de subvention', 'M42']])
      end

      it 'le sélectionne sans avertissement' do
        render_inline(component)
        expect(page).to have_css('option[selected][value="M42"]', text: 'Arrêté de subvention')
        expect(page).not_to have_text('non accessible')
      end
    end

    context 'quand aucun compte de service n’est configuré' do
      let(:service_emails) { {} }

      before do
        allow(APILexpol).to receive(:new).with(user.email, numero_tahiti, false).and_return(api_lexpol)
        allow(api_lexpol).to receive(:get_models).and_return([['Mon modèle', 'M7']])
      end

      it 'utilise le compte personnel de l’admin' do
        render_inline(component)
        expect(page).to have_css('option[value="M7"]', text: 'Mon modèle')
      end
    end

    context 'quand l’accès est refusé au compte de service' do
      before do
        allow(APILexpol).to receive(:new).and_return(api_lexpol)
        allow(api_lexpol).to receive(:get_models).and_raise(APILexpol::LexpolAccessDenied.new('redacteur.geda@service.gov.pf', 403))
      end

      it 'nomme le compte de service à chaque rendu (le refus n’est pas mis en cache)', :caching do
        2.times do
          render_inline(described_class.new(coordinate:, upper_coordinates: []))
          expect(page).to have_text('Aucun modèle Lexpol n’est accessible avec le compte de service (redacteur.geda@service.gov.pf)')
          expect(page).to have_text('déclarez ce compte de service sur les modèles')
          expect(page).not_to have_text('Erreur lors de la récupération des modèles Lexpol')
        end
      end

      context 'avec un modèle déjà configuré' do
        before { coordinate.type_de_champ.update!(lexpol_modele: 'M42') }

        it 'affiche le modèle en lecture seule et le conserve' do
          render_inline(component)
          expect(page).to have_text(/Modèle configuré :\s+M42/)
          expect(page).to have_css('input[type=hidden][name$="[lexpol_modele]"][value="M42"]', visible: false)
          expect(page).not_to have_css('select[name$="[lexpol_modele]"]')
        end
      end
    end

    context 'quand le compte de service ne voit aucun modèle' do
      before do
        allow(APILexpol).to receive(:new).and_return(api_lexpol)
        allow(api_lexpol).to receive(:get_models).and_return([])
      end

      it 'invite à déclarer le compte de service plutôt qu’afficher une erreur technique' do
        render_inline(component)
        expect(page).to have_text('Aucun modèle Lexpol n’est accessible avec le compte de service (redacteur.geda@service.gov.pf)')
        expect(page).not_to have_text('Erreur lors de la récupération des modèles Lexpol')
      end
    end

    context 'quand Lexpol est indisponible' do
      before do
        allow(APILexpol).to receive(:new).and_return(api_lexpol)
        allow(api_lexpol).to receive(:get_models).and_raise(StandardError, 'timeout')
      end

      it 'affiche l’erreur technique' do
        render_inline(component)
        expect(page).to have_text('Erreur lors de la récupération des modèles Lexpol')
        expect(page).to have_text('timeout')
      end
    end
  end
end
