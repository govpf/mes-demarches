# frozen_string_literal: true

describe 'instructeurs/procedures/_email_preferences', type: :view do
  let(:procedure) { create(:procedure) }
  let(:instructeur) { create(:instructeur) }
  let(:assign_to) { create(:assign_to, instructeur: instructeur, groupe_instructeur: procedure.defaut_groupe_instructeur) }
  let(:instructeur_procedure) { create(:instructeurs_procedure, instructeur:, procedure:) }

  subject do
    render('instructeurs/procedures/email_preferences', procedure:, instructeur_procedure:, assign_to:)
  end

  # pf: garde-fou contre la régression UI du flag PF deletion_email_notifications_enabled
  # (backend câblé en migration 20250930, flag resté sur assign_tos après le transfert upstream
  # des autres préférences vers instructeurs_procedures).
  it 'renders a toggle for deletion_email_notifications_enabled' do
    expect(subject).to have_selector('input[type="checkbox"][name="assign_to[deletion_email_notifications_enabled]"]', visible: :all)
  end

  # Garde-fou générique : chaque préférence e-mail d'instructeurs_procedures doit avoir un toggle dans la vue.
  it 'renders a toggle for every email preference of instructeurs_procedures' do
    [:instant_email_new_dossier, :instant_email_new_message, :instant_email_new_expert_avis, :daily_email_summary, :weekly_email_summary].each do |setting|
      expect(subject).to have_selector(
        "input[type=\"checkbox\"][name=\"instructeurs_procedure[#{setting}]\"]",
        visible: :all
      ), "expected a toggle for #{setting} in _email_preferences.html.haml"
    end
  end
end
