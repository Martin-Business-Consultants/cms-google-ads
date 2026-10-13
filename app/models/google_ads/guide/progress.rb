# frozen_string_literal: true

# Where a brief or a plan stands in the guide: each step "done", "started"
# or "todo", and the first one that isn't done.
class GoogleAds::Guide::Progress
  def initialize(record)
    @record = record
  end

  def steps = GoogleAds::Guide.steps(@record.guide_scope)

  def status(step)
    return "done" if @record.step_done?(step.key) || complete?(step)

    started?(step) ? "started" : "todo"
  end

  def next_step = steps.find { status(it) != "done" } || steps.last
  def done_count = steps.count { status(it) == "done" }

  def to_a = steps.map { {key: it.key, title: it.title, summary: it.summary, status: status(it)} }

  private

  def groups = @record.ad_groups.to_a

  def complete?(step)
    case step.kind
    when :exclusions then GoogleAds::ExclusionList.all.any? { it.keyword_list.any? }
    when :structure then groups.any? && groups.all? { it.landing_path.present? }
    when :keywords then groups.any? && groups.all? { it.keyword_list.size >= 3 }
    when :ads then groups.any? && groups.all? { ad_ready?(it) }
    when :landing_pages then false
    when :setup then required_answered?(step) && Array(@record.exclusion_list_ids).any?
    when :preflight then @record.campaign_id.present? && GoogleAds::PlanChecks.new(@record).problems.zero?
    else required_answered?(step)
    end
  end

  def started?(step)
    case step.kind
    when :exclusions then GoogleAds::ExclusionList.exists?
    when :structure, :keywords, :ads, :preflight then groups.any?
    else step.fields.any? { @record.answered?(it.key) && !(it.key == "networks") }
    end
  end

  def required_answered?(step) = step.fields.select(&:required).all? { @record.answered?(it.key) }

  def ad_ready?(group)
    headlines = group.headline_list
    descriptions = group.description_list
    headlines.size >= 3 && descriptions.size >= 2 && headlines.all? { it.length <= GoogleAds::PlanAdGroup::HEADLINE_LIMIT } &&
      descriptions.all? { it.length <= GoogleAds::PlanAdGroup::DESCRIPTION_LIMIT }
  end
end
