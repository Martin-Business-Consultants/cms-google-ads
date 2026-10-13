# frozen_string_literal: true

# An ad group's landing page built by the install's AI (the AI plugin,
# cms-ai: Ai.structured) from the site's own blocks, so it's on the theme:
# the block types this install has (each with the shape of its data), how
# the site's pages are composed from them, the strategy and the campaign, and
# the ad group's keywords and ads, so the page says what the ad said. Each
# block the AI writes is checked against its type and left out if it
# doesn't fit. The page is made a draft at the ad group's landing path (or
# a draft there rebuilt), never published: a person reviews it in the page
# editor and publishes it. Run in GoogleAds::LandingPageJob; the state is
# kept in the cache by ad group.
class GoogleAds::LandingPageBuild
  class Failed < StandardError; end

  KEEP_FOR = 2.hours
  STUCK_AFTER = 10.minutes
  # Field types the AI can't fill (a file, a record, nested blocks): a block type that needs one isn't offered, and its optional ones are left empty.
  UNFILLABLE = %w[asset record_ref record_refs blocks].freeze
  # Block types for other kinds of page.
  NOT_FOR_LANDING = %w[error_page confirmation post_list collection_list roles pattern].freeze
  EXAMPLES = 8
  SYSTEM = "You build landing pages for Google Ads campaigns on a small business's own website, from the website's own blocks. " \
           "A landing page turns a paid click into a lead: it says what the ad said, puts the form (or a call) near the top, gives proof and one clear next step, " \
           "and answers the doubts that stop people. Write in the business's voice, specific to it and its area; never invent facts (names, numbers, reviews, " \
           "awards): where you'd need one, write something true and general, and say what to add in the notes."

  def self.available? = GoogleAds::Guide::Fill.available?

  def initialize(group)
    @group = group
    @plan = group.plan
  end

  def key = "google_ads/landing_page/#{@group.id}"
  def state = Rails.cache.read(key) || {}
  def working? = state["state"] == "running" && Time.zone.parse(state["at"].to_s).to_i > STUCK_AFTER.ago.to_i
  def error = (state["state"] == "failed") ? state["error"] : nil
  def notes = (state["state"] == "ready") ? state["notes"] : nil
  def clear = Rails.cache.delete(key)

  # The page at the ad group's landing path, if there is one.
  def page
    path = landing_path
    path && ::Page.find_by(path: path)
  end

  # Whether the AI may build here: no page yet, or a draft (a published page is edited by a person).
  def buildable? = page.nil? || page.status != "published"

  def start(user:)
    write("state" => "running")
    GoogleAds::LandingPageJob.perform_later(@group, user)
  end

  # Builds it; never raises: what went wrong is kept for the step's screen.
  def run!(user: nil)
    raise Failed, "The page at #{@group.landing_path} is published: change it in the page editor" unless buildable?

    types = offered_types
    raise Failed, "This site has no blocks a landing page can be built from (Block types)" if types.empty?

    answer = ::Ai.structured(purpose: "google_ads_landing_page", system: SYSTEM, prompt: prompt(types), schema: schema(types), user: user)
    blocks, dropped = blocks_from(answer, types)
    raise Failed, "None of the AI's blocks fit the site's block types; try again" if blocks.size < 2

    page = save_page(answer, blocks)
    @group.update!(landing_path: "/#{page.path}")
    write("state" => "ready", "page_id" => page.id,
      "notes" => [answer["notes"].to_s.strip.presence, ("Left out, as they didn't fit their block type: #{dropped.join("; ")}" if dropped.any?)].compact.join("\n\n").presence)
  rescue => error
    known = error.is_a?(Failed) || (defined?(::Ai::Error) && (error.is_a?(::Ai::Error) || error.is_a?(::Ai::Unavailable))) || error.is_a?(ActiveRecord::RecordInvalid)
    Rails.logger.error("[google_ads] building the landing page for ad group #{@group.id}: #{error.class}: #{error.message}") unless known
    write("state" => "failed", "error" => (known ? error.message : "#{error.class.name.demodulize}: #{error.message}").truncate(400))
  end

  private

  def landing_path = @group.landing_path.to_s.delete_prefix("/").chomp("/").presence

  # The install's block types a landing page can use, by slug.
  def offered_types
    ::BlockType.order(:category, :label).reject do |type|
      NOT_FOR_LANDING.include?(type.slug) || Array(type.fields).any? { it["required"] == true && UNFILLABLE.include?(it["type"]) }
    end.index_by(&:slug)
  end

  def schema(types)
    {type: "object", additionalProperties: false, required: %w[title slug meta_title meta_description blocks notes],
     properties: {
       title: {type: "string", description: "The page's title, for the site's admin and the browser tab."},
       slug: {type: "string", description: "Its address, lower case with hyphens, e.g. holiday-planters-for-businesses."},
       meta_title: {type: "string", description: "Under 60 characters, with the ad group's main keyword."},
       meta_description: {type: "string", description: "Under 155 characters: the offer, the area, and the next step."},
       blocks: {type: "array", description: "The page from top to bottom.", items: {
         type: "object", additionalProperties: false, required: %w[type data_json],
         properties: {type: {type: "string", enum: types.keys}, data_json: {type: "string", description: "The block's data as a JSON object, in its type's shape."}}
       }},
       notes: {type: "string", description: "What a person should check or add before publishing: photos, real numbers, reviews, the form."}
     }}
  end

  def prompt(types)
    step = GoogleAds::Guide::PLAN_STEPS.find { it.key == "landing_pages" }
    [GoogleAds::Guide::Prompt.new(step, @plan).known,
      "## This ad group\n#{group_facts}",
      "## The site's blocks\nBuild the page only from these block types (slug, what it is, and the JSON schema of its data). " \
        "Leave out fields for images, files and records. A link is {\"kind\": \"page\", \"value\": \"page path\"} or {\"kind\": \"url\", \"value\": \"https://… or #anchor\"}.\n" +
        types.values.map { "- #{it.slug} (#{it.label}#{", #{it.category}" if it.category.present?}): #{it.description.to_s.squish.presence&.then { "#{_1} " }}#{JSON.generate(data_schema(it))}" }.join("\n"),
      "## How the site's pages are put together\n#{compositions}",
      ("## The site's pages, to link to\n#{::Page.where(status: "published").order(:path).limit(60).map { "/#{(it.path == "home") ? "" : it.path} — #{it.title}" }.join("\n")}"),
      "## Your task\nBuild the landing page for this ad group from the site's blocks, in the way the site's pages are put together. It must say what the ad group's ads say, " \
        "lead with its offer for its searches, put the way to get in touch (a form block if the site has one, else a call to action) near the top, and give proof, " \
        "the answers to the doubts that stop people, and one clear next step. 4 to 8 blocks. Today is #{Date.current.to_fs(:long)}."].compact_blank.join("\n\n")
  end

  def group_facts
    [("Name: #{@group.name}"), ("Landing page: #{@group.landing_path}" if @group.landing_path.present?), (@group.notes.to_s.squish.presence&.then { "Notes: #{it}" }),
      ("Keywords: #{@group.keyword_list.map { it[:text] }.join(", ")}" if @group.keyword_list.any?),
      ("Ad headlines: #{@group.headline_list.join(" | ")}" if @group.headline_list.any?),
      ("Ad descriptions: #{@group.description_list.join(" | ")}" if @group.description_list.any?)].compact.join("\n")
  end

  # Each block type's data schema, without the fields the AI can't fill.
  def data_schema(type)
    schema = type.json_schema
    fillable = Array(type.fields).reject { UNFILLABLE.include?(it["type"]) }.map { it["name"] }
    schema.merge("properties" => schema["properties"].slice(*fillable), "required" => Array(schema["required"]) & fillable)
  end

  # The block types of the site's published pages, in order, and one in full, so the AI composes the way the site does.
  def compositions
    pages = ::Page.where(status: "published").where.not(blocks: []).order(updated_at: :desc).limit(40).to_a
    pages = pages.sort_by { [(it.path == "home") ? 1 : 0, -Array(it.blocks).size] }.first(EXAMPLES)
    return "No published pages yet: lead with a hero, then the offer, proof, questions and a form." if pages.empty?

    example = pages.first
    [*pages.map { "/#{(it.path == "home") ? "" : it.path}: #{Array(it.blocks).map { it["type"] }.join(" → ")}" },
      "One of them in full (/#{example.path}): #{JSON.generate(Array(example.blocks).map { it.slice("type", "data") }).truncate(6000)}"].join("\n")
  end

  # The AI's blocks that fit their type, and what was left out.
  def blocks_from(answer, types)
    dropped = []
    blocks = Array(answer["blocks"]).filter_map do |block|
      problem, built = block_from(block, types)
      dropped << problem if problem
      built
    end
    [blocks, dropped]
  end

  # [why it was left out, nil] or [nil, the block].
  def block_from(block, types)
    type = types[block["type"]] or return ["a block of unknown type #{block["type"]}", nil]
    data = begin
      JSON.parse(block["data_json"].to_s)
    rescue JSON::ParserError
      return ["a #{type.label} whose data wasn't JSON", nil]
    end
    return ["a #{type.label} whose data wasn't an object", nil] unless data.is_a?(Hash)

    unfillable = Array(type.fields).select { UNFILLABLE.include?(it["type"]) }.map { it["name"] }
    data = data.except(*unfillable).slice(*Array(type.fields).map { it["name"] })
    problems = type.validate_data(data)
    return ["a #{type.label} (#{problems.map { |path, messages| "#{path} #{Array(messages).join(", ")}" }.join("; ").truncate(120)})", nil] if problems.any?

    [nil, {"type" => type.slug, "version" => 1, "data" => data}]
  end

  def save_page(answer, blocks)
    seo = {"meta_title" => answer["meta_title"].to_s.strip.first(70).presence, "meta_description" => answer["meta_description"].to_s.strip.first(170).presence,
           "focus_keyword" => @group.keyword_list.first&.dig(:text)}.compact
    title = answer["title"].to_s.strip.presence || @group.name
    if (existing = page)
      existing.update!(title: title, blocks: blocks, seo: existing.seo.to_h.merge(seo))
      return existing
    end

    path = landing_path || answer["slug"].to_s
    parent_path, _, leaf = path.rpartition("/")
    parent = parent_path.present? ? ::Page.find_by(path: parent_path) : nil
    slug = leaf.parameterize.presence || title.parameterize
    slug = free_slug(::Page.where(parent_id: parent&.id), slug)
    ::Page.create!(title: title.truncate(150), slug: slug, parent: parent, status: "draft", locale: default_locale, blocks: blocks, frontmatter: {}, seo: seo)
  end

  def free_slug(scope, base)
    taken = scope.where("slug = ? OR slug LIKE ?", base, "#{base}-%").pluck(:slug)
    taken.include?(base) ? (2..).lazy.map { "#{base}-#{it}" }.find { !taken.include?(it) } : base
  end

  def default_locale = Setting.get("general")["default_locale"].presence || "en"

  def write(data) = Rails.cache.write(key, data.merge("at" => Time.current.iso8601), expires_in: KEEP_FOR)
end
