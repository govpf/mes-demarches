# frozen_string_literal: true

describe EditableChamp::ReferentielDePolynesieComponent, type: :component do
  let(:referentiel) { create(:baserow_referentiel) }
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, mandatory: false },
    ])
  end
  let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
  let(:rdp_tdc) { procedure.draft_revision.types_de_champ_public.second }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.project_champ(rdp_tdc) }
  let(:component) { build_component(champ) }

  # pf: react_props appelle des helpers d'URL (data_sources_rdp_search_path) qui exigent
  # que le composant ait déjà traversé le pipeline de rendu ViewComponent (#controller
  # lève sinon ControllerCalledBeforeRenderError) ; on rend une première fois avant
  # d'inspecter react_props directement sur l'instance.
  def build_component(champ)
    result = nil
    ActionView::Base.empty.form_for(champ, url: '/') do |form|
      result = described_class.new(form:, champ:)
    end
    render_inline(result)
    result
  end

  before { allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).and_return(nil) }

  context 'sans filtre contextuel' do
    # pf: cascade rempart n°1 — stable_id part même sans filtre : le serveur l'exige dès
    # qu'un dossier_id accompagne la recherche.
    it 'garde le comportement catalogue (saisie de 2 caractères) mais transmet stable_id' do
      props = component.react_props
      expect(props[:minimumInputLength]).to eq(2)
      expect(props[:loader]).to include("stable_id=#{rdp_tdc.stable_id}")
      expect(props[:loader]).not_to include('pilot_version')
      expect(props).not_to have_key(:emptyLabel)
    end
  end

  context 'avec filtre contextuel' do
    before do
      rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
      dossier.reload
    end

    it 'transmet stable_id au loader, liste au focus, ne masque jamais le champ' do
      props = component.react_props
      expect(props[:loader]).to include("stable_id=#{rdp_tdc.stable_id}")
      expect(props[:loader]).not_to include('row_id')
      expect(props[:minimumInputLength]).to eq(0)
      expect(props[:hideWhenEmpty]).to be_nil
    end

    # pf: cascade — l'URL du loader doit changer avec la valeur du pilote (cache-buster) pour
    # que la liste React se recharge après un re-rendu Turbo, sans jamais exposer la valeur.
    it 'fait varier pilot_version avec la valeur du pilote, sans l’exposer' do
      blank_loader = component.react_props[:loader]
      expect(blank_loader).to include('pilot_version=0')

      dossier.project_champ(pilot_tdc).update!(value: 'Plants')
      dossier.reload
      filled_loader = build_component(dossier.project_champ(rdp_tdc)).react_props[:loader]

      expect(filled_loader).to include('pilot_version=')
      expect(filled_loader).not_to include('Plants')
      expect(filled_loader).not_to eq(blank_loader)
    end

    it 'affiche « Renseignez d’abord » quand le pilote est vide' do
      expect(component.react_props[:emptyLabel]).to eq('Renseignez d’abord « Type de produit »')
    end

    it 'affiche « Aucun résultat pour » quand le pilote est renseigné' do
      dossier.project_champ(pilot_tdc).update!(value: 'Plants')
      dossier.reload
      expect(build_component(dossier.project_champ(rdp_tdc)).react_props[:emptyLabel]).to eq('Aucun résultat pour « Plants »')
    end
  end
end
