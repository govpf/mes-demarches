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
  end
end
