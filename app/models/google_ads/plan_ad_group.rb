# frozen_string_literal: true

# An ad group in a plan: one theme, its keywords ("phrase", [exact], or bare
# for broad), the page its clicks land on, and a responsive search ad's
# headlines (up to 15, 30 characters each) and descriptions (up to 4, 90 each).
class GoogleAds::PlanAdGroup < ApplicationRecord
  HEADLINE_LIMIT = 30
  DESCRIPTION_LIMIT = 90
  PATH_LIMIT = 15

  belongs_to :plan, class_name: "GoogleAds::Plan", touch: true

  normalizes :name, with: -> { it.squish }
  normalizes :landing_path, with: -> { it.strip.presence }

  validates :name, presence: true
  validates :path1, :path2, length: {maximum: PATH_LIMIT}

  before_create { self.position = (plan.ad_groups.maximum(:position) || 0) + 1 if position.to_i.zero? }

  # [{text:, match_type: PHRASE|EXACT|BROAD}]
  def keyword_list
    lines(keywords).map do |line|
      if line.match?(/\A\[.*\]\z/) then {text: line[1..-2].squish.downcase, match_type: "EXACT"}
      elsif line.match?(/\A".*"\z/) then {text: line[1..-2].squish.downcase, match_type: "PHRASE"}
      else {text: line.downcase, match_type: "BROAD"}
      end
    end.uniq
  end

  def headline_list = lines(headlines)
  def description_list = lines(descriptions)

  def as_json(*)
    {id: id, name: name, landing_path: landing_path, keywords: keyword_list, headlines: headline_list, descriptions: description_list,
     path1: path1, path2: path2, notes: notes, position: position}
  end

  private

  def lines(text) = text.to_s.lines.map(&:squish).compact_blank
end
