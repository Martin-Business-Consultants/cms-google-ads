# frozen_string_literal: true

# One thing to do for a plan, in a phase (PlanTemplate::PHASES), with a hint
# on how. A repeating one (weekly, monthly) is done for its period, then due again.
class GoogleAds::PlanTask < ApplicationRecord
  REPEATS = {"weekly" => 7.days, "monthly" => 30.days}.freeze

  belongs_to :plan, class_name: "GoogleAds::Plan", touch: true

  normalizes :title, with: -> { it.squish }

  validates :title, presence: true
  validates :phase, inclusion: {in: GoogleAds::PlanTemplate::PHASES.keys}
  validates :repeats, inclusion: {in: REPEATS.keys}, allow_nil: true

  before_create { self.position = (plan.tasks.maximum(:position) || 0) + 1 if position.to_i.zero? }

  # Done, and for a repeating one, done within its period.
  def done? = done_at.present? && (repeats.nil? || done_at > REPEATS.fetch(repeats).ago)

  def toggle!(by: nil)
    done? ? update!(done_at: nil, done_by: nil) : update!(done_at: Time.current, done_by: by)
  end

  def as_json(*)
    {id: id, phase: phase, title: title, hint: hint, repeats: repeats, done: done?, done_at: done_at, done_by: done_by, position: position}
  end
end
