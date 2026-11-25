# frozen_string_literal: true

describe 'instructeurs/procedures/_email_preferences', type: :view do
  let(:procedure) { create(:procedure) }
  let(:instructeur) { create(:instructeur) }
  let(:instructeur_procedure) { create(:instructeurs_procedure, instructeur:, procedure:) }

  subject do
    render('instructeurs/procedures/email_preferences', procedure:, instructeur_procedure:)
  end

  # pf: garde-fou — chaque préférence e-mail doit avoir un toggle dans la vue, y compris le flag PF
  # deletion_email_notifications_enabled (déjà perdu une fois lors d'un refactor upstream de la vue).
  it 'renders a toggle for every email preference' do
    [
      :instant_email_new_dossier, :instant_email_new_message, :instant_email_new_expert_avis,
      :daily_email_summary, :weekly_email_summary, :deletion_email_notifications_enabled,
    ].each do |setting|
      expect(subject).to have_selector(
        "input[type=\"checkbox\"][name=\"instructeurs_procedure[#{setting}]\"]",
        visible: :all
      ), "expected a toggle for #{setting} in _email_preferences.html.haml"
    end
  end
end
