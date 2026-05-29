# frozen_string_literal: true

describe TypeDeChamp do
  describe 'validation' do
    context 'type' do
      it do
        is_expected.not_to allow_value(nil).for(:type_champ)
        is_expected.not_to allow_value('').for(:type_champ)
      end

      let(:procedure) { create(:procedure, :with_all_champs) }
      let(:dossier) { create(:dossier, procedure:) }

      it do
        dossier.revision.types_de_champ_public.each do |type_de_champ|
          champ = dossier.project_champ(type_de_champ)
          expect(type_de_champ.dynamic_type.class.name).to match(/^TypesDeChamp::/)
          expect(champ.class.name).to match(/^Champs::/)
        end
      end
    end

    context 'description' do
      it do
        is_expected.to allow_value(nil).for(:description)
        is_expected.to allow_value('').for(:description)
        is_expected.to allow_value('blabla').for(:description)
      end
    end

    context 'stable_id' do
      it {
        type_de_champ = create(:type_de_champ_text)
        expect(type_de_champ.id).to eq(type_de_champ.stable_id)
        cloned_type_de_champ = type_de_champ.clone
        expect(cloned_type_de_champ.stable_id).to eq(type_de_champ.stable_id)
      }
    end

    context 'changing the type_champ from a piece_justificative' do
      context 'when the tdc is piece_justificative' do
        let(:template_double) { double('template', attached?: attached, purge_later: true, blob: double(byte_size: 10, content_type: 'text/plain')) }
        let(:tdc) { create(:type_de_champ_piece_justificative) }

        subject { template_double }

        before do
          allow(tdc).to receive(:piece_justificative_template).and_return(template_double)

          tdc.update(type_champ: target_type_champ)
        end

        context 'when the target type_champ is not pj' do
          let(:target_type_champ) { TypeDeChamp.type_champs.fetch(:text) }

          context 'calls template.purge_later when a file is attached' do
            let(:attached) { true }

            it { is_expected.to have_received(:purge_later) }
          end

          context 'does not call template.purge_later when no file is attached' do
            let(:attached) { false }

            it { is_expected.not_to have_received(:purge_later) }
          end
        end

        context 'when the target type_champ is pj' do
          let(:target_type_champ) { TypeDeChamp.type_champs.fetch(:piece_justificative) }

          context 'does not call template.purge_later when a file is attached' do
            let(:attached) { true }

            it { is_expected.not_to have_received(:purge_later) }
          end
        end
      end
    end

    describe 'changing the type_champ from a drop_down_list' do
      let(:tdc) { create(:type_de_champ_drop_down_list) }

      before do
        tdc.update(type_champ: target_type_champ)
      end

      context 'when the target type_champ is not drop_down_list' do
        let(:target_type_champ) { TypeDeChamp.type_champs.fetch(:text) }

        it do
          expect(tdc.drop_down_options).to be_present
          expect(tdc.drop_down_options).to eq(["val1", "val2", "val3"])
        end
      end

      context 'when the target type_champ is linked_drop_down_list' do
        let(:target_type_champ) { TypeDeChamp.type_champs.fetch(:linked_drop_down_list) }

        it do
          expect(tdc.drop_down_options).to be_present
          expect(tdc.drop_down_options).to eq(['--Fromage--', 'bleu de sassenage', 'picodon', '--Dessert--', 'éclair', 'tarte aux pommes'])
        end
      end

      context 'when the target type_champ is multiple_drop_down_list' do
        let(:target_type_champ) { TypeDeChamp.type_champs.fetch(:multiple_drop_down_list) }

        it do
          expect(tdc.drop_down_options).to be_present
          expect(tdc.drop_down_options).to eq(["val1", "val2", "val3"])
        end
      end
    end

    context 'delegate validation to dynamic type' do
      subject { build(:type_de_champ_text) }
      let(:dynamic_type) do
        Class.new(TypesDeChamp::TypeDeChampBase) do
          validate :never_valid

          def never_valid
            errors.add(:troll, 'always invalid')
          end
        end.new(subject)
      end

      before { subject.instance_variable_set(:@dynamic_type, dynamic_type) }

      it do
        is_expected.to be_invalid
        expect(subject.errors.full_messages.to_sentence).to eq("Le champ « Troll » always invalid")
      end
    end
  end

  describe 'piece_justificative nature and options' do
    describe '#allowed_content_types' do
      it 'returns jpeg/png for titre_identite' do
        tdc = create(:type_de_champ_piece_justificative, nature: 'TITRE_IDENTITE')
        expect(tdc.allowed_content_types).to match_array(['image/jpeg', 'image/png'])
      end

      it 'includes doc and image types for RIB' do
        tdc = create(:type_de_champ_piece_justificative, nature: 'RIB')
        expect(tdc.allowed_content_types).to include('application/pdf').or include('application/msword')
        expect(tdc.allowed_content_types).to include('image/jpeg').or include('image/png')
      end

      it 'restricts to selected families when pj_limit_formats enabled' do
        tdc = create(:type_de_champ_piece_justificative, pj_limit_formats: '1', pj_format_families: ['document_texte'])
        expect(tdc.allowed_content_types).to include('application/pdf')
        expect(tdc.allowed_content_types).not_to include('application/zip')
      end

      it 'does not restrict when pj_limit_formats enabled but families empty' do
        tdc = create(:type_de_champ_piece_justificative, pj_limit_formats: '1', pj_format_families: [])
        expect(tdc.allowed_content_types).to include('application/pdf')
        expect(tdc.allowed_content_types).to include('application/zip')
      end
    end

    describe '#max_file_size_bytes' do
      it 'is 20MB for titre_identite' do
        tdc = create(:type_de_champ_piece_justificative, nature: 'TITRE_IDENTITE')
        expect(tdc.max_file_size_bytes).to eq(20.megabytes)
      end

      it 'is 200MB by default' do
        tdc = create(:type_de_champ_piece_justificative)
        expect(tdc.max_file_size_bytes).to eq(TypeDeChamp::FILE_MAX_SIZE)
      end
    end

    describe '#pj_auto_purge?' do
      it 'is true for titre_identite' do
        tdc = create(:type_de_champ_piece_justificative, nature: 'TITRE_IDENTITE')
        expect(tdc.pj_auto_purge?).to be true
      end

      it 'reflects the option otherwise' do
        tdc = create(:type_de_champ_piece_justificative, pj_auto_purge: '1')
        expect(tdc.pj_auto_purge?).to be true
        tdc2 = create(:type_de_champ_piece_justificative, pj_auto_purge: '0')
        expect(tdc2.pj_auto_purge?).to be false
      end
    end
  end

  describe "linked_drop_down_list" do
    let(:type_de_champ) { create(:type_de_champ_linked_drop_down_list) }

    it 'should validate without label' do
      type_de_champ.drop_down_options = ['toto']
      expect(type_de_champ.validate).to be_falsey
      messages = type_de_champ.errors.full_messages
      expect(messages.size).to eq(1)
      expect(messages.first).to eq("Le champ « #{type_de_champ.libelle} » doit commencer par une entrée de menu primaire de la forme <code style='white-space: pre-wrap;'>--texte--</code>")

      type_de_champ.libelle = ''
      expect(type_de_champ.validate).to be_falsey
      messages = type_de_champ.errors.full_messages
      expect(messages.size).to eq(1)
      expect(messages.last).to eq("Le champ « La liste » doit commencer par une entrée de menu primaire de la forme <code style='white-space: pre-wrap;'>--texte--</code>")
    end
  end

  describe "validate_regexp" do
    let(:tdc) { create(:type_de_champ_formatted, expression_reguliere:, expression_reguliere_exemple_text:) }
    subject { tdc.invalid_regexp? }

    context "expression_reguliere and bad example" do
      let(:expression_reguliere_exemple_text) { "01234567" }
      let(:expression_reguliere) { "[A-Z]+" }

      it "should add only one error message" do
        expect(subject).to be_truthy
        expect(tdc.errors.messages[:expression_reguliere_exemple_text].size).to eq(1)

        tdc.invalid_regexp?

        expect(tdc.errors.messages[:expression_reguliere_exemple_text].size).to eq(1)
      end
    end

    context "Bad expression_reguliere" do
      let(:expression_reguliere_exemple_text) { "0123456789" }
      let(:expression_reguliere) { "(" }

      it "should add error message" do
        expect(subject).to be_truthy
        expect(tdc.errors.messages[:expression_reguliere]).to be_present
      end
    end
  end

  describe '#drop_down_options' do
    let(:type_de_champ) { create(:type_de_champ_drop_down_list) }

    it "splits input" do
      type_de_champ.drop_down_options_from_text = nil
      expect(type_de_champ.drop_down_options).to eq([])

      type_de_champ.drop_down_options_from_text = "\n\r"
      expect(type_de_champ.drop_down_options).to eq([])

      type_de_champ.drop_down_options_from_text = " 1 / 2 \r\n 3"
      expect(type_de_champ.drop_down_options).to eq(['1 / 2', '3'])
    end
  end

  describe '#public_only' do
    let(:procedure) { create(:procedure, :with_type_de_champ, :with_type_de_champ_private) }

    it 'partition public and private' do
      expect(procedure.active_revision.types_de_champ_public.count).to eq(1)
      expect(procedure.active_revision.types_de_champ_private.count).to eq(1)
    end
  end

  describe 'condition' do
    let(:type_de_champ) { create(:type_de_champ) }
    let(:condition) { Logic::Eq.new(Logic::Constant.new(true), Logic::Constant.new(true)) }

    it 'saves and reload the condition' do
      type_de_champ.update(condition: condition)
      type_de_champ.reload
      expect(type_de_champ.condition).to eq(condition)
    end
  end

  describe '#prefillable?' do
    shared_examples 'a prefillable type de champ' do |factory|
      it { expect(build(factory).prefillable?).to eq(true) }
    end

    shared_examples 'a non-prefillable type de champ' do |factory|
      it { expect(build(factory).prefillable?).to eq(false) }
    end

    it_behaves_like "a prefillable type de champ", :type_de_champ_text
    it_behaves_like "a prefillable type de champ", :type_de_champ_textarea
    it_behaves_like "a prefillable type de champ", :type_de_champ_decimal_number
    it_behaves_like "a prefillable type de champ", :type_de_champ_integer_number
    it_behaves_like "a prefillable type de champ", :type_de_champ_email
    it_behaves_like "a prefillable type de champ", :type_de_champ_phone
    it_behaves_like "a prefillable type de champ", :type_de_champ_iban
    it_behaves_like "a prefillable type de champ", :type_de_champ_date
    it_behaves_like "a prefillable type de champ", :type_de_champ_datetime
    it_behaves_like "a prefillable type de champ", :type_de_champ_civilite
    it_behaves_like "a prefillable type de champ", :type_de_champ_pays
    it_behaves_like "a prefillable type de champ", :type_de_champ_regions
    it_behaves_like "a prefillable type de champ", :type_de_champ_departements
    it_behaves_like "a prefillable type de champ", :type_de_champ_communes
    it_behaves_like "a prefillable type de champ", :type_de_champ_address
    it_behaves_like "a prefillable type de champ", :type_de_champ_yes_no
    it_behaves_like "a prefillable type de champ", :type_de_champ_checkbox
    it_behaves_like "a prefillable type de champ", :type_de_champ_drop_down_list
    it_behaves_like "a prefillable type de champ", :type_de_champ_repetition
    it_behaves_like "a prefillable type de champ", :type_de_champ_multiple_drop_down_list
    it_behaves_like "a prefillable type de champ", :type_de_champ_epci
    it_behaves_like "a prefillable type de champ", :type_de_champ_dossier_link
    it_behaves_like "a prefillable type de champ", :type_de_champ_siret

    it_behaves_like "a non-prefillable type de champ", :type_de_champ_number
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_titre_identite
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_linked_drop_down_list
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_header_section
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_explication
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_piece_justificative
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_cnaf
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_dgfip
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_pole_emploi
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_mesri
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_carte
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_rna
    it_behaves_like "a non-prefillable type de champ", :type_de_champ_annuaire_education
  end

  describe '#normalize_libelle' do
    it do
      expect(create(:type_de_champ, :header_section, libelle: " 2.3 Test").libelle).to eq("2.3 Test")
      expect(create(:type_de_champ, libelle: " fix me ").libelle).to eq("fix me")
    end
  end

  describe '#set_default_libelle' do
    let(:type_de_champ) { create(:type_de_champ, type_champ: :header_section, libelle: libelle) }
    let(:libelle) { nil }

    it { expect(type_de_champ.libelle).to eq("Titre de section") }

    context "when the type champ is changed" do
      before { type_de_champ.update(type_champ: :dossier_link) }

      it { expect(type_de_champ.libelle).to eq("Numéro de dossier déposé sur %{app_name}") }

      context "when the libelle is customized" do
        let(:libelle) { "Customized libelle" }

        it { expect(type_de_champ.libelle).to eq("Customized libelle") }
      end
    end
  end

  describe '#safe_filename' do
    subject { build(:type_de_champ, libelle:).libelle_as_filename }

    let(:libelle) { "  #/🐉 1 très  intéressant Bilan " }

    it { is_expected.to eq("1-tres-interessant-bilan") }
  end

  describe '#clean_options' do
    subject { procedure.published_revision.types_de_champ.first.options }

    let(:procedure) { create(:procedure) }

    context "Header section" do
      let(:type_de_champ) { create(:type_de_champ_header_section, procedure:) }

      before do
        type_de_champ.update!(options: { 'header_section_level' => '1', 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the header_section_level' do
        is_expected.to eq({ 'header_section_level' => '1' })
      end
    end

    context "Explication" do
      let(:type_de_champ) { create(:type_de_champ_explication, procedure:) }

      before do
        type_de_champ.update!(options: { 'collapsible_explanation_enabled' => '1', 'collapsible_explanation_text' => 'hello', 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the collapsible_explanation keys' do
        is_expected.to eq({ 'collapsible_explanation_enabled' => '1', 'collapsible_explanation_text' => 'hello' })
      end
    end

    context "Text area" do
      let(:type_de_champ) { create(:type_de_champ_textarea, procedure:) }

      before do
        type_de_champ.update!(options: { 'character_limit' => '400', 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the character limit' do
        is_expected.to eq({ 'character_limit' => '400' })
      end
    end

    context "Carte" do
      let(:type_de_champ) { create(:type_de_champ_carte, procedure:) }

      before do
        type_de_champ.update!(options: { 'unesco' => '0', 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the layers' do
        is_expected.to eq({ 'unesco' => '0' })
      end
    end

    context "Simple drop down_list" do
      let(:type_de_champ) { create(:type_de_champ_drop_down_list, procedure:) }

      before do
        type_de_champ.update!(options: { 'drop_down_other' => '0', 'drop_down_options' => ['Premier choix', 'Deuxième choix'], 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the drop_down_other and drop_down_options' do
        is_expected.to eq({ 'drop_down_other' => '0', 'drop_down_options' => ['Premier choix', 'Deuxième choix'] })
      end
    end

    context "Multiple drop down_list" do
      let(:type_de_champ) { create(:type_de_champ_multiple_drop_down_list, procedure:) }

      before do
        type_de_champ.update!(options: { 'drop_down_options' => ['Premier choix', 'Deuxième choix'], 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the drop_down_options' do
        is_expected.to eq({ 'drop_down_options' => ['Premier choix', 'Deuxième choix'] })
      end
    end

    context "Linked drop down list" do
      let(:type_de_champ) { create(:type_de_champ_linked_drop_down_list, procedure:) }

      before do
        type_de_champ.update!(options: { 'drop_down_options' => ['--Fromage--', 'bleu de sassenage', 'picodon', '--Dessert--', 'éclair', 'tarte aux pommes'], 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the drop_down_options' do
        is_expected.to eq({ 'drop_down_options' => ['--Fromage--', 'bleu de sassenage', 'picodon', '--Dessert--', 'éclair', 'tarte aux pommes'] })
      end
    end

    context "Integer number" do
      let(:type_de_champ) { create(:type_de_champ_integer_number, procedure:) }

      before do
        type_de_champ.update!(options: { "positive_number" => "1", "range_number" => '1', "min_number" => '2', "max_number" => '18' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping the positive number options' do
        is_expected.to eq({ "positive_number" => "1", "range_number" => '1', "min_number" => '2', "max_number" => '18' })
      end
    end

    context "Decimal number" do
      let(:type_de_champ) { create(:type_de_champ_decimal_number, procedure:) }

      before do
        type_de_champ.update!(options: { "positive_number" => "1", "range_number" => '1', "min_number" => '2.5', "max_number" => '18' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping the positive number options' do
        is_expected.to eq({ "positive_number" => "1", "range_number" => '1', "min_number" => '2.5', "max_number" => '18' })
      end
    end

    context "Piece justificative" do
      let(:type_de_champ) { create(:type_de_champ_piece_justificative, procedure:) }

      before do
        type_de_champ.update!(options: { 'old_pj' => '123', 'skip_pj_validation' => '1', 'skip_content_type_pj_validation' => '1', 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the old_pj, skip_validation_pj and skip_content_type_pj_validation' do
        is_expected.to eq({ 'old_pj' => '123', 'skip_pj_validation' => '1', 'skip_content_type_pj_validation' => '1' })
      end
    end

    context "Visa" do
      let(:type_de_champ) { create(:type_de_champ_visa, procedure:) }

      before do
        type_de_champ.update!(options: { 'accredited_users' => ['user1@example.com', 'user2@example.com'], 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the accredited_users' do
        is_expected.to eq({ 'accredited_users' => ['user1@example.com', 'user2@example.com'] })
      end
    end

    context "Te Fenua" do
      let(:type_de_champ) { create(:type_de_champ_te_fenua, procedure:) }

      before do
        type_de_champ.update!(options: { 'parcelles' => '1', 'batiments' => '0', 'zones_manuelles' => '1', 'te_fenua_layer' => '1', 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the parcelles, batiments, zones_manuelles and te_fenua_layer' do
        is_expected.to eq({ 'parcelles' => '1', 'batiments' => '0', 'zones_manuelles' => '1', 'te_fenua_layer' => '1' })
      end
    end

    context "Lexpol" do
      let(:type_de_champ) { create(:type_de_champ_lexpol, procedure:) }

      before do
        type_de_champ.update!(options: { 'lexpol_modele' => 'modele_1', 'lexpol_mapping' => { 'field1' => 'value1' }, 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the lexpol_modele and lexpol_mapping' do
        is_expected.to eq({ 'lexpol_modele' => 'modele_1', 'lexpol_mapping' => { 'field1' => 'value1' } })
      end
    end

    context "Champ formaté simple" do
      let(:type_de_champ) { create(:type_de_champ_formatted, procedure:) }

      before do
        type_de_champ.update!(options: { 'formatted_mode' => 'simple', 'letters_accepted' => "1", 'numbers_accepted' => '1', "special_characters_accepted" => "0", 'min_character_length' => "4", 'max_character_length' => "5", "key" => "value" })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the formatted mode, letters_accepted, numbers_accepted, special_characters_accepted' do
        is_expected.to eq({ 'formatted_mode' => 'simple', 'letters_accepted' => "1", 'numbers_accepted' => '1', "special_characters_accepted" => "0", 'min_character_length' => "4", 'max_character_length' => "5" })
      end
    end

    context "Champ formaté avancé" do
      let(:type_de_champ) { create(:type_de_champ_formatted, procedure:) }

      before do
        type_de_champ.update!(options: { 'formatted_mode' => 'advanced', 'expression_reguliere' => '\d{9}', 'expression_reguliere_error_message' => 'error', 'expression_reguliere_exemple_text' => '123456789', 'key' => 'value' })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the expression_reguliere, expression_reguliere_error_message and expression_reguliere_exemple_text' do
        is_expected.to eq({ 'formatted_mode' => 'advanced', 'expression_reguliere' => '\d{9}', 'expression_reguliere_error_message' => 'error', 'expression_reguliere_exemple_text' => '123456789' })
      end
    end

    context 'Champ referentiel' do
      let(:procedure) { create(:procedure, types_de_champ_public:) }
      let(:types_de_champ_public) { [{ type: :referentiel, referentiel: }] }
      let(:referentiel) { create(:api_referentiel, :exact_match, :with_exact_match_response) }
      let(:type_de_champ) { procedure.draft_revision.types_de_champ.first }

      before do
        type_de_champ.update!(options: { 'referentiel_mapping' => { 'kikoo' => 'lol' } })
        procedure.publish_revision!(procedure.administrateurs.first)
      end

      it 'keeping only the expression_reguliere, expression_reguliere_error_message and expression_reguliere_exemple_text' do
        is_expected.to eq({ 'referentiel_mapping' => { 'kikoo' => 'lol' } })
      end
    end
  end

  describe 'champ_value with cast' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: type_champ }]) }
    let(:dossier) { create(:dossier, procedure:) }
    let(:type_champ) { :text }
    let(:last_write_type_champ) { :text }
    let(:champ_value) { 'hello' }
    let(:champ_type) { TypeDeChamp.type_champ_to_champ_class_name(last_write_type_champ.to_s) }
    let(:type_de_champ) { procedure.active_revision.types_de_champ.first }
    let(:champ) { dossier.champs.first }

    subject { champ.update_columns(type: champ_type, value: champ_value); type_de_champ.champ_value(champ) }

    it { expect(subject).to eq('hello') }

    context 'text -> integer_number' do
      let(:last_write_type_champ) { :text }
      let(:type_champ) { :integer_number }

      it { expect(subject).to eq('hello') }
    end

    context 'integer_number -> text' do
      let(:last_write_type_champ) { :integer_number }
      let(:type_champ) { :text }
      let(:champ_value) { '42' }

      it { expect(subject).to eq('42') }
    end

    context 'integer_number -> decimal_number' do
      let(:last_write_type_champ) { :integer_number }
      let(:type_champ) { :decimal_number }
      let(:champ_value) { '42' }

      it { expect(subject).to eq('42') }
    end

    context 'decimal_number -> integer_number' do
      let(:last_write_type_champ) { :decimal_number }
      let(:type_champ) { :integer_number }
      let(:champ_value) { '42.1' }

      it { expect(subject).to eq('42.1') }
    end

    context 'decimal_number -> text' do
      let(:last_write_type_champ) { :decimal_number }
      let(:type_champ) { :text }
      let(:champ_value) { '42.1' }

      it { expect(subject).to eq('42.1') }
    end

    context 'drop_down_list -> multiple_drop_down_list' do
      let(:last_write_type_champ) { :drop_down_list }
      let(:type_champ) { :multiple_drop_down_list }
      let(:champ_value) { type_de_champ.drop_down_options.first }

      it { expect(subject).to eq(champ_value) }
    end

    context 'drop_down_list -> text' do
      let(:last_write_type_champ) { :drop_down_list }
      let(:type_champ) { :text }
      let(:champ_value) { 'val1' }

      it { expect(subject).to eq(champ_value) }
    end

    context 'multiple_drop_down_list -> drop_down_list' do
      let(:last_write_type_champ) { :multiple_drop_down_list }
      let(:type_champ) { :drop_down_list }
      let(:champ_value) { type_de_champ.drop_down_options.to_json }

      it { expect(subject).to eq(type_de_champ.drop_down_options.first) }
    end

    context 'multiple_drop_down_list -> text' do
      let(:last_write_type_champ) { :multiple_drop_down_list }
      let(:type_champ) { :text }
      let(:champ_value) { '["val1", "val2"]' }

      it { expect(subject).to eq("val1, val2") }
    end

    context 'text -> formatted' do
      let(:last_write_type_champ) { :text }
      let(:type_champ) { :formatted }

      it { expect(subject).to eq('hello') }
    end

    context 'formatted -> text' do
      let(:last_write_type_champ) { :formatted }
      let(:type_champ) { :text }

      it { expect(subject).to eq('hello') }
    end

    context 'formatted -> textarea' do
      let(:last_write_type_champ) { :formatted }
      let(:type_champ) { :textarea }

      it { expect(subject).to eq('hello') }
    end

    context 'text -> textarea' do
      let(:last_write_type_champ) { :text }
      let(:type_champ) { :textarea }

      it { expect(subject).to eq('hello') }
    end
  end

  describe '#humanized_conditionable_types_by_category' do
    subject { TypeDeChamp.humanized_conditionable_types_by_category }

    it { is_expected.to eq([["« Référentiel des administrations »"], ["« Formule »", "« Nombre entier »", "« Nombre décimal »"], ["« Oui/Non »", "« Case à cocher seule »", "« Choix simple »", "« Choix multiple »"], ["« Adresse en France »", "« Communes »", "« EPCI »", "« Départements »", "« Régions »", "« Pays »", "« Commune de Polynésie »", "« Code Postal de Polynésie »"]]) }
  end

  describe '.referentiel_tables' do
    it 'retourne les tables triées par ordre alphabétique' do
      unsorted_tables = [
        { name: 'Zones', id: 3 },
        { name: 'Activités', id: 1 },
        { name: 'Communes', id: 2 },
      ]
      allow(ReferentielDePolynesie::API).to receive(:available_tables).and_return(unsorted_tables)
      Rails.cache.delete("referentiel_tables:#{Rails.env}")

      result = TypeDeChamp.referentiel_tables

      expect(result).to eq([['Activités', 1], ['Communes', 2], ['Zones', 3]])
    end
  end

  describe '#table_id' do
    let(:type_de_champ) { create(:type_de_champ_referentiel_de_polynesie) }

    context 'avec uniquement options legacy (avant harmonisation)' do
      before { type_de_champ.update_column(:options, { 'table_id' => '24' }) }

      it 'retourne la valeur legacy' do
        expect(type_de_champ.table_id).to eq('24')
      end
    end

    context 'avec uniquement un referentiel Baserow (nouveau flux)' do
      let(:referentiel) { create(:baserow_referentiel, url: 'baserow://25') }
      before { type_de_champ.update!(referentiel: referentiel) }

      it 'retourne la valeur du referentiel' do
        expect(type_de_champ.table_id).to eq('25')
      end
    end

    context 'avec options legacy ET un referentiel Baserow (migration)' do
      let(:referentiel) { create(:baserow_referentiel, url: 'baserow://25') }
      before do
        type_de_champ.update_column(:options, { 'table_id' => '24' })
        type_de_champ.update!(referentiel: referentiel)
      end

      it 'le referentiel prime sur les options legacy' do
        expect(type_de_champ.table_id).to eq('25')
      end
    end
  end

  describe 'formula expression methods' do
    let(:procedure) { build(:procedure) }
    let(:revision) { procedure.active_revision }
    let(:montant_tdc) { build(:type_de_champ_integer_number, libelle: 'Montant HT', stable_id: 123) }
    let(:formule_tdc) { build(:type_de_champ_formule) }

    before do
      allow(revision).to receive(:types_de_champ).and_return([montant_tdc, formule_tdc])
      allow(formule_tdc).to receive(:revisions).and_return([revision])
    end

    describe '#formule_user_expression' do
      context 'when formule_expression contains stable_ids' do
        before do
          formule_tdc.formule_expression = '{123} * 1.2'
        end

        it 'converts to user-friendly libelles' do
          expect(formule_tdc.formule_user_expression).to eq('{Montant HT} * 1.2')
        end

        it 'caches the result' do
          expect(FormulaExpressionService).to receive(:convert_to_libelles).once.and_return('{Montant HT} * 1.2')

          2.times { formule_tdc.formule_user_expression }
        end
      end

      context 'when not a formule type' do
        let(:text_tdc) { build(:type_de_champ_text) }

        it 'returns empty string' do
          expect(text_tdc.formule_user_expression).to eq('')
        end
      end
    end

    # pf: Tests for formula order constraints
    describe '#available_champs_for_formula' do
      let(:procedure) { create(:procedure, :published) }
      let(:revision) { procedure.active_revision }

      context 'for a public formule champ' do
        # Utilise after_stable_id pour maintenir l'ordre: champ1 (0), champ2 (1), formule (2), champ3 (3)
        let!(:champ1) { procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Champ 1') }
        let!(:champ2) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Champ 2', after_stable_id: champ1.stable_id) }
        let!(:formule) { procedure.draft_revision.add_type_de_champ(type_champ: :formule, libelle: 'Formule', after_stable_id: champ2.stable_id) }
        let!(:champ3) { procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Champ 3', after_stable_id: formule.stable_id) }

        it 'returns only preceding public champs' do
          # formule (position 2) peut référencer champ1 (0) et champ2 (1), mais PAS champ3 (3)
          available = formule.available_champs_for_formula(procedure.draft_revision)
          expect(available.map(&:libelle)).to contain_exactly('Champ 1', 'Champ 2')
          expect(available.map(&:libelle)).not_to include('Champ 3')
        end

        it 'does not include private annotations' do
          annotation = procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Annotation', private: true)

          available = formule.available_champs_for_formula(procedure.draft_revision)
          expect(available.map(&:libelle)).not_to include('Annotation')
        end
      end

      context 'for a private formule annotation' do
        # Ordre: public1 (0), public2 (1) | annot1 (0 private), formule (1 private), annot2 (2 private)
        let!(:public1) { procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Public 1') }
        let!(:public2) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Public 2', after_stable_id: public1.stable_id) }
        let!(:annot1) { procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Annotation 1', private: true) }
        let!(:formule) { procedure.draft_revision.add_type_de_champ(type_champ: :formule, libelle: 'Formule Privée', private: true, after_stable_id: annot1.stable_id) }
        let!(:annot2) { procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Annotation 2', private: true, after_stable_id: formule.stable_id) }

        it 'returns ALL public champs regardless of position' do
          available = formule.available_champs_for_formula(procedure.draft_revision)
          expect(available.map(&:libelle)).to include('Public 1', 'Public 2')
        end

        it 'returns only preceding private annotations' do
          # formule (position 1) peut référencer annot1 (position 0), mais PAS annot2 (position 2)
          available = formule.available_champs_for_formula(procedure.draft_revision)
          expect(available.map(&:libelle)).to include('Annotation 1')
          expect(available.map(&:libelle)).not_to include('Annotation 2')
        end
      end
    end

    describe 'formula validation with order constraints' do
      let(:procedure) { create(:procedure) }

      context 'for a public formule champ' do
        # Ordre: champ1 (0), formule (1), champ2 (2)
        let!(:champ1) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Montant') }
        let!(:formule) { procedure.draft_revision.add_type_de_champ(type_champ: :formule, libelle: 'Total', after_stable_id: champ1.stable_id) }
        let!(:champ2) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Taux', after_stable_id: formule.stable_id) }

        it 'validates references to preceding champs' do
          formule.formule_expression = "{#{champ1.stable_id}} * 2"
          formule.save(validate: false)
          expect(procedure.valid?(:types_de_champ_public_editor)).to be_truthy
        end

        it 'rejects references to following champs' do
          formule.formule_expression = "{#{champ2.stable_id}} * 2"
          formule.save(validate: false)
          expect(procedure.valid?(:types_de_champ_public_editor)).to be_falsey
          expect(procedure.errors[:draft_types_de_champ_public]).to include(match(/Total.*Taux/))
        end

        it 'rejects references to private annotations' do
          annot = procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Note', private: true)

          formule.formule_expression = "{#{annot.stable_id}}"
          formule.save(validate: false)
          expect(procedure.valid?(:types_de_champ_public_editor)).to be_falsey
        end
      end

      context 'for a private formule annotation' do
        # Ordre: public_champ (0) | annot1 (0 private), formule (1 private), annot2 (2 private)
        let!(:public_champ) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Montant') }
        let!(:annot1) { procedure.draft_revision.add_type_de_champ(type_champ: :text, libelle: 'Note', private: true) }
        let!(:formule) { procedure.draft_revision.add_type_de_champ(type_champ: :formule, libelle: 'Calcul', private: true, after_stable_id: annot1.stable_id) }
        let!(:annot2) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Score', private: true, after_stable_id: formule.stable_id) }

        it 'validates references to public champs regardless of position' do
          formule.formule_expression = "{#{public_champ.stable_id}} * 2"
          formule.save(validate: false)
          expect(procedure.valid?(:types_de_champ_private_editor)).to be_truthy
        end

        it 'validates references to preceding private annotations' do
          formule.formule_expression = "{#{annot1.stable_id}}"
          formule.save(validate: false)
          expect(procedure.valid?(:types_de_champ_private_editor)).to be_truthy
        end

        it 'rejects references to following private annotations' do
          formule.formule_expression = "{#{annot2.stable_id}}"
          formule.save(validate: false)
          expect(procedure.valid?(:types_de_champ_private_editor)).to be_falsey
          expect(procedure.errors[:draft_types_de_champ_private]).to include(match(/Calcul.*Score/))
        end
      end
    end

    # pf: Tests for formula validations in repetitions
    describe 'Formula validations in repetitions' do
      let(:procedure) { create(:procedure, :published) }
      let(:revision) { procedure.active_revision }

      context 'formula in repetition' do
        let!(:parent) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Parent') }
        let!(:repetition) { procedure.draft_revision.add_type_de_champ(type_champ: :repetition, libelle: 'Bloc', after_stable_id: parent.stable_id) }
        let!(:sibling) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Sibling', parent_stable_id: repetition.stable_id) }
        let!(:formula) { procedure.draft_revision.add_type_de_champ(type_champ: :formule, libelle: 'Formule', parent_stable_id: repetition.stable_id, after_stable_id: sibling.stable_id) }
        let!(:following) { procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Suivant', parent_stable_id: repetition.stable_id, after_stable_id: formula.stable_id) }

        it 'accepts reference to sibling field (preceding position)' do
          formula.formule_expression = "{tdc#{sibling.stable_id}} * 2"
          formula.save(validate: false)

          expect(procedure.valid?(:types_de_champ_public_editor)).to be_truthy
        end

        it 'accepts reference to parent field (outside repetition)' do
          formula.formule_expression = "{tdc#{parent.stable_id}} * 2"
          formula.save(validate: false)

          expect(procedure.valid?(:types_de_champ_public_editor)).to be_truthy
        end

        it 'rejects reference to following sibling field' do
          formula.formule_expression = "{tdc#{following.stable_id}} * 2"
          formula.save(validate: false)

          expect(procedure.valid?(:types_de_champ_public_editor)).to be_falsey
          expect(procedure.errors[:draft_types_de_champ_public]).to include(match(/Formule.*ne peut référencer/))
        end

        it 'warns about collision between sibling and parent fields' do
          # Create a collision: parent and sibling with same name
          parent_prix = procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Prix')
          repetition_prix = procedure.draft_revision.add_type_de_champ(type_champ: :repetition, libelle: 'Produits', after_stable_id: parent_prix.stable_id)
          sibling_prix = procedure.draft_revision.add_type_de_champ(type_champ: :integer_number, libelle: 'Prix', parent_stable_id: repetition_prix.stable_id)
          formula_prix = procedure.draft_revision.add_type_de_champ(type_champ: :formule, libelle: 'Total', parent_stable_id: repetition_prix.stable_id, after_stable_id: sibling_prix.stable_id)

          formula_prix.formule_expression = "{tdc#{sibling_prix.stable_id}} * 2"
          formula_prix.save(validate: false)

          # Validation should pass despite collision (warning is not blocking)
          # Note: With FormulaValidator at Procedure level, warnings on individual TypeDeChamp
          # are not accessible after validation completes. This test verifies that the collision
          # doesn't block validation (i.e., it's treated as a warning, not an error).
          expect(procedure.valid?(:types_de_champ_public_editor)).to be_truthy
        end
      end
    end

    # pf: Tests for formule_deps['champs'] (replaces removed dependent_stable_ids)
    describe "formule_deps['champs']" do
      let(:formule_tdc) { build(:type_de_champ_formule) }

      def champs_for(tdc)
        tdc.valid?
        tdc.formule_deps&.[]('champs') || []
      end

      it 'extracts stable_ids from {tdc456} format' do
        formule_tdc.formule_expression = '{tdc456} + {tdc789}'

        expect(champs_for(formule_tdc)).to contain_exactly(456, 789)
      end

      it 'extracts stable_ids from {tdc456/path} format' do
        formule_tdc.formule_expression = '{tdc123/commune} + {tdc456/date_de_naissance}'

        expect(champs_for(formule_tdc)).to contain_exactly(123, 456)
      end

      it 'supports old format {123} (backward compatibility)' do
        formule_tdc.formule_expression = '{123} + {456}'

        expect(champs_for(formule_tdc)).to contain_exactly(123, 456)
      end

      it 'supports mixed format {123} + {tdc456}' do
        formule_tdc.formule_expression = '{123} + {tdc456}'

        expect(champs_for(formule_tdc)).to contain_exactly(123, 456)
      end

      it 'ignores system columns {dossier_number}' do
        formule_tdc.formule_expression = '{dossier_number} + {tdc456}'

        expect(champs_for(formule_tdc)).to contain_exactly(456)
      end

      it 'extracts from complex expressions with functions' do
        formule_tdc.formule_expression = 'SI({tdc123} > 10, SOMME({tdc456}, {tdc789}), 0)'

        expect(champs_for(formule_tdc)).to contain_exactly(123, 456, 789)
      end
    end
  end
end
