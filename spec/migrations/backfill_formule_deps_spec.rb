# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260522174323_backfill_formule_deps')

# pf: Spec pour la migration de backfill formule_deps.
# La migration calcule les dépendances des formules en inline (regex), sans
# passer par le layer applicatif, ce qui la rend indépendante de l'ordre de
# déploiement entre l'étape D (ajout de la clé dans le whitelist options) et
# l'étape E (ce backfill).
RSpec.describe BackfillFormuleDeps do
  let(:migration) { described_class.new }

  # Crée un TDC formule avec l'expression donnée, en forçant les options via
  # update_column pour bypasser les callbacks et valider le comportement de la
  # migration sur des données brutes (simule des TDC pré-étape-D).
  def create_formule_tdc_with_expression(expression)
    tdc = create(:type_de_champ_formule)
    raw_opts = (tdc.options || {}).merge('formule_expression' => expression)
    raw_opts.delete('formule_deps')
    tdc.update_column(:options, raw_opts)
    tdc
  end

  def run_migration_and_reload(tdc)
    migration.up
    tdc.reload
    tdc
  end

  describe '#up — backfill de formule_deps' do
    context 'avec une expression référençant des TDC et une fonction horloge' do
      # Ex: {tdc42} + AGE({tdc7}) — AGE est dans CLOCK_PATTERN
      let(:tdc) { create_formule_tdc_with_expression('{tdc42} + AGE({tdc7})') }

      before { run_migration_and_reload(tdc) }

      it 'calcule les champs référencés triés' do
        expect(tdc.options['formule_deps']['champs']).to eq([7, 42])
      end

      it 'marque has_clock = true' do
        expect(tdc.options['formule_deps']['has_clock']).to be(true)
      end

      it 'ne marque pas has_state ni has_identite' do
        expect(tdc.options['formule_deps']['has_state']).to be_nil
        expect(tdc.options['formule_deps']['has_identite']).to be_nil
      end
    end

    context "avec une expression référençant l'identité individuelle" do
      let(:tdc) { create_formule_tdc_with_expression('{individual_last_name}') }

      before { run_migration_and_reload(tdc) }

      it 'marque has_identite = true' do
        expect(tdc.options['formule_deps']['has_identite']).to be(true)
      end

      it 'a champs vide' do
        expect(tdc.options['formule_deps']['champs']).to eq([])
      end

      it 'ne marque pas has_state ni has_clock' do
        expect(tdc.options['formule_deps']['has_state']).to be_nil
        expect(tdc.options['formule_deps']['has_clock']).to be_nil
      end
    end

    context 'avec une expression référençant la date de dépôt du dossier' do
      let(:tdc) { create_formule_tdc_with_expression('{dossier_depose_at}') }

      before { run_migration_and_reload(tdc) }

      it 'marque has_state = true' do
        expect(tdc.options['formule_deps']['has_state']).to be(true)
      end

      it 'a champs vide' do
        expect(tdc.options['formule_deps']['champs']).to eq([])
      end

      it 'ne marque pas has_clock ni has_identite' do
        expect(tdc.options['formule_deps']['has_clock']).to be_nil
        expect(tdc.options['formule_deps']['has_identite']).to be_nil
      end
    end

    context 'avec une expression vide (blank)' do
      let(:tdc) { create_formule_tdc_with_expression('') }

      before { run_migration_and_reload(tdc) }

      it 'crée formule_deps avec champs vide et aucun flag' do
        expect(tdc.options['formule_deps']).to eq({ 'champs' => [] })
      end
    end

    context 'avec un TDC dont formule_deps est déjà renseigné (ex: étape D)' do
      # Simule un TDC déjà traité par l'étape D avec des valeurs potentiellement
      # différentes (ex: AST vs regex). La migration doit réécrire avec les valeurs regex.
      # Trade-off documenté : regex peut légèrement différer de l'AST (ex: faux positif
      # has_clock pour un AGE dans un littéral string), mais c'est corrigé à la prochaine
      # sauvegarde du TDC via validate_expression.
      let(:tdc) do
        tdc = create(:type_de_champ_formule)
        existing_deps = { 'champs' => [99], 'has_clock' => false }
        raw_opts = (tdc.options || {}).merge(
          'formule_expression' => '{tdc7}',
          'formule_deps' => existing_deps
        )
        tdc.update_column(:options, raw_opts)
        tdc
      end

      before { run_migration_and_reload(tdc) }

      it 'écrase formule_deps avec la valeur recalculée par regex' do
        deps = tdc.options['formule_deps']
        expect(deps['champs']).to eq([7])
      end

      it 'supprime has_clock si absent de la nouvelle expression' do
        # L'ancienne valeur avait has_clock: false, la nouvelle (regex sur {tdc7}) ne l'a pas
        expect(tdc.options['formule_deps'].key?('has_clock')).to be(false)
      end
    end

    context 'avec plusieurs TDC stable_ids — tri et déduplication' do
      let(:tdc) { create_formule_tdc_with_expression('{tdc100} + {tdc5} * {tdc100} - {tdc12}') }

      before { run_migration_and_reload(tdc) }

      it 'déduplique et trie les stable_ids' do
        expect(tdc.options['formule_deps']['champs']).to eq([5, 12, 100])
      end
    end

    context 'avec AUJOURDHUI() — autre fonction horloge' do
      let(:tdc) { create_formule_tdc_with_expression('AUJOURDHUI()') }

      before { run_migration_and_reload(tdc) }

      it 'marque has_clock = true' do
        expect(tdc.options['formule_deps']['has_clock']).to be(true)
      end
    end

    context 'avec une expression référençant une entreprise' do
      let(:tdc) { create_formule_tdc_with_expression('{entreprise_nom}') }

      before { run_migration_and_reload(tdc) }

      it 'marque has_identite = true' do
        expect(tdc.options['formule_deps']['has_identite']).to be(true)
      end
    end

    context 'avec formule_expression absente des options' do
      let(:tdc) do
        tdc = create(:type_de_champ_formule)
        raw_opts = (tdc.options || {})
        raw_opts.delete('formule_expression')
        raw_opts.delete('formule_deps')
        tdc.update_column(:options, raw_opts)
        tdc
      end

      before { run_migration_and_reload(tdc) }

      it 'crée formule_deps avec champs vide' do
        expect(tdc.options['formule_deps']).to eq({ 'champs' => [] })
      end
    end

    context "n'affecte pas les TDC d'autres types" do
      let!(:texte_tdc) { create(:type_de_champ_text) }
      let!(:formule_tdc) { create_formule_tdc_with_expression('{tdc1}') }

      before { migration.up }

      it 'ne touche pas le TDC texte' do
        expect(texte_tdc.reload.options).not_to have_key('formule_deps')
      end

      it 'backfille bien le TDC formule' do
        expect(formule_tdc.reload.options['formule_deps']).to be_present
      end
    end
  end

  describe 'survivabilité via TypeDeChamp#clean_options' do
    it 'formule_deps est conservé après clean_options (whitelist INSTANCE_OPTIONS_BY_TYPE)' do
      tdc = create_formule_tdc_with_expression('{tdc42}')
      described_class.new.up
      tdc.reload

      expect(tdc.options['formule_deps']).to be_present
      expect(tdc.clean_options['formule_deps']).to eq(tdc.options['formule_deps'])
    end
  end

  describe '#down' do
    it 'lève IrreversibleMigration' do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
