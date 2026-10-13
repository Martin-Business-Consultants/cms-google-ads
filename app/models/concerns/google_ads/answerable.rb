# frozen_string_literal: true

# What the guide reads and writes on a brief or a plan: each step's fields
# (a column when the record has one, otherwise in `answers`), and which
# steps were marked done.
module GoogleAds::Answerable
  extend ActiveSupport::Concern

  def answer(key)
    key = key.to_s
    has_attribute?(key) && key != "answers" ? self[key] : answers.to_h[key]
  end

  def answered?(key)
    value = answer(key)
    value.respond_to?(:empty?) ? value.present? : !value.nil?
  end

  # Field values from the guide's form or a pasted answer: columns set, the rest merged into answers.
  def assign_answers(values)
    extra = answers.to_h.dup
    values.to_h.each do |key, value|
      key = key.to_s
      if has_attribute?(key) && !%w[id answers done_steps].include?(key) then self[key] = value
      else extra[key] = value
      end
    end
    self.answers = extra
  end

  def step_done?(key) = Array(done_steps).include?(key.to_s)

  def mark_step!(key, done: true)
    steps = Array(done_steps) - [key.to_s]
    update!(done_steps: done ? steps + [key.to_s] : steps)
  end
end
