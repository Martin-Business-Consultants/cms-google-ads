# frozen_string_literal: true

# The research prompt for a step: everything the guide knows so far (the
# brand brief, the strategy, the exclusion lists, and for a campaign step
# the plan and its ad groups), the step's task, and the exact JSON shape to
# answer in, so the answer can be pasted straight back.
class GoogleAds::Guide::Prompt
  def initialize(step, record, brief: GoogleAds::Brief.current)
    @step = step
    @record = record
    @brief = brief
    @plan = record if record.is_a?(GoogleAds::Plan)
  end

  # Everything known so far (the brand brief, the strategy, the exclusion lists, and for a plan the plan), for another prompt to start from.
  def known = context

  def to_s
    [intro, context, "## Your task", @step.task, "## How to answer", answer_rules, "```json\n#{JSON.pretty_generate(@step.answer_format)}\n```"].compact_blank.join("\n\n")
  end

  private

  def intro
    "You're helping plan a Google Ads search campaign for a small business. Research on the web where it helps, say when you're estimating, " \
      "and be specific to this business and its service area. Here is what's known so far."
  end

  def answer_rules
    "Reply with one JSON code block in exactly this shape (the same keys; lists as JSON arrays), and nothing after it. " \
      "A few sentences before it explaining your reasoning are welcome."
  end

  def context
    sections = []
    brand = defined?(::BrandBrief) ? ::BrandBrief.to_h : {}
    sections << section("Brand", brand.map { |key, value| "#{key.humanize}: #{value}" })
    GoogleAds::Guide::BRIEF_STEPS.each do |step|
      next if step.kind == :exclusions

      sections << section(step.title, step.fields.filter_map { |field| line(field, @brief.answer(field.key)) })
    end
    lists = GoogleAds::ExclusionList.ordered.to_a
    sections << section("Exclusion lists (negative keywords already kept)", lists.map { "#{it.name}: #{it.keyword_list.map { it[:text] }.first(80).join(", ")}" })
    if @plan
      sections << section("This campaign", GoogleAds::Guide::PLAN_STEPS.flat_map(&:fields).filter_map { line(it, @plan.answer(it.key)) })
      sections << section("Its ad groups", @plan.ad_groups.map { ad_group_line(it) })
      sections << section("Its own negatives", [@plan.negative_keywords.map { it[:text] }.join(", ").presence].compact)
    end
    sections.compact.join("\n\n")
  end

  def section(title, lines)
    lines = lines.compact_blank
    "## #{title}\n#{lines.map { "- #{it}" }.join("\n")}" if lines.any?
  end

  def line(field, value)
    return if value.blank?

    value = value.to_s.lines.map(&:strip).compact_blank.join("; ") if field.lines? || field.type == :textarea
    value = "#{value}%" if field.type == :percent
    value = "$#{value}" if field.type == :money
    "#{field.label}: #{value}"
  end

  def ad_group_line(group)
    parts = [group.name, ("landing page #{group.landing_path}" if group.landing_path), group.notes.presence&.squish,
      ("keywords: #{group.keyword_list.map { it[:text] }.join(", ")}" if group.keyword_list.any?),
      ("headlines: #{group.headline_list.join(" | ")}" if group.headline_list.any?)]
    parts.compact.join(" — ")
  end
end
