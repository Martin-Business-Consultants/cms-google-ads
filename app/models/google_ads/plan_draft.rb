# frozen_string_literal: true

# A new campaign plan drafted by the install's AI (the AI plugin, cms-ai:
# Ai.structured) from the strategy answered so far and a line on what the
# campaign is for: a name, the goal, what success looks like and when to
# stop, who it's for, the budget, when to decide, and the setup. It fills
# Plans › New for the marketer to work through before saving; nothing is
# made until they do. Run in GoogleAds::PlanDraftJob (a model can take a
# minute or two); kept in the cache, a draft a person, until they make the
# plan or it expires.
class GoogleAds::PlanDraft
  KEEP_FOR = 2.hours
  STUCK_AFTER = 10.minutes
  FIELDS = %w[name goal success audience daily_budget decide_in_days locations schedule bidding].freeze
  SCHEMA = {
    type: "object", additionalProperties: false, required: FIELDS,
    properties: {
      name: {type: "string", description: "Short: segment and offer, as Google Ads will list it, e.g. “Commercial: seasonal displays”."},
      goal: {type: "string", description: GoogleAds::PlanTemplate::HINTS[:goal].to_s},
      success: {type: "string", description: GoogleAds::PlanTemplate::HINTS[:success].to_s},
      audience: {type: "string", description: GoogleAds::PlanTemplate::HINTS[:audience].to_s},
      daily_budget: {type: "number", description: "Dollars a day, checked against the economics: enough for about 10 clicks a day at the expected cost per click if the business can afford it."},
      decide_in_days: {type: "integer", description: "Days from today until deciding whether to keep it: usually 60 to 90."},
      locations: {type: "string", description: GoogleAds::PlanTemplate::HINTS[:locations].to_s},
      schedule: {type: "string", description: GoogleAds::PlanTemplate::HINTS[:schedule].to_s},
      bidding: {type: "string", description: GoogleAds::PlanTemplate::HINTS[:bidding].to_s}
    }
  }.freeze

  def self.for(user) = new(user)

  def initialize(user)
    @user = user
  end

  def key = "google_ads/plan_draft/#{@user.id}"
  def state = Rails.cache.read(key) || {}
  def working? = state["state"] == "running" && Time.zone.parse(state["at"].to_s).to_i > STUCK_AFTER.ago.to_i
  def ready? = state["state"] == "ready" && state["answer"].is_a?(Hash)
  def error = (state["state"] == "failed") ? state["error"] : nil
  def about = state["about"]
  def clear = Rails.cache.delete(key)

  def start(about)
    write("state" => "running", "about" => about.to_s.strip.first(500))
    GoogleAds::PlanDraftJob.perform_later(@user)
  end

  # The plan's attributes as the form takes them.
  def attributes
    answer = state["answer"] || {}
    days = answer["decide_in_days"].to_i
    budget = answer["daily_budget"].to_f
    answer.slice("name", "goal", "success", "audience", "locations", "schedule", "bidding").transform_values { it.to_s.strip.presence }.compact.merge(
      "daily_budget" => (budget.positive? ? budget.round(2) : nil), "decision_on" => (days.positive? ? Date.current + days.clamp(14, 365) : nil)
    ).compact
  end

  # Asks the AI; never raises: what went wrong is kept for Plans › New.
  def run!
    about = state["about"]
    step = GoogleAds::Guide::PLAN_STEPS.first
    known = GoogleAds::Guide::Prompt.new(step, GoogleAds::Plan.new).known
    prompt = [known.presence || "Nothing has been answered in the strategy yet: work from the brand brief, and say what to check.",
      "## Your task", "Draft a new Google Ads search campaign plan for this business#{": #{about}" if about.present?}. " \
        "One campaign, one customer segment and one offer: the one with the best chance of paying, from the strategy above. " \
        "Set a goal, what success looks like on the decision date and the result that should make it stop, who it's for and who it isn't, " \
        "a daily budget checked against the economics, the days until deciding, the locations, the schedule and the bidding to start with. " \
        "Today is #{Date.current.to_fs(:long)}. Plain, specific sentences the marketer can work from."].join("\n\n")
    answer = ::Ai.structured(purpose: "google_ads_plan", system: GoogleAds::Guide::Fill::SYSTEM, prompt: prompt, schema: SCHEMA, user: @user)
    write(state.merge("state" => "ready", "answer" => answer))
  rescue => error
    known = defined?(::Ai::Error) && (error.is_a?(::Ai::Error) || error.is_a?(::Ai::Unavailable))
    Rails.logger.error("[google_ads] drafting a plan with AI: #{error.class}: #{error.message}") unless known
    write(state.merge("state" => "failed", "error" => (known ? error.message : "#{error.class.name.demodulize}: #{error.message}").truncate(400)))
  end

  private

  def write(data) = Rails.cache.write(key, data.merge("at" => Time.current.iso8601), expires_in: KEEP_FOR)
end
