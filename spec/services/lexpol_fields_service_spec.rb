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
end
