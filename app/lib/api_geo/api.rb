class ApiGeo::API
  TIMEOUT = 15
  CACHE_DURATION = 1.day

  def self.regions
    url = [API_GEO_URL, "regions"].join("/")
    call(url, { fields: :nom })
  end

  def self.departements
    url = [API_GEO_URL, "departements"].join("/")
    call(url, { fields: :nom })
  end

  def self.pays
    parse(File.open('app/lib/api_geo/pays.json').read)
  end

  def self.nationalites
    parse(File.open('app/lib/api_geo/nationalites.json').read)
  end

  def self.polynesian_cities
    result = []
    headers = []
    File.foreach('app/lib/api_geo/polynesian_postal_codes.txt', encoding: "windows-1252").with_index do |l, i|
      fields = l.split("\t")
      if i == 0
        headers = fields.map { |f| f.gsub(/\s+/, "_").downcase.to_sym }
      else
        entry = {}
        [1, 6, 7].each do |f|
          entry[headers[f]] = fields[f]
        end
        [2, 3].each do |f|
          entry[headers[f]] = fields[f].to_i
        end
        result << entry
      end
    end
    result
  end

  def self.codes_postaux_de_polynesie
    cities = polynesian_cities.partition { |e| e[:population] > 0 }
    big_cities = cities[0].sort_by { |e| [e[:code_postal], e[:commune]] }.map(&method(:postal_code_city_label))
    small_cities = cities[1].sort_by { |e| [e[:code_postal], e[:commune]] }.map(&method(:postal_code_city_label))
    big_cities + ['------------------------'] + small_cities
  end

  def self.communes_de_polynesie
    cities = polynesian_cities.partition { |e| e[:population] > 0 }
    big_cities = cities[0].sort_by { |e| [e[:commune], e[:code_postal]] }.map(&method(:city_postal_code))
    small_cities = cities[1].sort_by { |e| [e[:commune], e[:code_postal]] }.map(&method(:city_postal_code))
    big_cities + ['------------------------'] + small_cities
  end

  def self.search_rpg(geojson)
    url = [API_GEO_SANDBOX_URL, "rpg", "parcelles", "search"].join("/")
    call(url, geojson, :post)
  end

  private

  def self.postal_code_city_label(e)
    commune = e[:commune];
    ile = e[:ile]

    e[:code_postal].to_s + ' - ' + commune + (commune == ile ? "" : ' - ' + ile)
  end

  def self.city_postal_code(e)
    commune = e[:commune];
    ile = e[:ile]

    commune + (commune == ile ? "" : ' - ' + ile) + ' - ' + e[:code_postal].to_s
  end

  def self.parse(body)
    JSON.parse(body, symbolize_names: true)
  end

  def self.call(url, body, method = :get)
    # The cache engine is stored, because as of Typhoeus 1.3.1 the cache engine instance
    # is included in the computed `cache_key`.
    # (Which means that when the cache instance changes, the cache is invalidated.)
    @typhoeus_cache ||= Typhoeus::Cache::SuccessfulRequestsRailsCache.new

    response = Typhoeus::Request.new(
      url,
      method: method,
      params: method == :get ? body : nil,
      body: method == :post ? body : nil,
      timeout: TIMEOUT,
      accept_encoding: 'gzip',
      headers: {
        'Accept' => 'application/json',
        'Accept-Encoding' => 'gzip, deflate'
      }.merge(method == :post ? { 'Content-Type' => 'application/json' } : {}),
      cache: @typhoeus_cache,
      cache_ttl: CACHE_DURATION
    ).run

    if response.success?
      parse(response.body)
    else
      nil
    end
  end
end
