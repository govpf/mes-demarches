# frozen_string_literal: true

describe InstructeurChampDisplayHelper do
  let(:instructeur) { create(:instructeur) }
  let(:user) { instructeur.user }

  def fake_pj_champ(attachments_count:, type: :piece_justificative)
    attachments = double('attachments', size: attachments_count)
    pjf = double('piece_justificative_file', attachments: attachments)
    double(
      'champ',
      type_champ: type.to_s,
      piece_justificative?: type == :piece_justificative,
      titre_identite?: type == :titre_identite,
      piece_justificative_file: pjf
    )
  end

  def fake_other_champ(type)
    double(
      'champ',
      type_champ: type.to_s,
      piece_justificative?: false,
      titre_identite?: false
    )
  end

  describe '#champ_display_width' do
    it 'PJ avec 1 fichier → :third' do
      expect(helper.champ_display_width(fake_pj_champ(attachments_count: 1))).to eq(:third)
    end

    it 'PJ avec 0 fichier (champ vide) → :third' do
      expect(helper.champ_display_width(fake_pj_champ(attachments_count: 0))).to eq(:third)
    end

    it 'PJ avec 2 fichiers → :full' do
      expect(helper.champ_display_width(fake_pj_champ(attachments_count: 2))).to eq(:full)
    end

    it 'PJ avec 5 fichiers → :full' do
      expect(helper.champ_display_width(fake_pj_champ(attachments_count: 5))).to eq(:full)
    end

    it 'titre_identite mono-fichier → :third' do
      expect(helper.champ_display_width(fake_pj_champ(attachments_count: 1, type: :titre_identite))).to eq(:third)
    end

    it 'titre_identite multi-fichier → :full' do
      expect(helper.champ_display_width(fake_pj_champ(attachments_count: 2, type: :titre_identite))).to eq(:full)
    end

    it 'header_section → :full' do
      expect(helper.champ_display_width(fake_other_champ(:header_section))).to eq(:full)
    end

    it 'siret → :full' do
      expect(helper.champ_display_width(fake_other_champ(:siret))).to eq(:full)
    end

    it 'formule (default) → :third' do
      expect(helper.champ_display_width(fake_other_champ(:formule))).to eq(:third)
    end

    it 'text (default) → :third' do
      expect(helper.champ_display_width(fake_other_champ(:text))).to eq(:third)
    end
  end

  describe '#champ_break_before_class' do
    let(:pj_mono)         { fake_pj_champ(attachments_count: 1) }
    let(:pj_mono_other)   { fake_pj_champ(attachments_count: 1) }
    let(:ti_mono)         { fake_pj_champ(attachments_count: 1, type: :titre_identite) }
    let(:pj_multi)        { fake_pj_champ(attachments_count: 3) }
    let(:text_champ)      { fake_other_champ(:text) }
    let(:header_champ)    { fake_other_champ(:header_section) }

    it 'pas de previous → nil (premier champ)' do
      expect(helper.champ_break_before_class(pj_mono, nil)).to be_nil
    end

    it 'PJ-mono après champ texte → break-before' do
      expect(helper.champ_break_before_class(pj_mono, text_champ)).to eq('champ-grid-item--break-before')
    end

    it 'PJ-mono après PJ-mono → nil (groupées)' do
      expect(helper.champ_break_before_class(pj_mono, pj_mono_other)).to be_nil
    end

    it 'titre_identite-mono après PJ-mono → nil (groupées entre attachments)' do
      expect(helper.champ_break_before_class(ti_mono, pj_mono)).to be_nil
    end

    it 'champ texte après PJ-mono → break-before' do
      expect(helper.champ_break_before_class(text_champ, pj_mono)).to eq('champ-grid-item--break-before')
    end

    it 'PJ-multi (full) après PJ-mono → break-before' do
      expect(helper.champ_break_before_class(pj_multi, pj_mono)).to eq('champ-grid-item--break-before')
    end

    it 'PJ-mono après PJ-multi → break-before' do
      expect(helper.champ_break_before_class(pj_mono, pj_multi)).to eq('champ-grid-item--break-before')
    end

    it 'header (full) après texte → nil (transition non-pj-mono → non-pj-mono)' do
      expect(helper.champ_break_before_class(header_champ, text_champ)).to be_nil
    end
  end

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
