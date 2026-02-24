# frozen_string_literal: true

describe ApplicationHelper do
  describe 'app_host_legacy?' do
    let(:request) { instance_double(ActionDispatch::Request, base_url: request_base_url) }
    let(:app_host_legacy) { 'legacy' }
    let(:app_host) { 'host' }

    before do
      stub_const("ApplicationHelper::APP_HOST_LEGACY", app_host_legacy)
      stub_const("ApplicationHelper::APP_HOST", app_host)
    end

    subject { app_host_legacy?(request) }

    context 'when request on ENV[APP_HOST_LEGACY]' do
      let(:request_base_url) { app_host_legacy }
      it { is_expected.to be_truthy }
    end

    context 'when request on ENV[APP_HOST]' do
      let(:request_base_url) { app_host }
      it { is_expected.to be_falsey }
    end
  end

  describe 'auto_switch_domain?' do
    subject { auto_switch_domain?(request, user_signed_in) }

    context 'when user_signed_in? is true' do
      let(:user_signed_in) { true }
      let(:request) { instance_double(ActionDispatch::Request, base_url: 'osf', params: {}) }
      it { is_expected.to be_falsey }
    end

    context 'when user_signed_in? is false' do
      let(:user_signed_in) { false }
      let(:params) { {} }
      let(:request) { instance_double(ActionDispatch::Request, base_url: request_base_url, params:) }
      let(:app_host_legacy) { 'legacy' }
      let(:app_host) { 'host' }

      before do
        stub_const("ApplicationHelper::APP_HOST_LEGACY", app_host_legacy)
        stub_const("ApplicationHelper::APP_HOST", app_host)
      end

      context 'request on ENV[APP_HOST_LEGACY] without feature or url' do
        let(:request_base_url) { app_host_legacy }
        it { is_expected.to be_falsey }
      end

      context 'request on ENV[APP_HOST_LEGACY] with switch_domain params' do
        let(:params) { { switch_domain: '1' } }
        let(:request_base_url) { app_host_legacy }
        it { is_expected.to be_truthy }
      end

      context 'request on ENV[APP_HOST_LEGACY] with switch_domain params' do
        before { Flipper.enable :switch_domain }
        after { Flipper.disable :switch_domain }
        let(:request_base_url) { app_host_legacy }
        it { is_expected.to be_truthy }
      end

      context 'request on ENV[APP_HOST]' do
        let(:request_base_url) { app_host }
        it { is_expected.to be_falsey }
      end
    end
  end

  describe "#flash_class" do
    it { expect(flash_class('notice')).to eq 'alert-success fr-icon-success-line fr-icon--sm fr-text--sm fr-mb-0' }
    it { expect(flash_class('alert', sticky: true, fixed: true)).to eq 'alert-danger fr-icon-error-line fr-icon--sm fr-text--sm fr-mb-0 sticky alert-fixed' }
    it { expect(flash_class('error')).to eq 'alert-danger fr-icon-error-line fr-icon--sm fr-text--sm fr-mb-0' }
    it { expect(flash_class('unknown-level')).to eq '' }
  end

  describe "#try_format_date" do
    subject { try_format_date(date) }

    describe 'try formatting a date' do
      let(:date) { Date.new(2019, 01, 24) }
      it { is_expected.to eq("24 janvier 2019") }
    end

    describe 'try formatting a blank string' do
      let(:date) { "" }
      it { is_expected.to eq("") }
    end

    describe 'try formatting a nil string' do
      let(:date) { nil }
      it { is_expected.to eq("") }
    end
  end

  describe "#try_format_datetime" do
    subject { try_format_datetime(datetime) }

    describe 'try formatting 31/01/2019 11:25' do
      let(:datetime) { Time.zone.local(2019, 01, 31, 11, 25, 00) }
      it { is_expected.to eq("31 janvier 2019 11:25") }
    end

    describe 'try formatting a blank string' do
      let(:datetime) { "" }
      it { is_expected.to eq("") }
    end

    describe 'try formatting a nil string' do
      let(:datetime) { nil }
      it { is_expected.to eq("") }
    end
  end

  describe "#human_date" do
    subject { human_date(date) }

    # pf: use Date.current instead of Date.today to respect Pacific/Tahiti timezone
    describe 'human_date for today' do
      let(:date) { Date.current }
      it { is_expected.to eq("Aujourd’hui") }
    end
    describe 'human_date for yesterday' do
      let(:date) { Date.current - 1 }
      it { is_expected.to eq("Hier") }
    end
    describe 'human_date for before yesterday' do
      let(:date) { Date.current - 2 }
      it { is_expected.to eq("Il y a 2 jours") }
    end
    describe 'human_date for 24/01/2019' do
      let(:date) { Date.new(2019, 01, 24) }
      it { is_expected.to eq("24 janvier 2019") }
    end
  end

  # pf: tests des helpers de titres d'onglet compacts
  describe '#title_role_abbreviation' do
    let(:controller_double) { double }

    before do
      allow(helper).to receive(:controller).and_return(controller_double)
    end

    context 'when nav_bar_profile returns :administrateur' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:administrateur) }

      it { expect(helper.title_role_abbreviation).to eq('A') }
    end

    context 'when nav_bar_profile returns :instructeur' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:instructeur) }

      it { expect(helper.title_role_abbreviation).to eq('I') }
    end

    context 'when nav_bar_profile returns :expert' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:expert) }

      it { expect(helper.title_role_abbreviation).to eq('E') }
    end

    context 'when nav_bar_profile returns :gestionnaire' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:gestionnaire) }

      it { expect(helper.title_role_abbreviation).to eq('G') }
    end

    context 'when nav_bar_profile is nil and fallback_nav_bar_profile returns :administrateur' do
      before do
        allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(nil)
        allow(controller_double).to receive(:try).with(:fallback_nav_bar_profile).and_return(:administrateur)
      end

      it { expect(helper.title_role_abbreviation).to eq('A') }
    end

    context 'when both nav_bar_profile and fallback_nav_bar_profile are nil (guest)' do
      before do
        allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(nil)
        allow(controller_double).to receive(:try).with(:fallback_nav_bar_profile).and_return(nil)
      end

      it { expect(helper.title_role_abbreviation).to be_nil }
    end

    context 'when nav_bar_profile returns :user' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:user) }

      it { expect(helper.title_role_abbreviation).to be_nil }
    end

    context 'when nav_bar_profile returns :superadmin' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:superadmin) }

      it { expect(helper.title_role_abbreviation).to be_nil }
    end
  end

  describe '#procedure_tab_title' do
    let(:procedure) { create(:procedure, libelle: 'Demande de subvention pour les associations sportives et culturelles de Polynésie française') }
    let(:controller_double) { double }

    before do
      allow(helper).to receive(:controller).and_return(controller_double)
    end

    context 'when role is instructeur' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:instructeur) }

      it 'returns procedure id with role abbreviation' do
        expect(helper.procedure_tab_title(procedure)).to eq("#{procedure.id}(I)")
      end

      it 'prepends page name when provided' do
        expect(helper.procedure_tab_title(procedure, 'À suivre')).to eq("À suivre · #{procedure.id}(I)")
      end
    end

    context 'when role is administrateur' do
      before { allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(:administrateur) }

      it 'returns procedure id with role abbreviation' do
        expect(helper.procedure_tab_title(procedure)).to eq("#{procedure.id}(A)")
      end

      it 'prepends page name when provided' do
        expect(helper.procedure_tab_title(procedure, 'Champs')).to eq("Champs · #{procedure.id}(A)")
      end
    end

    context 'when no role (guest/user)' do
      before do
        allow(controller_double).to receive(:try).with(:nav_bar_profile).and_return(nil)
        allow(controller_double).to receive(:try).with(:fallback_nav_bar_profile).and_return(nil)
      end

      it 'returns procedure id without role' do
        expect(helper.procedure_tab_title(procedure)).to eq(procedure.id.to_s)
      end

      it 'prepends page name when provided' do
        expect(helper.procedure_tab_title(procedure, 'Détails')).to eq("Détails · #{procedure.id}")
      end
    end
  end

  describe '#dossier_tab_title' do
    context 'when dossier has an individual' do
      let(:procedure) { create(:procedure, :for_individual) }
      let(:dossier) { create(:dossier, :with_individual, procedure: procedure) }

      it 'includes the prénom in parentheses' do
        expect(helper.dossier_tab_title(dossier, 'Demande')).to eq("Demande · #{dossier.id} (#{dossier.individual.prenom})")
      end
    end

    context 'when dossier has an entreprise' do
      let(:dossier) { create(:dossier, :with_entreprise) }

      it 'includes the truncated raison sociale in parentheses' do
        raison = dossier.etablissement.entreprise_raison_sociale.truncate_words(3)
        expect(helper.dossier_tab_title(dossier, 'Demande')).to eq("Demande · #{dossier.id} (#{raison})")
      end
    end

    context 'when dossier has no individual nor entreprise' do
      let(:dossier) { create(:dossier, individual: nil) }

      it 'shows only the dossier id without parentheses' do
        expect(helper.dossier_tab_title(dossier, 'Demande')).to eq("Demande · #{dossier.id}")
      end
    end
  end

  describe '#acronymize' do
    it 'returns the acronym of a given string' do
      expect(helper.acronymize('Application Name')).to eq('AN')
      expect(helper.acronymize('Hello World')).to eq('HW')
      expect(helper.acronymize('Demarches Simplifiees')).to eq('DS')
    end

    it 'handles single word input' do
      expect(helper.acronymize('Word')).to eq('W')
    end

    it 'returns an empty string for empty input' do
      expect(helper.acronymize('')).to eq('')
    end

    it 'handles strings with extensions' do
      expect(helper.acronymize('file_name.txt')).to eq('FN')
      expect(helper.acronymize('example.pdf')).to eq('E')
    end

    it 'handles strings with various word separators' do
      expect(helper.acronymize('multi-word_string')).to eq('MWS')
      expect(helper.acronymize('another_example-test')).to eq('AET')
    end
  end
end
