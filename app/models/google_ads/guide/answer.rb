# frozen_string_literal: true

# A research answer pasted back from Claude (or posted by an agent): the
# JSON read out of it, what it would change in the step (described for a
# person to review), and the change made.
class GoogleAds::Guide::Answer
  attr_reader :data

  def initialize(step, record, text)
    @step = step
    @record = record
    @data = text.is_a?(Hash) ? text.deep_stringify_keys : parse(text.to_s)
    expected = @step.answer_format.keys.map(&:to_s)
    raise GoogleAds::Error, "That answer has none of the keys this step asks for (#{expected.join(", ")})" if (@data.keys & expected).empty?
  end

  # A field step's values, as the form takes them (lists one a line), and anything else Claude said.
  def values
    @step.fields.each_with_object({}) do |field, out|
      next unless @data.key?(field.key)

      value = @data[field.key]
      out[field.key] = value.is_a?(Array) ? value.map { it.to_s.strip }.compact_blank.join("\n") : value
    end
  end

  def notes = @data.except(*@step.fields.map(&:key), "ad_groups", "lists", "campaign_negatives").values.flatten.map(&:to_s).compact_blank.join("\n\n").presence

  # What applying it would do, a line each.
  def changes
    case @step.kind
    when :exclusions
      lists.map do |list|
        existing = GoogleAds::ExclusionList.where("LOWER(name) = ?", list["name"].downcase).first
        "#{existing ? "Add to" : "New list"} “#{list["name"]}”: #{list["keywords"].first(12).join(", ")}#{"…" if list["keywords"].size > 12} (#{list["keywords"].size})"
      end
    when :structure then groups.map { "#{find_group(it["name"]) ? "Update" : "New ad group"} “#{it["name"]}”#{" → #{it["landing_path"]}" if it["landing_path"].present?}#{": #{it["theme"]}" if it["theme"].present?}" }
    when :keywords
      groups.map { "“#{it["name"]}”#{" (new)" unless find_group(it["name"])}: #{Array(it["keywords"]).size} keywords — #{Array(it["keywords"]).first(6).join(", ")}…" } +
        (negatives.any? ? ["Campaign negatives: #{negatives.join(", ")}"] : [])
    when :ads
      groups.map do |group|
        long = Array(group["headlines"]).count { it.to_s.length > 30 } + Array(group["descriptions"]).count { it.to_s.length > 90 }
        "“#{group["name"]}”#{" (new)" unless find_group(group["name"])}: #{Array(group["headlines"]).size} headlines, #{Array(group["descriptions"]).size} descriptions#{" — #{long} over the limit" if long.positive?}"
      end
    else values.map { |key, value| "#{@step.field(key).label}: #{value.to_s.truncate(120)}" }
    end
  end

  # Makes the change: fields saved, or lists and ad groups created and filled.
  def apply!
    GoogleAds::Plan.transaction do
      case @step.kind
      when :exclusions then apply_lists
      when :structure, :keywords, :ads then apply_groups
      else
        @record.assign_answers(values)
        @record.save!
      end
    end
    changes
  end

  private

  def parse(text)
    json = text[/```(?:json)?\s*(\{.*?\})\s*```/m, 1] || text[/\{.*\}/m]
    raise GoogleAds::Error, "There's no JSON in that answer: paste Claude's whole reply, including the ```json block" unless json

    answer = JSON.parse(json)
    raise GoogleAds::Error, "The answer's JSON should be an object ({…})" unless answer.is_a?(Hash)

    answer
  rescue JSON::ParserError => error
    raise GoogleAds::Error, "Couldn't read the answer's JSON (#{error.message.truncate(80)}). Ask Claude to send it again as one ```json block."
  end

  def lists
    Array(@data["lists"]).filter_map do |list|
      next unless list.is_a?(Hash) && list["name"].present?

      {"name" => list["name"].to_s.squish, "description" => list["description"].to_s.strip.presence,
       "keywords" => Array(list["keywords"]).map { it.to_s.strip.downcase }.compact_blank.uniq}
    end
  end

  def groups = Array(@data["ad_groups"]).select { it.is_a?(Hash) && it["name"].present? }
  def negatives = Array(@data["campaign_negatives"]).map { it.to_s.strip.downcase }.compact_blank.uniq

  def find_group(name) = @record.ad_groups.find { it.name.casecmp?(name.to_s.squish) }

  def apply_lists
    lists.each do |attributes|
      list = GoogleAds::ExclusionList.where("LOWER(name) = ?", attributes["name"].downcase).first || GoogleAds::ExclusionList.new(name: attributes["name"])
      list.description ||= attributes["description"]
      list.merge_keywords(attributes["keywords"])
      list.save!
    end
  end

  def apply_groups
    groups.each do |attributes|
      group = find_group(attributes["name"]) || @record.ad_groups.build(name: attributes["name"].to_s.squish)
      case @step.kind
      when :structure
        group.landing_path = attributes["landing_path"] if attributes["landing_path"].present?
        group.notes = [attributes["theme"], attributes["why"]].compact_blank.join("\n") if group.notes.blank?
      when :keywords
        group.keywords = Array(attributes["keywords"]).map { it.to_s.strip }.compact_blank.uniq.join("\n")
      when :ads
        group.headlines = Array(attributes["headlines"]).map { it.to_s.strip }.compact_blank.join("\n") if attributes.key?("headlines")
        group.descriptions = Array(attributes["descriptions"]).map { it.to_s.strip }.compact_blank.join("\n") if attributes.key?("descriptions")
        group.path1 = attributes["path1"].to_s.strip.first(15) if attributes["path1"].present?
        group.path2 = attributes["path2"].to_s.strip.first(15) if attributes["path2"].present?
      end
      group.save!
    end
    return unless @step.kind == :keywords && negatives.any?

    have = @record.negative_keywords.map { it[:text] }
    fresh = negatives.reject { have.include?(it.delete("[]\"")) }
    @record.update!(negatives: [@record.negatives.to_s.rstrip.presence, "# This campaign (keyword research)", *fresh].compact.join("\n")) if fresh.any?
  end
end
