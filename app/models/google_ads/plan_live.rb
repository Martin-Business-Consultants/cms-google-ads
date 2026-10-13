# frozen_string_literal: true

# A plan beside the live campaign it's linked to: the campaign's settings
# and the negative keywords on it, so PlanChecks can compare and the
# missing negatives can be applied. Nil-safe: an error is kept, not raised.
class GoogleAds::PlanLive
  attr_reader :error

  def self.for(plan, settings: GoogleAds::Settings.current)
    return unless plan.campaign_id && settings.ready?

    new(plan, report: GoogleAds::Report.new(settings: settings))
  end

  def initialize(plan, report:)
    @plan = plan
    @report = report
    load
  end

  def campaign = @campaign

  def negatives = @negatives || []

  def missing_negatives
    applied = negatives.map { [it[:text], it[:match_type]] }
    @plan.negative_keywords.reject { applied.include?([it[:text], it[:match_type]]) }
  end

  private

  def load
    @campaign = @report.campaign(@plan.campaign_id)
    @negatives = @report.campaign_negatives(@plan.campaign_id) if @campaign
  rescue GoogleAds::Error => problem
    @error = problem.message
  end
end
