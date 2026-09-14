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

    describe 'tdc referentiel_de_polynesie — filtre contextuel' do
      let(:referentiel) { create(:baserow_referentiel) }
      let(:procedure) do
        create(:procedure, types_de_champ_public: [
          { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
          { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
        ])
      end
      let(:coordinate) { procedure.draft_revision.revision_types_de_champ_public.second }
      let(:fields) do
        {
          1 => { name: 'Nom', type: 'text', select_options: [] },
          12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }] },
          20 => { name: 'Fichier', type: 'file', select_options: [] },
        }
      end
      # pf: le `before` du describe 'render' englobant (ligne 15) appelle déjà render_inline
      # AVANT que le `before` de ce bloc ne s'exécute (RSpec exécute les hooks outer -> inner).
      # Ce premier rendu déclenche InfoReferentielComponent#ready? -> BaserowAPI.config (HTTP réel)
      # puis, une fois la liste A branchée, ReferentielDePolynesie::API.table_fields (HTTP réel
      # aussi, table_id '24' étant configuré via .env). On pose donc les doubles dans ce `let`,
      # exécuté à la première évaluation de `component` (donc avant tout rendu), plutôt que dans
      # un `before` qui arriverait trop tard.
      let(:component) do
        allow_any_instance_of(Referentiels::BaserowReferentiel).to receive(:ready?).and_return(true)
        allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields)
        described_class.new(coordinate:, upper_coordinates: coordinate.upper_coordinates)
      end

      it 'affiche la case décochée et les listes masquées par défaut' do
        render_inline(component)
        expect(page).to have_unchecked_field('Restreindre les lignes proposées selon un autre champ du formulaire')
        expect(page).to have_css('[data-hide-target-target="toHide"].fr-hidden')
        expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Nom', 'Catégorie'])
        expect(page).not_to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Fichier'])
        expect(page).to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', with_options: ['Type de produit'])
      end

      it 'affiche la case cochée et les listes visibles quand un filtre est configuré' do
        coordinate.type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{procedure.draft_revision.types_de_champ_public.first.stable_id}" })
        render_inline(component)
        expect(page).to have_checked_field('Restreindre les lignes proposées selon un autre champ du formulaire')
        expect(page).to have_css('[data-hide-target-target="toHide"]:not(.fr-hidden)')
        expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
      end

      it 'garde la colonne en cache et prévient quand Baserow est injoignable' do
        allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(nil)
        coordinate.type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/1' })
        # pf: composant frais — `component` a déjà été rendu (une fois) par le `before` du describe
        # 'render' englobant, avant que ce `it` ne pose le double `table_fields: nil` ; réutiliser
        # cette instance servirait sa liste A mémoïsée (@referentiel_filter_baserow_options) de la
        # première fois plutôt que de refléter le nouveau double.
        render_inline(described_class.new(coordinate:, upper_coordinates: coordinate.upper_coordinates))
        expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
        expect(page).to have_text('Colonnes indisponibles pour le moment')
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
end
