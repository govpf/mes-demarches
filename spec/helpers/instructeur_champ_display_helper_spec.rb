# frozen_string_literal: true

describe InstructeurChampDisplayHelper do
  let(:instructeur) { create(:instructeur) }
  let(:user) { instructeur.user }

  describe '#dossier_layout_grid_enabled?' do
    subject { helper.dossier_layout_grid_enabled?(instructeur) }

    context 'quand le Flipper gate :dossier_layout_grid est activé pour cet instructeur' do
      before { Flipper.enable(:dossier_layout_grid, instructeur) }
      after { Flipper.disable(:dossier_layout_grid) }

      it { is_expected.to be_truthy }
    end

    context 'quand le Flipper gate est désactivé' do
      it { is_expected.to be_falsey }
    end

    context 'quand instructeur est nil' do
      let(:instructeur) { nil }
      it { is_expected.to be_falsey }
    end
  end

  describe '#show_dossier_layout_banner?' do
    subject { helper.show_dossier_layout_banner?(instructeur) }

    let(:today) { Date.new(2026, 6, 10) } # dans la fenêtre (15 jours après rollout)

    around { |ex| travel_to(today) { ex.run } }

    before { Flipper.enable(:dossier_layout_grid, instructeur) }
    after  { Flipper.disable(:dossier_layout_grid) }

    context 'cas nominal : gate activée, pas de choix, pas de dismiss, user habitué, dans la fenêtre' do
      before { user.update!(created_at: Date.new(2025, 1, 1)) }

      it { is_expected.to be_truthy }
    end

    context 'quand la gate est désactivée' do
      before { Flipper.disable(:dossier_layout_grid) }

      it { is_expected.to be_falsey }
    end

    context 'quand un choix de layout a déjà été posé en DB' do
      before do
        user.update!(created_at: Date.new(2025, 1, 1))
        instructeur.update!(dossier_layout_preference: 'grid')
      end

      it { is_expected.to be_falsey }
    end

    context 'quand le bandeau a déjà été dismissed' do
      before do
        user.update!(created_at: Date.new(2025, 1, 1))
        allow(helper).to receive(:cookies).and_return({ InstructeurChampDisplayHelper::DISMISSED_COOKIE => Time.current.iso8601 }.with_indifferent_access)
      end

      it { is_expected.to be_falsey }
    end

    context 'quand le user a été créé après le rollout (nouvel arrivant)' do
      before { user.update!(created_at: InstructeurChampDisplayHelper::FEATURE_ROLLOUT_DATE + 1.day) }

      it { is_expected.to be_falsey }
    end

    context 'quand on est hors de la fenêtre de transition' do
      let(:today) { InstructeurChampDisplayHelper::FEATURE_ROLLOUT_DATE + InstructeurChampDisplayHelper::BANNER_DURATION + 1.day }

      before { user.update!(created_at: Date.new(2025, 1, 1)) }

      it { is_expected.to be_falsey }
    end
  end

  describe '#dossier_layout_toggle_label' do
    context 'dans la fenêtre de transition' do
      around { |ex| travel_to(InstructeurChampDisplayHelper::FEATURE_ROLLOUT_DATE + 10.days) { ex.run } }

      it 'utilise les libellés de transition' do
        expect(helper.dossier_layout_toggle_label(:grid)).to eq("Revenir à l'ancien affichage")
        expect(helper.dossier_layout_toggle_label(:stacked)).to eq('Revenir au nouvel affichage')
      end
    end

    context 'hors fenêtre de transition' do
      around { |ex| travel_to(InstructeurChampDisplayHelper::FEATURE_ROLLOUT_DATE + InstructeurChampDisplayHelper::BANNER_DURATION + 1.day) { ex.run } }

      it 'utilise les libellés neutres' do
        expect(helper.dossier_layout_toggle_label(:grid)).to eq('Passer au mode liste')
        expect(helper.dossier_layout_toggle_label(:stacked)).to eq('Passer au mode grille')
      end
    end
  end

  describe '#dossier_layout_toggle_icon_class' do
    it 'renvoie l\'icône correspondant au mode cible' do
      expect(helper.dossier_layout_toggle_icon_class(:grid)).to eq('fr-icon-list-unordered')
      expect(helper.dossier_layout_toggle_icon_class(:stacked)).to eq('fr-icon-layout-grid-fill')
    end
  end

  describe '#instructeur_champs_layout_mode' do
    it 'retourne la pref DB si présente' do
      instructeur.update!(dossier_layout_preference: 'stacked')
      expect(helper.instructeur_champs_layout_mode(instructeur)).to eq(:stacked)
    end

    it 'retourne :grid par défaut si aucun choix' do
      expect(helper.instructeur_champs_layout_mode(instructeur)).to eq(:grid)
    end

    it 'retourne :grid si instructeur est nil' do
      expect(helper.instructeur_champs_layout_mode(nil)).to eq(:grid)
    end
  end

  describe '#instructeur_champs_layout_chosen?' do
    it 'est faux sans choix DB' do
      expect(helper.instructeur_champs_layout_chosen?(instructeur)).to be_falsey
    end

    it 'est vrai si une pref est en DB' do
      instructeur.update!(dossier_layout_preference: 'grid')
      expect(helper.instructeur_champs_layout_chosen?(instructeur)).to be_truthy
    end
  end
end
