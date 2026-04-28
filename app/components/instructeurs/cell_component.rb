# frozen_string_literal: true

class Instructeurs::CellComponent < ApplicationComponent
  include DossierHelper

  def initialize(dossier:, column:)
    @dossier = dossier
    @column = column
  end

  def call
    advanced_layout || simple_layout
  end

  private

  def advanced_layout
    if @column.email?
      email_and_tiers(@dossier)
    elsif @column.dossier_labels?
      tags_label(@dossier.labels)
    elsif @column.avis?
      sum_up_avis(@dossier.avis)
    end
  end

  def simple_layout
    raw_value = raw_value_for_column(@dossier, @column)
    return '' if raw_value.nil?

    format(raw_value, @column.type)
  end

  def raw_value_for_column(dossier, column)
    data = if @column.champ_column?
      @dossier.champs.find { _1.stable_id == column.stable_id }
    else
      @dossier
    end

    @column.value(data)
  end

  def format(raw_value, type)
    case @column.type
    when :boolean
      if @column.type_de_champ? && @column.tdc_type == 'checkbox'
        raw_value ? I18n.t('activerecord.attributes.type_de_champ.type_champs.checkbox_true') : ''
      else
        raw_value ? I18n.t('utils.yes') : I18n.t('utils.no')
      end
    when :attachments
      raw_value.present? ? 'présent' : 'absent'
    when :enum
      format_enum(column: @column, raw_value:)
    when :enums
      format_enums(column: @column, raw_values: raw_value)
    when :date
      raw_value = Date.parse(raw_value) if raw_value.is_a?(String)
      I18n.l(raw_value)
    when :datetime
      raw_value = DateTime.parse(raw_value) if raw_value.is_a?(String)
      I18n.l(raw_value)
    when :integer, :decimal
      # pf: ChampColumn#typed_value force `.to_f` sur les colonnes :decimal,
      # ce qui produit "56.0" pour une formule retournant un entier (stocké
      # en chaîne "56"). On retire le `.0` quand le nombre est entier pour
      # un affichage propre. Bénéfique aussi pour les colonnes decimal_number
      # natives qui auraient été saisies sans décimales.
      raw_value.is_a?(Numeric) && raw_value % 1 == 0 ? raw_value.to_i.to_s : raw_value.to_s
    else
      raw_value
    end
  end

  def format_enums(column:, raw_values:)
    raw_values.map { format_enum(column:, raw_value: _1) }.join(', ')
  end

  def format_enum(column:, raw_value:)
    column.label_for_value(raw_value)
  end

  def email_and_tiers(dossier)
    email = dossier&.user&.email || dossier.user_email_for(:display)

    if dossier.for_tiers
      prenom, nom = dossier&.individual&.prenom, dossier&.individual&.nom
      "#{email} #{I18n.t('views.instructeurs.dossiers.acts_on_behalf')} #{prenom} #{nom}"
    else
      email
    end
  end

  def sum_up_avis(avis)
    avis.map(&:question_answer)&.compact&.tally
      &.map { |k, v| I18n.t("helpers.label.question_answer_with_count.#{k}", count: v) }
      &.join(' / ')
  end
end
