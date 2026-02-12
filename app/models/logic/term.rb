# frozen_string_literal: true

class Logic::Term
  def to_json
    to_h.to_json
  end

  def dup_with_stable_ids(_mapping)
    self
  end
end
