# frozen_string_literal: true

# A campaign, planned before a cent is spent: what it's for and what counts
# as success, the budget and the date to decide whether it worked, how it's
# set up, its ad groups and negatives, and a checklist (Plan::Template) from
# research to that decision. Linked to the live campaign (campaign_id), it is
# checked against it (Plan::Checks) and its negatives can be applied.
class GoogleAds::Plan < ApplicationRecord
  STATUSES = {"planning" => "Planning", "live" => "Live", "paused" => "Paused", "done" => "Done"}.freeze
  NETWORKS = {"search" => "Search only", "search_partners" => "Search and search partners", "search_display" => "Search and Display"}.freeze

  has_many :ad_groups, -> { order(:position, :id) }, class_name: "GoogleAds::PlanAdGroup", inverse_of: :plan, dependent: :delete_all
  has_many :tasks, -> { order(:position, :id) }, class_name: "GoogleAds::PlanTask", inverse_of: :plan, dependent: :delete_all

  normalizes :name, with: -> { it.squish }
  normalizes :campaign_id, with: -> { it.to_s.delete("^0-9").presence }

  validates :name, presence: true
  validates :status, inclusion: {in: STATUSES.keys}
  validates :networks, inclusion: {in: NETWORKS.keys}
  validates :daily_budget, numericality: {greater_than: 0}, allow_nil: true
  validate { errors.add(:decision_on, "is before the start") if starts_on && decision_on && decision_on < starts_on }

  scope :ordered, -> { in_order_of(:status, STATUSES.keys).order(updated_at: :desc) }

  # A new plan with the template's checklist (and the template's setup, where it's blank).
  def self.from_template(attributes = {}, template: "search_leads")
    new(attributes).tap { GoogleAds::PlanTemplate.apply(it, template) }
  end

  def status_label = STATUSES.fetch(status)
  def networks_label = NETWORKS.fetch(networks)
  def monthly_budget = daily_budget && (daily_budget * 30.4).round

  def days_to_decision = decision_on && (decision_on - Date.current).to_i

  # The negatives, one a line: "# Heading" names a group, [word] is exact match, anything else phrase.
  def negative_keywords
    group = "Negatives"
    found = []
    negatives.to_s.each_line do |line|
      line = line.strip
      if line.start_with?("#")
        group = line.delete_prefix("#").strip.presence || group
      elsif line.present?
        found << {text: line.delete("[]\"").squish.downcase, match_type: line.match?(/\A\[.*\]\z/) ? "EXACT" : "PHRASE", group: group}
      end
    end
    found.uniq { [it[:text], it[:match_type]] }
  end

  def progress
    countable = tasks.reject(&:repeats)
    {done: countable.count(&:done?), total: countable.size}
  end

  def as_json(*)
    {id: id, name: name, status: status, goal: goal, success: success, audience: audience, daily_budget: daily_budget&.to_f,
     monthly_budget: monthly_budget&.to_f, starts_on: starts_on, decision_on: decision_on, days_to_decision: days_to_decision,
     locations: locations, schedule: schedule, bidding: bidding, networks: networks, final_url_suffix: final_url_suffix,
     campaign_id: campaign_id, negatives: negatives, negative_keywords: negative_keywords, notes: notes, progress: progress,
     ad_groups: ad_groups.map(&:as_json), tasks: tasks.map(&:as_json), updated_at: updated_at}
  end
end
