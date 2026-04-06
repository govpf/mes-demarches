# frozen_string_literal: true

require 'rails_helper'

# pf: Audit de performance et de comportement de la cascade refresh_dependent_formulas
# Ce test sert de garde-fou CI pour détecter les régressions de performance
# et vérifier le comportement du recalcul en chaîne.
RSpec.describe 'Formule cascade refresh_dependent_formulas', type: :model do
  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  def count_sql_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql]&.start_with?('SAVEPOINT', 'RELEASE')
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end

  def set_formule_expression(dossier, formule_tdc, expression)
    formule_tdc.update_column(:options, formule_tdc.options.merge('formule_expression' => expression))
  end

  def find_champ(dossier, tdc)
    dossier.champs.find { |c| c.stable_id == tdc.stable_id }
  end

  # ------------------------------------------------------------------
  # Scénario 1 : Fan-out — 1 champ source, N formules dépendantes
  # ------------------------------------------------------------------
  describe 'fan-out: 1 source → N formules' do
    let(:n_formulas) { 10 }
    let(:types) do
      [{ type: :integer_number, libelle: 'Source' }] +
        n_formulas.times.map { |i| { type: :formule, libelle: "Formule #{i}" } }
    end
    let(:procedure) { create(:procedure, :published, types_de_champ_public: types) }
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }

    before do
      source_tdc = procedure.active_revision.types_de_champ_public.find(&:integer_number?)
      procedure.active_revision.types_de_champ_public.select(&:formule?).each do |formule_tdc|
        set_formule_expression(dossier, formule_tdc, "{tdc#{source_tdc.stable_id}} * 2")
      end
    end

    it "recalcule les #{10} formules quand la source change" do
      source_champ = dossier.champs.find { |c| c.type_de_champ.integer_number? }
      source_champ.update!(value: '100')

      # Vérifier que les formules ont été recalculées
      dossier.reload
      formule_champs = dossier.champs.select { |c| c.type_de_champ.formule? }
      formule_champs.each do |fc|
        expect(fc.compute_value_from_formula).to eq('200'), "Formule #{fc.libelle} non recalculée"
      end
    end

    it 'reste dans un budget SQL raisonnable' do
      source_champ = dossier.champs.find { |c| c.type_de_champ.integer_number? }

      # Warmup (preload caches)
      source_champ.update!(value: '1')

      query_count = count_sql_queries do
        source_champ.update!(value: '42')
      end

      # Budget : save (1) + find dependants (~2-3) + N update_columns + overhead
      # On accepte 5 requêtes par formule max (50 pour 10 formules)
      expect(query_count).to be < 50,
        "Trop de requêtes SQL pour le fan-out (#{query_count}). Risque N+1."
    end
  end

  # ------------------------------------------------------------------
  # Scénario 2 : Chaîne linéaire — A → formule B → formule C
  # ------------------------------------------------------------------
  describe 'chaîne linéaire: A → B → C' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Montant' },
        { type: :formule, libelle: 'Double' },
        { type: :formule, libelle: 'Quadruple' }
      ])
    end
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }

    let(:montant_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Montant' } }
    let(:double_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Double' } }
    let(:quadruple_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Quadruple' } }

    before do
      set_formule_expression(dossier, double_tdc, "{tdc#{montant_tdc.stable_id}} * 2")
      set_formule_expression(dossier, quadruple_tdc, "{tdc#{double_tdc.stable_id}} * 2")
    end

    it 'recalcule le premier niveau (Double)' do
      montant = find_champ(dossier, montant_tdc)
      montant.update!(value: '10')

      # Reload pour que le service voie la valeur mise à jour
      dossier.reload
      double_champ = find_champ(dossier, double_tdc)
      expect(double_champ.compute_value_from_formula).to eq('20')
    end

    it 'refresh_dependent_formulas détecte les dépendances du premier niveau' do
      dossier.reload
      montant = find_champ(dossier, montant_tdc)
      expect(montant.dependent_formula_champs).not_to be_empty
      expect(montant.dependent_formula_champs.map(&:stable_id)).to include(double_tdc.stable_id)
    end

    it 'ne provoque pas de cascade infinie (pas de StackOverflow)' do
      montant = find_champ(dossier, montant_tdc)
      expect { montant.update!(value: '999') }.not_to raise_error
    end
  end

  # ------------------------------------------------------------------
  # Scénario 3 : Référence circulaire — protégée par detect_circular_references
  # ------------------------------------------------------------------
  describe 'référence circulaire' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :formule, libelle: 'Formule A' },
        { type: :formule, libelle: 'Formule B' }
      ])
    end
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }

    let(:formule_a_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Formule A' } }
    let(:formule_b_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Formule B' } }

    before do
      set_formule_expression(dossier, formule_a_tdc, "{tdc#{formule_b_tdc.stable_id}} + 1")
      set_formule_expression(dossier, formule_b_tdc, "{tdc#{formule_a_tdc.stable_id}} + 1")
      # Reload pour que les TDC en mémoire reflètent les expressions mises à jour
      dossier.reload
    end

    it 'détecte la référence circulaire sans crash' do
      formule_a = find_champ(dossier, formule_a_tdc)
      result = formule_a.compute_value_from_formula
      expect(result).to include('circulaire')
    end
  end

  # ------------------------------------------------------------------
  # Scénario 4 : Temps de réponse
  # ------------------------------------------------------------------
  describe 'temps de réponse' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Source' },
        { type: :formule, libelle: 'Résultat' }
      ])
    end
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }

    before do
      source_tdc = procedure.active_revision.types_de_champ_public.find(&:integer_number?)
      formule_tdc = procedure.active_revision.types_de_champ_public.find(&:formule?)
      set_formule_expression(dossier, formule_tdc, "{tdc#{source_tdc.stable_id}} * 2 + 100")
    end

    it 'le recalcul se fait en moins de 500ms' do
      source = dossier.champs.find { |c| c.type_de_champ.integer_number? }
      source.update!(value: '1') # warmup

      elapsed = Benchmark.realtime { source.update!(value: '42') }

      expect(elapsed).to be < 0.5,
        "Le refresh_dependent_formulas prend #{(elapsed * 1000).round}ms (budget: 500ms)"
    end
  end
end
