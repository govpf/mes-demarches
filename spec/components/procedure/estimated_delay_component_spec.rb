# frozen_string_literal: true

describe Procedure::EstimatedDelayComponent, type: :component do
  subject { render_inline(described_class.new(procedure:)) }

  let(:procedure) { create(:procedure, :published) }

  before do
    allow(procedure).to receive(:stats_usual_traitement_time).and_return(traitement_times)
  end

  # pf: non-régression du décalage de libellés causé par le .uniq (cf. composant).
  # Les trois durées sont croissantes par construction, chaque palier doit porter
  # son propre libellé.
  context 'when the three durations differ' do
    let(:traitement_times) { [8.days, 1.month, 2.months] }

    it 'renders one line per group, each with its own label' do
      expect(subject).to have_text('Les dossiers les plus rapides sont traités en 8 jours')
      expect(subject).to have_text('Les dossiers dans la moyenne sont traités en environ un mois')
      expect(subject).to have_text('Les dossiers les plus longs sont traités en 2 mois')
    end
  end

  context 'when the two fastest groups round to the same duration' do
    let(:traitement_times) { [1.month, 1.month, 2.months] }

    it 'still attributes the longest duration to the slowest group' do
      expect(subject).to have_text('Les dossiers les plus rapides sont traités en environ un mois')
      expect(subject).to have_text('Les dossiers dans la moyenne sont traités en environ un mois')
      expect(subject).to have_text('Les dossiers les plus longs sont traités en 2 mois')
    end

    it 'does not present the longest duration as a mid-range one' do
      expect(subject).not_to have_text('Les dossiers dans la moyenne sont traités en 2 mois')
    end
  end

  context 'when the two slowest groups round to the same duration' do
    let(:traitement_times) { [8.days, 1.month, 1.month] }

    it 'keeps the slowest group visible' do
      expect(subject).to have_text('Les dossiers les plus rapides sont traités en 8 jours')
      expect(subject).to have_text('Les dossiers dans la moyenne sont traités en environ un mois')
      expect(subject).to have_text('Les dossiers les plus longs sont traités en environ un mois')
    end
  end

  context 'when the three durations round to the same duration' do
    let(:traitement_times) { [1.month, 1.month, 1.month] }

    it 'renders a single line without ranking groups' do
      expect(subject).to have_text('Les dossiers sont traités en environ un mois')
      expect(subject).not_to have_text('les plus rapides')
      expect(subject).not_to have_text('dans la moyenne')
    end
  end

  context 'when the estimation is missing' do
    let(:traitement_times) { nil }

    it 'does not render' do
      expect(subject.to_html).to be_empty
    end
  end
end
