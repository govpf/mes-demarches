# frozen_string_literal: true

describe Champs::ReferentielDePolynesieChamp, type: :model do
  let(:table_id) { '24' }
  let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, table_id: }] }
  let(:procedure) { create(:procedure, types_de_champ_public:) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.project_champs_public.first }

  # ─── Flux inline autocomplete Baserow (Phase 2) ───────────────────────────

  describe '#referentiel?' do
    it 'retourne true (pour être traité comme un referentiel upstream)' do
      expect(champ.referentiel?).to be true
    end

    it 'active le flux inline dans update_dossier_and_compute_errors' do
      # La méthode dossiers_controller#update_dossier_and_compute_errors ajoute :data
      # aux champ_attributes uniquement si champ.referentiel? && champ.autocomplete?
      expect(champ).to respond_to(:referentiel?)
    end
  end

  describe '#uses_external_data?' do
    context 'en mode autocomplete (inline — pas de job)' do
      let(:referentiel) { create(:baserow_referentiel, :autocomplete) }
      let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }

      it 'retourne false (le job ne doit pas se lancer)' do
        expect(champ.uses_external_data?).to be false
      end
    end

    context 'en mode exact_match (job asynchrone)' do
      let(:referentiel) { create(:baserow_referentiel, :exact_match) }
      let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }

      it 'retourne true (le job doit se lancer)' do
        expect(champ.uses_external_data?).to be true
      end
    end
  end

  describe '#autocomplete?' do
    context 'sans référentiel lié' do
      it 'retourne false (nil-safe)' do
        expect(champ.autocomplete?).to be_falsey
      end
    end

    context 'avec un référentiel autocomplete' do
      let(:referentiel) { create(:baserow_referentiel, :autocomplete) }
      let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }

      it 'retourne true' do
        expect(champ.autocomplete?).to be true
      end
    end

    context 'avec un référentiel exact_match' do
      let(:referentiel) { create(:baserow_referentiel, :exact_match) }
      let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }

      it 'retourne false' do
        expect(champ.autocomplete?).to be false
      end
    end
  end

  describe '#data= (flux inline)' do
    let(:encryptor) { MessageEncryptorService.new }
    let(:row_data) { { 'Nom' => 'Papeete', 'Code' => '98714' } }

    context 'en mode autocomplete avec blob chiffré valide' do
      let(:referentiel) { create(:baserow_referentiel, :autocomplete) }
      let(:types_de_champ_public) do
        [
          {
            type: :referentiel_de_polynesie,
            referentiel:,
            referentiel_mapping: {
              '$.Nom' => { 'type' => 'string', 'libelle' => 'Nom', 'display_usager' => '1' }
            }
          }
        ]
      end
      let(:encrypted_blob) { encryptor.encrypt_and_sign(row_data.to_json, purpose: :storage, expires_in: 1.hour) }

      it 'déchiffre le blob et stocke les données en hash' do
        champ.data = encrypted_blob
        expect(champ.data).to eq(row_data)
      end

      it 'positionne @inline_data_present à true' do
        champ.data = encrypted_blob
        expect(champ.instance_variable_get(:@inline_data_present)).to be true
      end

      it 'calcule value_json pour que ReferentielDisplayComponent affiche les colonnes displayable' do
        champ.data = encrypted_blob
        expect(champ.value_json).to eq({ '$.Nom' => 'Papeete' })
      end

      it 'persiste value_json au save (rechargement de page)' do
        champ.data = encrypted_blob
        champ.external_id = '24:1'
        champ.value = 'Papeete'
        champ.save!
        expect(champ.reload.value_json).to eq({ '$.Nom' => 'Papeete' })
      end
    end

    context 'en mode autocomplete avec blob chiffré invalide' do
      let(:referentiel) { create(:baserow_referentiel, :autocomplete) }
      let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }

      it 'stocke la valeur brute sans lever d\'exception' do
        expect { champ.data = 'blob_invalide' }.not_to raise_error
        expect(champ.data).to eq('blob_invalide')
      end

      it 'ne positionne pas @inline_data_present' do
        champ.data = 'blob_invalide'
        expect(champ.instance_variable_get(:@inline_data_present)).to be_nil
      end
    end

    context 'en mode exact_match (pas de déchiffrement)' do
      let(:referentiel) { create(:baserow_referentiel, :exact_match) }
      let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }

      it 'stocke la valeur telle quelle (hash direct)' do
        champ.data = row_data
        expect(champ.data).to eq(row_data)
      end

      it 'ne positionne pas @inline_data_present' do
        champ.data = row_data
        expect(champ.instance_variable_get(:@inline_data_present)).to be_nil
      end
    end

    context 'sans référentiel (mode legacy)' do
      it 'stocke la valeur telle quelle' do
        champ.data = row_data
        expect(champ.data).to eq(row_data)
      end
    end
  end

  describe '#clear_previous_result' do
    let(:referentiel) { create(:baserow_referentiel, :autocomplete) }
    let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }

    before { champ.update!(data: { 'Nom' => 'Papeete' }, value_json: { '$.Nom' => 'Papeete' }) }

    context 'quand @inline_data_present est true (données inline venant de data=)' do
      before { champ.instance_variable_set(:@inline_data_present, true) }

      it 'ne wipe pas les données' do
        champ.send(:clear_previous_result)
        expect(champ.data).to be_present
        expect(champ.value_json).to be_present
      end
    end

    context 'quand c\'est un new_record avec data présente (fork/deep_clone)' do
      it 'ne wipe pas les données' do
        new_champ = champ.dup
        new_champ.data = { 'Nom' => 'Papeete' }
        expect(new_champ).to be_new_record
        new_champ.send(:clear_previous_result)
        expect(new_champ.data).to be_present
      end
    end

    context 'dans le cas normal (record existant, pas d\'inline data)' do
      it 'wipe data, value_json et fetch_external_data_exceptions' do
        champ.send(:clear_previous_result)
        expect(champ.data).to be_nil
        expect(champ.value_json).to be_nil
        expect(champ.fetch_external_data_exceptions).to eq([])
      end
    end
  end

  describe 'flux inline autocomplete — propagate_prefill dans data= + reset flag après save' do
    let(:encryptor) { MessageEncryptorService.new }
    let(:row_data) { { 'Nom' => 'Papeete', 'Code' => '98714', 'Ile' => 'Tahiti' } }
    let(:prefillable_stable_id) { 999 }
    let(:referentiel) { create(:baserow_referentiel, :autocomplete) }

    context 'réinitialisation du flag après save' do
      let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, referentiel: }] }
      let(:encrypted_blob) { encryptor.encrypt_and_sign(row_data.to_json, purpose: :storage, expires_in: 1.hour) }

      it 'réinitialise @inline_data_present à false après save' do
        champ.data = encrypted_blob
        champ.external_id = '24:1'
        champ.value = 'Papeete'
        champ.save!

        expect(champ.instance_variable_get(:@inline_data_present)).to be false
      end
    end

    context 'avec préfillage (propagate_prefill appelé dans data=)' do
      let(:types_de_champ_public) do
        [
          {
            type: :referentiel_de_polynesie,
            referentiel:,
            referentiel_mapping: {
              '$.Code' => { 'prefill' => '1', 'prefill_stable_id' => prefillable_stable_id.to_s }
            }
          },
          { type: :text, libelle: 'Code pré-rempli', stable_id: prefillable_stable_id }
        ]
      end

      let(:text_champ) { dossier.project_champs_public.find { |c| c.stable_id == prefillable_stable_id } }
      let(:encrypted_blob) { encryptor.encrypt_and_sign(row_data.to_json, purpose: :storage, expires_in: 1.hour) }

      it 'pré-remplit instantanément les champs liés dès data= (avant le save)' do
        # propagate_prefill est appelé dans data=, pas dans after_save
        champ.data = encrypted_blob

        expect(text_champ.reload.value).to eq('98714')
        expect(text_champ.reload.prefilled).to be true
      end
    end
  end

  describe '#fetch_external_data' do
    let(:external_id) { '24:123' }

    context 'when API returns valid data' do
      let(:api_response) do
        { 'Nom' => 'Papeete', 'Archipel' => 'Îles du Vent', 'Code' => '98714' }
      end

      before do
        allow(ReferentielDePolynesie::API).to receive(:fetch_row)
          .with(external_id)
          .and_return(api_response)
        champ.update!(external_id:)
      end

      it 'returns a Success monad with flat data' do
        result = champ.fetch_external_data

        expect(result).to be_success
        expect(result.value!).to eq(api_response.with_indifferent_access)
      end
    end

    context 'when API returns nil' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:fetch_row)
          .with(external_id)
          .and_return(nil)
        champ.update!(external_id:)
      end

      it 'returns a Failure monad with code 404' do
        result = champ.fetch_external_data

        expect(result).to be_failure
        expect(result.failure).to include(code: 404, retryable: false)
      end
    end

    context 'when API raises an exception' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:fetch_row)
          .with(external_id)
          .and_raise(StandardError, 'Connection error')
        champ.update!(external_id:)
      end

      it 'returns a Failure monad with code 500' do
        result = champ.fetch_external_data

        expect(result).to be_failure
        expect(result.failure).to include(code: 500, retryable: false)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/ReferentielDePolynesieChamp fetch error.*Connection error/)
        champ.fetch_external_data
      end
    end
  end

  describe '#selected' do
    it 'returns external_id' do
      champ.external_id = '24:456'
      expect(champ.selected).to eq('24:456')
    end
  end

  describe '#selected_items' do
    context 'when external_id and value are present' do
      before do
        champ.external_id = '24:123'
        champ.value = 'Papeete'
      end

      it 'returns array with label and value' do
        expect(champ.selected_items).to eq([{ label: 'Papeete', value: '24:123' }])
      end
    end

    context 'when external_id is blank' do
      before do
        champ.external_id = nil
        champ.value = 'Papeete'
      end

      it 'returns empty array' do
        expect(champ.selected_items).to eq([])
      end
    end

    context 'when value is blank' do
      before do
        champ.external_id = '24:123'
        champ.value = nil
      end

      it 'returns empty array' do
        expect(champ.selected_items).to eq([])
      end
    end
  end

  describe '#referentiel_item_value' do
    context 'with new flat format' do
      before do
        champ.update!(data: { 'Nom' => 'Papeete', 'Code' => '98714' })
      end

      it 'extracts value by path' do
        expect(champ.referentiel_item_value('Nom')).to eq('Papeete')
        expect(champ.referentiel_item_value('Code')).to eq('98714')
      end

      it 'returns nil for non-existent paths' do
        expect(champ.referentiel_item_value('Inexistant')).to be_nil
      end
    end

    context 'with legacy row format' do
      before do
        champ.update!(data: {
          'row' => { 'Nom' => 'Papeete', 'Code' => '98714' }
        })
      end

      it 'extracts value from row by path' do
        expect(champ.referentiel_item_value('Nom')).to eq('Papeete')
        expect(champ.referentiel_item_value('Code')).to eq('98714')
      end
    end

    context 'when data is nil' do
      before { champ.update!(data: nil) }

      it 'returns nil' do
        expect(champ.referentiel_item_value('Nom')).to be_nil
      end
    end
  end

  describe '#focusable_input_id' do
    it 'returns html_id without suffix' do
      expect(champ.focusable_input_id).to eq(champ.html_id)
    end
  end

  describe 'inheritance from ReferentielChamp' do
    it 'inherits from Champs::ReferentielChamp' do
      expect(described_class.ancestors).to include(Champs::ReferentielChamp)
    end
  end

  describe 'pré-remplissage (propagate_prefill)' do
    include ActiveJob::TestHelper

    let(:prefillable_stable_id) { 999 }
    let(:types_de_champ_public) do
      [
        {
          type: :referentiel_de_polynesie,
          libelle: 'Référentiel',
          table_id: '24',
          referentiel_mapping: {
            '$.Code' => { 'prefill' => '1', 'prefill_stable_id' => prefillable_stable_id.to_s }
          }
        },
        { type: :text, libelle: 'Code pré-rempli', stable_id: prefillable_stable_id }
      ]
    end

    let(:referentiel_champ) { dossier.project_champs_public.find(&:referentiel_de_polynesie?) }
    let(:text_champ) { dossier.project_champs_public.find { |c| c.stable_id == prefillable_stable_id } }
    let(:baserow_row_data) do
      { 'Nom' => 'Papeete', 'Code' => '98714', 'Ile' => 'Tahiti' }
    end

    before do
      allow(ReferentielDePolynesie::API).to receive(:fetch_row)
        .with('24:123')
        .and_return(baserow_row_data)
    end

    it 'pré-remplit le champ texte quand le job ChampFetchExternalDataJob est exécuté' do
      referentiel_champ.update!(external_id: '24:123', value: 'Papeete - Tahiti')

      expect(text_champ.reload.value).to be_nil

      ChampFetchExternalDataJob.perform_now(referentiel_champ, '24:123')

      expect(text_champ.reload.value).to eq('98714')
      expect(text_champ.prefilled).to be true
    end

    it 'conserve le label dans value après le fetch' do
      referentiel_champ.update!(external_id: '24:123', value: 'Papeete - Tahiti')

      ChampFetchExternalDataJob.perform_now(referentiel_champ, '24:123')

      # pf: value doit conserver le label (pas être remplacé par external_id comme upstream)
      expect(referentiel_champ.reload.value).to eq('Papeete - Tahiti')
      expect(referentiel_champ.data).to be_present
    end

    it 'stocke les données brutes de l\'API en format plat dans data' do
      referentiel_champ.update!(external_id: '24:123', value: 'Papeete - Tahiti')

      ChampFetchExternalDataJob.perform_now(referentiel_champ, '24:123')

      expect(referentiel_champ.reload.data).to include('Nom' => 'Papeete', 'Code' => '98714')
    end

    context 'avec un mapping displayable' do
      let(:types_de_champ_public) do
        [
          {
            type: :referentiel_de_polynesie,
            libelle: 'Référentiel',
            table_id: '24',
            referentiel_mapping: {
              '$.Code' => { 'prefill' => '1', 'prefill_stable_id' => prefillable_stable_id.to_s },
              '$.Nom' => { 'type' => 'string', 'libelle' => 'Nom', 'display_instructeur' => '1' }
            }
          },
          { type: :text, libelle: 'Code pré-rempli', stable_id: prefillable_stable_id }
        ]
      end

      it 'calcule value_json via cast_displayable_values' do
        referentiel_champ.update!(external_id: '24:123', value: 'Papeete - Tahiti')

        ChampFetchExternalDataJob.perform_now(referentiel_champ, '24:123')

        expect(referentiel_champ.reload.value_json).to be_present
        expect(referentiel_champ.value_json['$.Nom']).to eq('Papeete')
      end
    end

    context 'avec erreur API' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:fetch_row)
          .with('24:999')
          .and_return(nil)
      end

      it 'gère gracieusement les erreurs API sans pré-remplir' do
        referentiel_champ.update!(external_id: '24:999', value: 'Entrée invalide')

        expect {
          ChampFetchExternalDataJob.perform_now(referentiel_champ, '24:999')
        }.not_to raise_error

        expect(text_champ.reload.value).to be_nil
      end
    end

    context 'avec plusieurs champs à pré-remplir' do
      let(:second_prefillable_stable_id) { 998 }
      let(:types_de_champ_public) do
        [
          {
            type: :referentiel_de_polynesie,
            libelle: 'Référentiel',
            table_id: '24',
            referentiel_mapping: {
              '$.Code' => { 'prefill' => '1', 'prefill_stable_id' => prefillable_stable_id.to_s },
              '$.Nom' => { 'prefill' => '1', 'prefill_stable_id' => second_prefillable_stable_id.to_s }
            }
          },
          { type: :text, libelle: 'Code pré-rempli', stable_id: prefillable_stable_id },
          { type: :text, libelle: 'Nom pré-rempli', stable_id: second_prefillable_stable_id }
        ]
      end

      let(:second_text_champ) { dossier.project_champs_public.find { |c| c.stable_id == second_prefillable_stable_id } }

      it 'pré-remplit plusieurs champs en une seule opération' do
        referentiel_champ.update!(external_id: '24:123', value: 'Papeete - Tahiti')

        ChampFetchExternalDataJob.perform_now(referentiel_champ, '24:123')

        expect(text_champ.reload.value).to eq('98714')
        expect(second_text_champ.reload.value).to eq('Papeete')
      end
    end
  end
end
