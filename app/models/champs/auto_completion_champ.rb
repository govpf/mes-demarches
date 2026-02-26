# frozen_string_literal: true

class Champs::AutoCompletionChamp < Champ
  def options?
    type_de_champ.any_drop_down_list?
  end

  def options
    type_de_champ.drop_down_options | [value]
  end

  def disabled_options
    []
  end
end
