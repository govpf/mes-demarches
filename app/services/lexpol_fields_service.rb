# frozen_string_literal: true

module LexpolFieldsService
  def self.object_field_values(source, field)
    return [] if source.blank? || field.blank?

    field.split('.').reduce([source]) do |objects, segment|
      objects.flat_map do |object|
        if object.respond_to?(segment)
          attributes(object, segment)
        elsif object.respond_to?(:rows)
          object.rows.flat_map { |row| select_champ(row, segment) }
        else
          object = dereference(object)
          results = []

          if object.is_a?(Dossier)
            all_champs = object.project_champs_public + object.project_champs_private
            results += select_champ(all_champs, segment)
          else
            results += select_champ(object.champs, segment) if object.respond_to?(:champs)
          end

          results += attributes(object, segment) if object.respond_to?(:segment)
          results
        end
      end
    end
  end

  def self.select_champ(champs, name)
    champs.filter { |champ| champ.libelle == name }
  end

  def self.attributes(object, name)
    r = object.send(name)
    r.is_a?(Array) ? r : [r]
  end

  # pf: deux contrats de formatage coexistent dans ce service.
  #
  # format_lexpol_value produit une DONNÉE destinée à une variable Lexpol.
  # Lexpol sait manipuler les dates et les nombres : on lui transmet donc une
  # date en jj/mm/aaaa — format que son formateur convertit en toutes lettres
  # selon ses propres conventions — et un nombre brut, qu'il sait calculer et
  # mettre en forme. Lexpol ne manipulant pas les datetime, ceux-ci sont
  # scindés en deux variables « X » et « X (heure) » par
  # LexpolService#build_variables, ce qui laisse au modèle le choix d'afficher
  # l'heure ou non (auparavant elle était collée à la date, donc obligatoire).
  #
  # format_lexpol_display produit un RENDU inséré tel quel dans le document
  # (cellules des tableaux de répétition). Lexpol n'a rien à manipuler ici :
  # le formatage doit être fait de notre côté, dates en toutes lettres et
  # nombres en typographie française.
  def self.format_lexpol_value(object)
    case object
    when Champs::DatetimeChamp, Champs::DateChamp
      format_date(object.value)
    when Champs::RepetitionChamp
      format_repetition_champ(object)
    when Champs::MultipleDropDownListChamp
      object.selected_options.to_sentence(last_word_connector: ' et ')
    when Champs::TextareaChamp
      format_markdown(object.value)
    when Champs::IntegerNumberChamp, Champs::DecimalNumberChamp
      object.value.present? ? object.value.to_s : "0"
    when Date, DateTime, Time
      format_date(object)
    else
      object.respond_to?(:value) ? object.value.to_s : object.to_s
    end
  end

  def self.format_lexpol_display(object)
    case object
    when Champs::DatetimeChamp
      format_datetime_en_lettres(object.value)
    when Champs::DateChamp
      format_date_en_lettres(object.value)
    when Champs::IntegerNumberChamp, Champs::DecimalNumberChamp
      format_nombre_fr(object.value)
    when DateTime, Time
      format_datetime_en_lettres(object)
    when Date
      format_date_en_lettres(object)
    else
      format_lexpol_value(object)
    end
  end

  def self.format_as_html_list(options)
    return '' if options.blank?

    list_items = options.each_with_index.map do |opt, index|
      # Dernier élément se termine par '.', les autres par ' ;'
      punctuation = (index == options.size - 1) ? '.' : ' ;'
      escaped_opt = ERB::Util.html_escape(opt.to_s)
      "<li>#{escaped_opt}#{punctuation}</li>"
    end

    "<ul>#{list_items.join}</ul>"
  end

  # pf: date destinée à une variable Lexpol. jj/mm/aaaa est le format que le
  # formateur Lexpol sait relire pour l'écrire en toutes lettres.
  def self.format_date(date)
    return '' if date.blank?
    parsed = parse_in_zone(date)
    parsed.nil? ? date.to_s : parsed.strftime('%d/%m/%Y')
  end

  # pf: heure d'un datetime, exposée dans une variable « X (heure) » distincte
  # puisque Lexpol ne manipule que des dates.
  def self.format_heure(datetime)
    return '' if datetime.blank?
    parsed = parse_in_zone(datetime)
    parsed.nil? ? '' : parsed.strftime('%H:%M')
  end

  def self.format_date_en_lettres(date)
    return '' if date.blank?
    parsed = parse_in_zone(date)
    return date.to_s if parsed.nil?

    day = (parsed.day == 1 ? "1er" : parsed.day.to_s)
    day + I18n.l(parsed.to_date, format: ' %B %Y')
  end

  def self.format_datetime_en_lettres(datetime)
    return '' if datetime.blank?
    parsed = parse_in_zone(datetime)
    return datetime.to_s if parsed.nil?

    "#{format_date_en_lettres(parsed)} à #{parsed.strftime('%H:%M')}"
  end

  # pf: le groupement des milliers ne démarre qu'à cinq chiffres : un champ
  # nombre contenant une année (2026) s'afficherait sinon « 2 026 ».
  GROUPING_THRESHOLD = 10_000

  def self.format_nombre_fr(value)
    return '0' if value.blank?

    number = Float(value.to_s)
    if number.abs < GROUPING_THRESHOLD
      value.to_s.tr('.', ',')
    else
      ActiveSupport::NumberHelper.number_to_delimited(value.to_s, delimiter: " ", separator: ',')
    end
  rescue ArgumentError, TypeError
    value.to_s
  end

  # pf: ramène une valeur (chaîne ISO, Date, Time) dans le fuseau de
  # l'application. Les valeurs saisies dans un champ sont des chaînes sans
  # fuseau : elles désignent une heure locale, jamais UTC.
  def self.parse_in_zone(value)
    case value
    when String then Time.zone.parse(value)
    else value.respond_to?(:in_time_zone) ? value.in_time_zone : nil
    end
  rescue ArgumentError, TypeError
    nil
  end

  def self.format_repetition_champ(repeat_champ)
    rows = repeat_champ.rows
    return '' if rows.blank?

    filtered_rows = rows.map do |row|
      row.reject { |champ| ignore_champ?(champ) }
    end

    return '' if filtered_rows.all?(&:empty?)

    <<~HTML.delete("\n")
      <table class="table table-bordered" style="margin: 0px auto !important;">
        <tbody>
          #{table_header_row(filtered_rows.first)}
          #{filtered_rows.each_with_index.map { |row, i| table_body_row(row, i) }.join}
        </tbody>
      </table>
    HTML
  end

  def self.table_header_row(row)
    return '' unless row.is_a?(Array)

    "<tr>" +
      row.map { |c| "<td style='background-color: #505050;color:#FFFFFF;padding:7px'>#{c.type_de_champ.libelle}</td>" }.join +
      "</tr></thead>"
  end

  def self.table_body_row(row, index)
    return '' if row.blank?

    background = (index.even? ? "#F0F0F0" : "#FFFFFF")

    "<tr style='background-color: #{background};'>" +
      row.map do |champ|
        # pf: contexte d'affichage — la cellule est insérée telle quelle dans
        # le document, Lexpol ne la manipule pas. Cf. format_lexpol_display.
        value = format_lexpol_display(champ)
        "<td style='vertical-align: middle; text-align: left;padding: 5px'>#{value}</td>"
      end.join +
      "</tr>"
  end

  def self.format_markdown(markdown_str)
    return '' if markdown_str.blank?

    renderer = Redcarpet::Render::HTML.new(filter_html: false, hard_wrap: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true)

    markdown.render(markdown_str).delete("\n")
  end

  def self.ignore_champ?(champ)
    champ.is_a?(Champs::HeaderSectionChamp) || champ.is_a?(Champs::ExplicationChamp)
  end

  private

  def self.dereference(object)
    object.is_a?(Champs::DossierLinkChamp) ? object.dossier : object
  end
end
