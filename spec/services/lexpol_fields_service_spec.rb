# frozen_string_literal: true

describe LexpolFieldsService do
  describe '.format_as_html_list' do
    it 'formate une liste avec ponctuation Lexpol' do
      options = ['A', 'B', 'C']
      result = LexpolFieldsService.format_as_html_list(options)
      expect(result).to eq('<ul><li>A ;</li><li>B ;</li><li>C.</li></ul>')
    end

    it 'retourne une chaîne vide si options vide' do
      expect(LexpolFieldsService.format_as_html_list([])).to eq('')
    end

    it 'retourne une chaîne vide si options nil' do
      expect(LexpolFieldsService.format_as_html_list(nil)).to eq('')
    end

    it 'gère un seul élément avec un point final' do
      result = LexpolFieldsService.format_as_html_list(['Seul'])
      expect(result).to eq('<ul><li>Seul.</li></ul>')
    end

    it 'gère deux éléments correctement' do
      result = LexpolFieldsService.format_as_html_list(['Premier', 'Dernier'])
      expect(result).to eq('<ul><li>Premier ;</li><li>Dernier.</li></ul>')
    end

    it 'échappe les caractères HTML dangereux' do
      options = ['Option <script>alert("XSS")</script>', 'A & B', '"Quotes"', "L'apostrophe"]
      result = LexpolFieldsService.format_as_html_list(options)

      # Vérifie que les caractères dangereux sont échappés
      expect(result).not_to include('<script>')
      expect(result).to include('&lt;script&gt;')
      expect(result).to include('&amp;')
      expect(result).to include('&quot;')

      # Vérifie la structure complète
      expect(result).to eq('<ul><li>Option &lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt; ;</li><li>A &amp; B ;</li><li>&quot;Quotes&quot; ;</li><li>L&#39;apostrophe.</li></ul>')
    end
  end

  describe '.object_field_values' do
    let(:procedure) { create(:procedure, :published) }
    let(:dossier) { create(:dossier, procedure: procedure) }

    it "utilise project_champs sur un dossier plutot que champ pour éviter les champs orphelins" do
      expect(dossier).to receive(:project_champs_public).and_return([])
      expect(dossier).to receive(:project_champs_private).and_return([])
      expect(dossier).not_to receive(:champs)
      expect(dossier).not_to receive(:annotations)

      LexpolFieldsService.object_field_values(dossier, 'un_champ')
    end
  end

  describe '.format_lexpol_value' do
    it 'retourne 0 si un champ IntegerNumberChamp ou DecimalNumberChamp est vide' do
      champ1 = Champs::IntegerNumberChamp.new(value: '')
      champ2 = Champs::DecimalNumberChamp.new(value: '')
      expect(LexpolFieldsService.format_lexpol_value(champ1)).to eq("0")
      expect(LexpolFieldsService.format_lexpol_value(champ2)).to eq("0")
    end

    it 'retourne la valeur saisie si un champ IntegerNumberChamp ou DecimalNumberChamp est rempli' do
      champ1 = Champs::IntegerNumberChamp.new(value: '20')
      champ2 = Champs::DecimalNumberChamp.new(value: '20.5')
      expect(LexpolFieldsService.format_lexpol_value(champ1)).to eq('20')
      expect(LexpolFieldsService.format_lexpol_value(champ2)).to eq('20.5')
    end

    it 'retourne 0 si un champ IntegerNumberChamp ou DecimalNumberChamp est nil' do
      champ1 = Champs::IntegerNumberChamp.new(value: nil)
      champ2 = Champs::DecimalNumberChamp.new(value: nil)
      expect(LexpolFieldsService.format_lexpol_value(champ1)).to eq("0")
      expect(LexpolFieldsService.format_lexpol_value(champ2)).to eq("0")
    end

    it 'retourne 0 si la valeur saisie est 0' do
      champ1 = Champs::IntegerNumberChamp.new(value: '0')
      champ2 = Champs::DecimalNumberChamp.new(value: '0')
      expect(LexpolFieldsService.format_lexpol_value(champ1)).to eq('0')
      expect(LexpolFieldsService.format_lexpol_value(champ2)).to eq('0')
    end
  end
end
