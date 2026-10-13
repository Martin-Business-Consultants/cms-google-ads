# frozen_string_literal: true

# A step filled in by the install's AI (the AI plugin, cms-ai: Ai.structured)
# rather than by pasting Claude's reply: the same research prompt, answered
# in the step's exact JSON shape (a schema made from its answer_format, so
# no key can go missing), kept for the step's screen to show like a pasted
# answer, for a person to check before anything is saved. Run in
# GoogleAds::FillJob, as a model can take a minute or two; the state is kept
# in the cache (by step and record) until the step is saved or it expires.
class GoogleAds::Guide::Fill
  KEEP_FOR = 2.hours
  STUCK_AFTER = 10.minutes
  SYSTEM = "You research and plan Google Ads search campaigns for small businesses. Be specific to this business and its service area, " \
           "say when you're estimating, and never invent facts about the business: where you can't know, give a sensible starting point and say so " \
           "in the notes. Answer in the JSON shape asked for, every key filled."

  def self.available? = defined?(::Ai) && ::Ai.respond_to?(:available?) && ::Ai.available?

  def self.unavailable_reason
    return "Filling with AI needs the AI plugin: install it and set it up in Settings › AI" unless defined?(::Ai) && ::Ai.respond_to?(:unavailable_reason)

    ::Ai.unavailable_reason
  end

  # The JSON schema an answer_format describes: objects with every key required, arrays of their first item's shape.
  def self.schema_for(value)
    case value
    when Hash
      {type: "object", additionalProperties: false, required: value.keys.map(&:to_s), properties: value.to_h { |key, item| [key.to_s, schema_for(item)] }}
    when Array then {type: "array", items: schema_for(value.first || "")}
    when Numeric then {type: "number"}
    else {type: "string"}
    end
  end

  def initialize(step, record)
    @step = step
    @record = record
  end

  def key = "google_ads/guide_fill/#{@record.class.name.demodulize.underscore}/#{@record.id}/#{@step.key}"
  def state = Rails.cache.read(key) || {}
  def working? = state["state"] == "running" && Time.zone.parse(state["at"].to_s).to_i > STUCK_AFTER.ago.to_i
  def ready? = state["state"] == "ready" && state["answer"].is_a?(Hash)
  def error = (state["state"] == "failed") ? state["error"] : nil
  def answer = ready? ? state["answer"] : nil
  def clear = Rails.cache.delete(key)

  def start(user:)
    write("state" => "running")
    GoogleAds::FillJob.perform_later(@record, @step.key, user)
  end

  # Asks the AI; never raises: what went wrong is kept for the step's screen.
  def run!(user: nil, brief: GoogleAds::Brief.current)
    prompt = GoogleAds::Guide::Prompt.new(@step, @record, brief: brief).to_s
    answer = ::Ai.structured(purpose: "google_ads_guide", name: "google_ads_#{@step.key}", system: SYSTEM, prompt: prompt,
      schema: self.class.schema_for(@step.answer_format), user: user)
    GoogleAds::Guide::Answer.new(@step, @record, answer) # checks it's readable
    write("state" => "ready", "answer" => answer)
  rescue => error
    known = error.is_a?(GoogleAds::Error) || (defined?(::Ai::Error) && (error.is_a?(::Ai::Error) || error.is_a?(::Ai::Unavailable)))
    Rails.logger.error("[google_ads] filling #{@step.key} with AI: #{error.class}: #{error.message}") unless known
    write("state" => "failed", "error" => (known ? error.message : "#{error.class.name.demodulize}: #{error.message}").truncate(400))
  end

  private

  def write(data) = Rails.cache.write(key, data.merge("at" => Time.current.iso8601), expires_in: KEEP_FOR)
end
