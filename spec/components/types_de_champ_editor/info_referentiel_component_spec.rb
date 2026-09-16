# frozen_string_literal: true

describe TypesDeChampEditor::InfoReferentielComponent, type: :component do
  describe 'render' do
    let(:component) { described_class.new(procedure:, type_de_champ:) }
    let(:types_de_champ_public) { [{ type: :referentiel }] }
    let(:type_de_champ) { procedure.draft_revision.types_de_champ_public.first }

    before do
      referentiel
      type_de_champ
      render_inline(component)
    end

    context "draft_procedure" do
      let(:procedure) { create(:procedure, types_de_champ_public:) }
      context 'having referentiel' do
        let(:referentiel) { create(:api_referentiel, :exact_match, types_de_champ: [type_de_champ]) }

        it "allows to edit referentiel" do
          expect(page).to have_link("Configurer le champ", href: Rails.application.routes.url_helpers.edit_admin_procedure_referentiel_path(procedure, type_de_champ.stable_id, referentiel.id))
        end
      end
      context 'not having referentiel' do
        let(:referentiel) { nil }

        it "new referentiel" do
          expect(page).to have_link("Configurer le champ", href: Rails.application.routes.url_helpers.new_admin_procedure_referentiel_path(procedure, type_de_champ.stable_id))
        end
      end
    end

    context "published_procedure" do
      let(:procedure) { create(:procedure, :published, types_de_champ_public:) }

      context "having referentiel" do
        let(:referentiel) { create(:api_referentiel, :exact_match, types_de_champ: [type_de_champ]) }

        it "does not allow to edit existing referentiel" do
          expect(page).to have_link("Configurer le champ", href: Rails.application.routes.url_helpers.new_admin_procedure_referentiel_path(procedure, type_de_champ.stable_id, referentiel_id: referentiel.id))
        end
      end

      context 'not having referentiel' do
        let(:referentiel) { nil }

        it "new referentiel" do
          expect(page).to have_link("Configurer le champ", href: Rails.application.routes.url_helpers.new_admin_procedure_referentiel_path(procedure, type_de_champ.stable_id))
        end
      end
    end
  end

  # pf: cascade — la carte du champ ne garde qu’un rappel en lecture seule du filtre contextuel,
  # configuré dans le wizard « Configurer le champ » : aucun appel Baserow ne doit partir d’ici.
  describe 'rappel du filtre contextuel' do
    let(:referentiel) { create(:baserow_referentiel) } # baserow://24
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
        { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
      ])
    end
    let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:type_de_champ) { procedure.draft_revision.types_de_champ_public.second }
    let(:component) { described_class.new(procedure:, type_de_champ:) }

    # pf: ready? interroge la table méta Baserow (hors périmètre du filtre) — on le neutralise
    before { allow_any_instance_of(Referentiels::BaserowReferentiel).to receive(:ready?).and_return(true) }

    context 'sans filtre configuré' do
      it 'n’affiche aucun rappel' do
        render_inline(component)
        expect(page).not_to have_text('Lignes restreintes')
      end
    end

    context 'avec un filtre configuré' do
      before do
        type_de_champ.update!(referentiel_filter: {
          'baserow_field_id' => 12,
          'baserow_field_name' => 'Catégorie',
          'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}",
        })
      end

      it 'affiche le rappel sans interroger Baserow' do
        expect(ReferentielDePolynesie::API).not_to receive(:table_fields)
        render_inline(component)
        expect(page).to have_text('Lignes restreintes selon « Type de produit » (colonne « Catégorie »)')
      end
    end

    context 'quand le champ pilote a disparu' do
      before do
        type_de_champ.update!(referentiel_filter: {
          'baserow_field_id' => 12,
          'baserow_field_name' => 'Catégorie',
          'pilot_column_id' => 'type_de_champ/999999',
        })
      end

      it 'se replie sur l’identifiant de la colonne' do
        render_inline(component)
        expect(page).to have_text('Lignes restreintes selon « type_de_champ/999999 » (colonne « Catégorie »)')
      end
    end
  end
end
