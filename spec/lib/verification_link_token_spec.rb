# frozen_string_literal: true

describe VerificationLinkToken do
  let(:key_1) { 'a' * 32 }
  let(:key_2) { 'b' * 32 }

  def with_keys(value)
    stub_const('ENV', ENV.to_hash.merge(described_class::ENV_KEY => value))
    described_class.reset!
  end

  def with_legacy_until(value)
    stub_const('ENV', ENV.to_hash.merge(described_class::LEGACY_UNTIL_ENV_KEY => value))
    described_class.reset!
  end

  after { described_class.reset! }

  describe 'without dedicated key' do
    before { with_keys('') }

    it 'signs with the key derived from secret_key_base' do
      token = described_class.generate('qrcode', 12)

      expect(token).to match(/\Ak0_[A-Za-z0-9_-]{22}\z/)
      expect(described_class.valid?(token, 'qrcode', 12)).to be(true)
    end
  end

  describe 'with dedicated keys' do
    before { with_keys("2:#{key_2},1:#{key_1}") }

    it 'signs with the first key' do
      expect(described_class.generate('qrcode', 12)).to start_with('k2_')
    end

    it 'is bound to the resource' do
      token = described_class.generate('pj', 12, 34, nil)

      expect(described_class.valid?(token, 'pj', 12, 34, nil)).to be(true)
      expect(described_class.valid?(token, 'pj', 13, 34, nil)).to be(false)
      expect(described_class.valid?(token, 'pj', 12, 34, 'row')).to be(false)
      expect(described_class.valid?(token, 'qrcode', 12)).to be(false)
    end

    it 'rejects malformed or forged tokens' do
      expect(described_class.valid?(nil, 'qrcode', 12)).to be(false)
      expect(described_class.valid?('65a1b2c3-1f2e3d', 'qrcode', 12)).to be(false)
      expect(described_class.valid?("k2_#{'A' * 22}", 'qrcode', 12)).to be(false)
      expect(described_class.valid?("k9_#{'A' * 22}", 'qrcode', 12)).to be(false)
    end

    it 'still verifies tokens signed with an older key or with the derived key' do
      with_keys("1:#{key_1}")
      old_token = described_class.generate('qrcode', 12)
      with_keys('')
      derived_token = described_class.generate('qrcode', 12)

      with_keys("2:#{key_2},1:#{key_1}")

      expect(described_class.valid?(old_token, 'qrcode', 12)).to be(true)
      expect(described_class.valid?(derived_token, 'qrcode', 12)).to be(true)
    end

    it 'invalidates tokens of a removed key' do
      with_keys("1:#{key_1}")
      old_token = described_class.generate('qrcode', 12)

      with_keys("2:#{key_2}")

      expect(described_class.valid?(old_token, 'qrcode', 12)).to be(false)
    end
  end

  describe 'with an invalid configuration' do
    it 'refuses a short key, a non numeric version or a duplicated version' do
      ["1:short", "v1:#{key_1}", "0:#{key_1}", "1:#{key_1},1:#{key_2}"].each do |value|
        with_keys(value)
        expect { described_class.keys }.to raise_error(described_class::InvalidConfiguration)
      end
    end
  end

  describe 'legacy format cutoff' do
    it 'allows the legacy format everywhere without cutoff' do
      with_legacy_until(nil)

      expect(described_class.legacy_allowed?(Time.zone.now)).to be(true)
    end

    it 'allows the legacy format only for records created before the cutoff' do
      with_legacy_until('2026-11-20T08:00:00-10:00')
      cutoff = Time.zone.parse('2026-11-20T08:00:00-10:00')

      expect(described_class.legacy_allowed?(cutoff - 1.second)).to be(true)
      expect(described_class.legacy_allowed?(cutoff)).to be(false)
      expect(described_class.legacy_allowed?(cutoff + 1.day)).to be(false)
      expect(described_class.legacy_allowed?(nil)).to be(false)
    end

    it 'refuses an invalid date' do
      with_legacy_until('bientôt')

      expect { described_class.legacy_until }.to raise_error(described_class::InvalidConfiguration)
    end
  end

  it 'tells a signed token from the legacy encoded date' do
    expect(described_class.token?('k1_abc')).to be(true)
    expect(described_class.token?('65a1b2c3-1f2e3d')).to be(false)
  end
end
