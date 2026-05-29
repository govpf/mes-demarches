# frozen_string_literal: true

describe 'instructeurs/procedures/_email_preferences', type: :view do
  let(:procedure) { create(:procedure) }
  let(:instructeur) { create(:instructeur) }
  let(:assign_to) { create(:assign_to, instructeur: instructeur, groupe_instructeur: procedure.defaut_groupe_instructeur) }

  subject do
    render('instructeurs/procedures/email_preferences', procedure: procedure, assign_to: assign_to)
  end

  # pf: garde-fou contre la régression UI du flag PF deletion_email_notifications_enabled
  # (backend câblé en migration 20250930, toggle resté absent de la vue après le refactor radio→toggle).
  it 'renders a toggle for deletion_email_notifications_enabled' do
    expect(subject).to have_selector('input[type="checkbox"][name="assign_to[deletion_email_notifications_enabled]"]', visible: :all)
  end

  # Garde-fou générique : tout flag listé dans NOTIFICATION_SETTINGS doit avoir un toggle dans la vue.
  it 'renders a toggle for every flag in Instructeur::NOTIFICATION_SETTINGS' do
    Instructeur::NOTIFICATION_SETTINGS.each do |setting|
      expect(subject).to have_selector(
        "input[type=\"checkbox\"][name=\"assign_to[#{setting}]\"]",
        visible: :all
      ), "expected a toggle for #{setting} in _email_preferences.html.haml"
    end
  end
end
