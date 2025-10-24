# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LexpolService do
  let(:procedure) { create(:procedure, :published, types_de_champ_public: [{ type: :text, libelle: 'Nom' }, { type: :multiple_drop_down_list, libelle: 'Catégories', drop_down_options: ['Option A', 'Option B', 'Option C'] }, { type: :lexpol }]) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:lexpol_type_de_champ) { procedure.active_revision.types_de_champ.find { |tdc| tdc.type_champ == 'lexpol' } }
  let(:text_champ) { dossier.champs.find { |c| c.libelle == 'Nom' } }
  let(:multiple_drop_down_champ) { dossier.champs.find { |c| c.libelle == 'Catégories' } }
  let(:lexpol_champ) { dossier.champs.find { |c| c.type_champ == 'lexpol' } }
  let(:apilexpol) { instance_double(APILexpolService) }
  let(:service) { LexpolService.new(champ: lexpol_champ, dossier: dossier, apilexpol: apilexpol) }

  describe '#build_variables' do
    before do
      text_champ.update!(value: 'Jean Dupont')
      multiple_drop_down_champ.update!(value: '["Option A","Option B","Option C"]')
    end

    it 'génère la variable standard pour un champ texte' do
      variables = service.build_variables
      expect(variables['Nom']).to eq('Jean Dupont')
    end

    it 'génère la variable standard pour un champ MultipleDropDownList' do
      variables = service.build_variables
      expect(variables['Catégories']).to eq('Option A, Option B et Option C')
    end

    it 'génère la variable avec suffixe (liste) pour un champ MultipleDropDownList' do
      variables = service.build_variables
      expect(variables['Catégories (liste)']).to eq('<ul><li>Option A ;</li><li>Option B ;</li><li>Option C.</li></ul>')
    end

    it 'ne génère pas la variable (liste) pour un champ MultipleDropDownList vide' do
      multiple_drop_down_champ.update!(value: '[]')
      variables = service.build_variables
      expect(variables).not_to have_key('Catégories (liste)')
    end

    it 'ne génère pas la variable (liste) pour un champ non MultipleDropDownList' do
      variables = service.build_variables
      expect(variables).not_to have_key('Nom (liste)')
    end
  end

  describe '.lexpol_variables' do
    it 'inclut les variables de champs standards' do
      variables = LexpolService.lexpol_variables(lexpol_type_de_champ, procedure)
      expect(variables).to include('Nom')
      expect(variables).to include('Catégories')
    end

    it 'inclut la variable (liste) pour les champs MultipleDropDownList' do
      variables = LexpolService.lexpol_variables(lexpol_type_de_champ, procedure)
      expect(variables).to include('Catégories (liste)')
    end

    it 'n\'inclut pas la variable (liste) pour les champs non MultipleDropDownList' do
      variables = LexpolService.lexpol_variables(lexpol_type_de_champ, procedure)
      # Vérifier qu'il n'y a pas de variable "Nom (liste)"
      expect(variables.select { |v| v.include?('Nom (liste)') }).to be_empty
    end
  end
end
