describe 'instructeurs/procedures/_header.html.haml', type: :view do
  let(:procedure) { create(:procedure, id: 1, procedure_expires_when_termine_enabled: expiration_enabled)}

  subject do
    render('instructeurs/procedures/header.html.haml',
            procedure: procedure,
            statut: 'tous',
            a_suivre_count: 0,
            suivis_count: 0,
            traites_count: 0,
            tous_count: 0,
            archives_count: 0,
            expirant_count: 0,
            has_en_cours_notifications: false,
            has_termine_notifications: false,
            current_instructeur: build_stubbed(:instructeur))
  end

  context 'when procedure_expires_when_termine_enabled is true' do
    let(:expiration_enabled) { true }
    it 'contains link to expiring dossiers within procedure' do
      expect(subject).to have_selector(%Q(a[href="#{instructeur_procedure_path(procedure, statut: 'expirant')}"]), count: 1)
    end
  end

  context 'when procedure_expires_when_termine_enabled is false' do
    let(:expiration_enabled) { false }
    it 'does not contain link to expiring dossiers within procedure' do
      expect(subject).to have_selector(%Q(a[href="#{instructeur_procedure_path(procedure, statut: 'expirant')}"]), count: 0)
    end
  end
end
