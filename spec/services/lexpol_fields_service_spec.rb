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

    # pf: Lexpol ne manipule pas les datetime mais sait mettre en forme une
    # date reçue en jj/mm/aaaa. L'heure part dans une variable dédiée.
    context 'avec une date ou un datetime' do
      it 'ne transmet que la date pour un champ datetime' do
        champ = Champs::DatetimeChamp.new(value: '2026-04-01T00:03:00-10:00')
        expect(LexpolFieldsService.format_lexpol_value(champ)).to eq('01/04/2026')
      end

      it 'transmet une date de champ en jj/mm/aaaa' do
        champ = Champs::DateChamp.new(value: '2026-04-01')
        expect(LexpolFieldsService.format_lexpol_value(champ)).to eq('01/04/2026')
      end

      it "ne transmet que la date pour un horodatage système (colonne d'export)" do
        expect(LexpolFieldsService.format_lexpol_value(Time.zone.local(2026, 4, 1, 0, 3))).to eq('01/04/2026')
      end

      it 'retourne une chaîne vide pour une valeur absente' do
        expect(LexpolFieldsService.format_lexpol_value(Champs::DatetimeChamp.new(value: nil))).to eq('')
      end
    end
  end

  describe '.format_heure' do
    it "extrait l'heure d'un champ datetime" do
      champ = Champs::DatetimeChamp.new(value: '2026-04-01T14:30:00-10:00')
      expect(LexpolFieldsService.format_heure(champ.value)).to eq('14:30')
    end

    it "extrait l'heure d'un horodatage système dans le fuseau de l'application" do
      expect(LexpolFieldsService.format_heure(Time.zone.local(2026, 4, 1, 0, 3))).to eq('00:03')
    end

    it 'retourne une chaîne vide pour une valeur absente' do
      expect(LexpolFieldsService.format_heure(nil)).to eq('')
      expect(LexpolFieldsService.format_heure('')).to eq('')
    end

    it 'retourne une chaîne vide pour une valeur non parsable' do
      expect(LexpolFieldsService.format_heure('pas une date')).to eq('')
    end
  end

  # pf: contexte d'affichage — le rendu est inséré tel quel dans le document,
  # Lexpol ne le manipule pas, le formatage doit donc être fait ici.
  describe '.format_lexpol_display' do
    it 'rend un datetime en toutes lettres, heure comprise' do
      champ = Champs::DatetimeChamp.new(value: '2026-04-01T14:30:00-10:00')
      expect(LexpolFieldsService.format_lexpol_display(champ)).to eq('1er avril 2026 à 14:30')
    end

    it 'rend une date en toutes lettres' do
      champ = Champs::DateChamp.new(value: '2026-04-12')
      expect(LexpolFieldsService.format_lexpol_display(champ)).to eq('12 avril 2026')
    end

    it 'groupe les milliers des grands nombres' do
      champ = Champs::IntegerNumberChamp.new(value: '100000')
      expect(LexpolFieldsService.format_lexpol_display(champ)).to eq("100 000")
    end

    it 'ne groupe pas les nombres à quatre chiffres, pour ne pas casser les années' do
      champ = Champs::IntegerNumberChamp.new(value: '2026')
      expect(LexpolFieldsService.format_lexpol_display(champ)).to eq('2026')
    end

    it 'utilise la virgule décimale' do
      champ = Champs::DecimalNumberChamp.new(value: '20.5')
      expect(LexpolFieldsService.format_lexpol_display(champ)).to eq('20,5')

      grand = Champs::DecimalNumberChamp.new(value: '12500.75')
      expect(LexpolFieldsService.format_lexpol_display(grand)).to eq("12 500,75")
    end

    it 'délègue à format_lexpol_value pour les types que Lexpol ne manipule pas' do
      champ = Champs::TextChamp.new(value: 'Un texte')
      expect(LexpolFieldsService.format_lexpol_display(champ)).to eq('Un texte')
    end
  end

  describe '.format_repetition_champ' do
    let(:champ_datetime) do
      champ = Champs::DatetimeChamp.new(value: '2026-04-01T14:30:00-10:00')
      allow(champ).to receive(:type_de_champ).and_return(double(libelle: 'Créneau'))
      champ
    end

    let(:champ_montant) do
      champ = Champs::IntegerNumberChamp.new(value: '100000')
      allow(champ).to receive(:type_de_champ).and_return(double(libelle: 'Montant'))
      champ
    end

    let(:repetition) { instance_double(Champs::RepetitionChamp, rows: [[champ_datetime, champ_montant]]) }

    # pf: une cellule de tableau est un rendu, pas une donnée : l'heure n'a pas
    # de variable de repli à ce niveau, elle doit rester dans la cellule.
    it "conserve l'heure d'un datetime dans une cellule" do
      expect(LexpolFieldsService.format_repetition_champ(repetition)).to include('1er avril 2026 à 14:30')
    end

    it 'met les nombres en typographie française dans une cellule' do
      expect(LexpolFieldsService.format_repetition_champ(repetition)).to include("100 000")
    end
  end
end
