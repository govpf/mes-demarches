# frozen_string_literal: true

describe EditableChamp::ReferentielComponent, type: :component do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :referentiel }]) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:tdc) { procedure.active_revision.types_de_champ.first }
  let(:champ) { dossier.champs.first }

  subject do
    component = nil
    ActionView::Base.empty.form_for(champ, url: '/') do |form|
      component = EditableChamp::EditableChampComponent.new(champ:, form:)
    end
    render_inline(component)
  end

  # Régression MES-DEMARCHES-36W : à l'aperçu d'une procédure dont le champ
  # référentiel n'est pas encore configuré, type_de_champ.referentiel est nil.
  # Le composant tombait dans la branche `else` et appelait referentiel.id → 500.
  context 'when the referentiel is not configured (referentiel is nil)' do
    it 'does not raise and renders no autocomplete' do
      expect(tdc.referentiel).to be_nil

      expect { subject }.not_to raise_error
      expect(page).to have_no_css('react-component')
    end
  end
end
