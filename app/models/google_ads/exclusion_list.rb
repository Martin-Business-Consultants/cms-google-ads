# frozen_string_literal: true

# A list of negative keywords kept once and used by every campaign that
# should never show for them ("Residential", "Maintenance", "Jobs"): synced
# to Google Ads as a shared negative keyword set (SharedSets), and attached
# to a plan's campaign. Keywords one a line: words alone are phrase match,
# [brackets] exact.
class GoogleAds::ExclusionList < ApplicationRecord
  normalizes :name, with: -> { it.squish }

  validates :name, presence: true, uniqueness: {case_sensitive: false}, length: {maximum: 120}

  scope :ordered, -> { order(:position, :name) }

  before_create { self.position = (self.class.maximum(:position) || 0) + 1 if position.to_i.zero? }

  def keyword_list
    keywords.to_s.lines.map(&:strip).reject { it.empty? || it.start_with?("#") }.map do |line|
      {text: line.delete("[]\"").squish.downcase, match_type: line.match?(/\A\[.*\]\z/) ? "EXACT" : "PHRASE"}
    end.uniq
  end

  # Adds what isn't there yet (from a pasted answer), keeping what is.
  def merge_keywords(words)
    have = keyword_list.map { [it[:text], it[:match_type]] }
    added = Array(words).map { it.to_s.strip }.compact_blank.reject do |word|
      have.include?([word.delete("[]\"").squish.downcase, word.match?(/\A\[.*\]\z/) ? "EXACT" : "PHRASE"])
    end.uniq
    self.keywords = [keywords.to_s.rstrip.presence, *added].compact.join("\n")
    added
  end

  def synced? = shared_set_id.present? && synced_at.present? && synced_at >= updated_at - 1.second

  def as_json(*)
    {id: id, name: name, description: description, keywords: keyword_list, count: keyword_list.size,
     shared_set_id: shared_set_id, synced_at: synced_at, synced: synced?, sync_error: sync_error}
  end
end
