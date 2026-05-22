# frozen_string_literal: true

describe FormulaValueDisplayComponent, type: :component do
  subject { render_inline(described_class.new(champ: champ)) }

  let(:type_de_champ) { build(:type_de_champ_formule, formule_output_type: output_type) }
  let(:champ) { instance_double(Champs::FormuleChamp, value: value, type_de_champ: type_de_champ) }
  let(:output_type) { nil }
  let(:value) { nil }

  context 'with output_type "string"' do
    let(:output_type) { 'string' }

    context 'and a value that starts with an ISO date prefix' do
      # pf: bug d'origine — "2026-06-08CAP-19297/288" était parsé comme date
      # par le sniffing regex et rendu dans une balise <time>.
      let(:value) { '2026-06-08CAP-19297/288' }

      it 'renders the raw text without a <time> tag' do
        subject
        expect(page).to have_text('2026-06-08CAP-19297/288')
        expect(page).not_to have_selector('time')
      end
    end

    context 'and a value that looks numeric' do
      let(:value) { '195/1' }

      it 'renders the raw text without number formatting' do
        subject
        expect(page).to have_text('195/1')
      end
    end
  end

  context 'with output_type "date"' do
    let(:output_type) { 'date' }
    let(:value) { '2026-06-08' }

    it 'renders a <time> tag with ISO datetime' do
      subject
      expect(page).to have_selector('time[datetime="2026-06-08"]')
    end
  end

  context 'with output_type "datetime"' do
    let(:output_type) { 'datetime' }
    let(:value) { '2026-06-08T15:40:00+02:00' }

    it 'renders a <time> tag' do
      subject
      expect(page).to have_selector('time')
    end
  end

  context 'with output_type "number"' do
    let(:output_type) { 'number' }

    context 'with a Rational-like string "195/1"' do
      let(:value) { '195/1' }

      it 'renders 195 (no Rational artefact)' do
        subject
        expect(page).to have_text('195')
        expect(page).not_to have_text('195/1')
      end
    end

    context 'with a decimal string' do
      let(:value) { '12.50' }

      it 'renders with French formatting' do
        subject
        expect(page).to have_text('12,5')
      end
    end

    context 'with an integer string' do
      let(:value) { '1234' }

      it 'renders with thousand delimiter' do
        subject
        expect(page).to have_text(number_with_delimiter(1234))
      end
    end
  end

  context 'with output_type "boolean"' do
    let(:output_type) { 'boolean' }

    context 'when true' do
      let(:value) { Champs::BooleanChamp::TRUE_VALUE }
      it { subject; expect(page).to have_text(I18n.t('utils.yes')) }
    end

    context 'when false' do
      let(:value) { Champs::BooleanChamp::FALSE_VALUE }
      it { subject; expect(page).to have_text(I18n.t('utils.no')) }
    end
  end

  context 'with output_type nil (defensive — should not happen in practice)' do
    let(:output_type) { nil }

    context 'with an ISO date value' do
      let(:value) { '2026-06-08' }

      it 'does NOT auto-detect a date (no sniffing fallback)' do
        subject
        expect(page).to have_text('2026-06-08')
        expect(page).not_to have_selector('time')
      end
    end

    context 'with a blank value' do
      let(:value) { '' }

      it 'renders empty' do
        subject
        expect(page.text).to eq('')
      end
    end
  end

  def number_with_delimiter(n)
    ActionController::Base.helpers.number_with_delimiter(n)
  end
end
