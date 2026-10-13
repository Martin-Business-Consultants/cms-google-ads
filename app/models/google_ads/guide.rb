# frozen_string_literal: true

# The guide: a marketer stepped from the big picture to a campaign that's
# ready to launch. Strategy first (BRIEF_STEPS, answered once, shared by
# every campaign), then each campaign (PLAN_STEPS). Each step says why it
# matters, asks its questions with a hint and an example for each, and
# writes a research prompt for Claude from everything answered so far: the
# marketer runs it in Claude, pastes the answer back, and the guide reads
# it (Guide::Answer) into the step for them to review.
module GoogleAds::Guide
  Field = Data.define(:key, :label, :type, :hint, :placeholder, :required, :choices) do
    def initialize(key:, label:, type: :text, hint: nil, placeholder: nil, required: false, choices: nil)
      super(key: key.to_s, label: label, type: type, hint: hint, placeholder: placeholder, required: required, choices: choices)
    end

    def lines? = type == :lines
    def number? = %i[money percent number].include?(type)
  end

  Step = Data.define(:key, :scope, :title, :summary, :why, :tips, :fields, :kind, :task, :answer_format) do
    def initialize(key:, scope:, title:, summary:, why:, tips: [], fields: [], kind: :fields, task: nil, answer_format: nil)
      super(key: key.to_s, scope: scope, title: title, summary: summary, why: why, tips: tips, fields: fields, kind: kind, task: task, answer_format: answer_format)
    end

    def research? = task.present?
    def field(key) = fields.find { it.key == key.to_s }
  end

  def self.field(...) = Field.new(...)

  BRIEF_STEPS = [
    Step.new(key: :business, scope: :brief, title: "The business and its offer",
      summary: "What you sell, what you don't, and the one thing ads should sell first.",
      why: "Every keyword, ad and exclusion comes from this. Most wasted spend is clicks from people looking for something you don't sell, " \
           "so the “don't sell” list matters as much as the “sell” list. Ads work best selling one clear offer, not the whole business.",
      tips: ["Write it the way a customer would search for it, not the way the industry names it.",
        "The lead offer is the service with the best mix of demand, value and margin, that you can deliver well next month.",
        "Proof is what makes a stranger trust you: reviews, numbers, named clients, credentials, guarantees."],
      fields: [
        field(key: :business_name, label: "Business name", required: true),
        field(key: :website, label: "Website", placeholder: "https://…"),
        field(key: :sells, label: "What you sell", type: :lines, required: true, hint: "One a line, in the customer's words.", placeholder: "Seasonal planter programs for storefronts\nPlanting design for office entrances"),
        field(key: :not_sold, label: "What you don't sell, that people confuse with you", type: :lines, required: true,
          hint: "One a line. These become exclusions.", placeholder: "Lawn mowing\nSnow removal\nPatios and retaining walls"),
        field(key: :lead_offer, label: "The offer ads sell first", required: true, hint: "One service, for one kind of customer.", placeholder: "Holiday and winter planter displays for businesses"),
        field(key: :differentiators, label: "Why choose you", type: :lines, hint: "Three at most, each one a competitor couldn't honestly claim."),
        field(key: :proof, label: "Proof", type: :textarea, hint: "Reviews, results, clients, credentials.")
      ],
      task: "Read the business's website (and anything else you can find about it) and describe its offer the way a customer would search for it. " \
            "List what it sells, what people commonly confuse it with that it does NOT sell (so those searches can be excluded), the single offer " \
            "with the best chance as a paid search ad, its honest differentiators, and the proof a stranger would trust.",
      answer_format: {business_name: "…", website: "https://…", sells: ["…"], not_sold: ["…"], lead_offer: "…", differentiators: ["…"], proof: "…"}),

    Step.new(key: :customers, scope: :brief, title: "Customers and market",
      summary: "Who buys, who doesn't, where, and when they go looking.",
      why: "Search ads reach people at the moment they look. Knowing who's looking (and who isn't worth paying for) decides the keywords, " \
           "the locations, the schedule and the words in the ad. The “not customers” list becomes exclusions too.",
      tips: ["Segments are groups who buy for different reasons: a restaurant owner and an HOA board want different things.",
        "Buying triggers are what makes someone search today: a new building, a bad review of their entrance, the season changing.",
        "Seasonality tells you when to spend more and when to pause."],
      fields: [
        field(key: :segments, label: "Customer segments", type: :lines, required: true, hint: "One a line: who, and what they want.",
          placeholder: "Restaurants and shops: storefronts that draw people in\nHOA boards: entrances residents are proud of"),
        field(key: :not_customers, label: "Who isn't a customer", type: :lines, required: true, hint: "One a line. Searches from them are wasted money.",
          placeholder: "Homeowners (served separately)\nJob seekers\nDIY gardeners"),
        field(key: :decision_makers, label: "Who decides and who pays", hint: "Owner, facilities manager, property manager, board…"),
        field(key: :service_area, label: "Service area", type: :textarea, required: true, hint: "Counties, cities or a radius."),
        field(key: :buying_triggers, label: "What makes them search now", type: :lines),
        field(key: :seasonality, label: "Seasons and buying cycles", type: :textarea, hint: "When they search, when they decide, when budgets are set.")
      ],
      task: "Describe the market for this business's lead offer in its service area: the customer segments who buy it and why, who searches " \
            "for similar things but is NOT a customer (to exclude), who decides and pays, what triggers a search, and the seasons and budget cycles.",
      answer_format: {segments: ["Segment: what they want"], not_customers: ["…"], decision_makers: "…", service_area: "…", buying_triggers: ["…"], seasonality: "…"}),

    Step.new(key: :economics, scope: :brief, title: "What a customer is worth", kind: :economics,
      summary: "The numbers that decide what a click is worth paying for.",
      why: "Without these, every bid is a guess. A customer's value, how many leads become customers, and your margin give the most you can pay " \
           "for a lead. With a typical cost per click and the share of clicks that become leads, you can see whether ads can work before spending anything.",
      tips: ["Use first-year value unless customers reliably stay longer.", "Close rate is leads to paying customers, not leads to meetings.",
        "If you don't know, use honest guesses and correct them after 30 days."],
      fields: [
        field(key: :client_value, label: "A customer's value (first year)", type: :money, required: true, placeholder: "2400"),
        field(key: :close_rate, label: "Leads that become customers", type: :percent, required: true, placeholder: "20"),
        field(key: :margin, label: "Gross margin", type: :percent, required: true, placeholder: "50"),
        field(key: :expected_cpc, label: "Expected cost per click", type: :money, required: true, hint: "Keyword Planner's top-of-page bids, or Claude's estimate below."),
        field(key: :conversion_rate, label: "Clicks that become leads", type: :percent, required: true, placeholder: "5", hint: "3–8% is usual for a good landing page with a form."),
        field(key: :benchmark_notes, label: "Where these numbers came from", type: :textarea)
      ],
      task: "Estimate realistic Google Ads benchmarks for this business's lead offer in its service area: the typical cost per click for its main " \
            "keywords and the typical share of clicks that become leads for a local service landing page with a form. Give ranges, say which number " \
            "you'd plan with, and name your sources.",
      answer_format: {expected_cpc: 6.5, conversion_rate: 5, benchmark_notes: "ranges, assumptions and sources"}),

    Step.new(key: :competitors, scope: :brief, title: "Competitors and the search page",
      summary: "Who's already advertising, what they promise, and your angle against them.",
      why: "Your ad appears beside theirs. If every ad says “quality landscaping, free estimates”, the one that says something specific wins the click. " \
           "Knowing who bids also tells you which searches are contested and expensive.",
      tips: ["Search your main keywords logged out, from your service area, on a phone and a computer.",
        "Note who ranks organically too: if the top results sell something else, the keyword probably means something else."],
      fields: [
        field(key: :competitors, label: "Competitors", type: :lines, required: true, hint: "One a line: name — what they promise — where you differ."),
        field(key: :search_page, label: "What the search page shows", type: :textarea, hint: "Ads, map pack, the kind of results."),
        field(key: :angle, label: "Your angle, in one line", required: true, placeholder: "The only plants-only commercial designer: four seasons of color, no mowing contract")
      ],
      task: "Research who competes for this business's lead offer in its service area: who advertises on Google for its main searches, what they promise, " \
            "who ranks, and what the search results suggest people searching those words actually want. Then suggest the one-line angle that would " \
            "stand out against them.",
      answer_format: {competitors: ["Name — what they promise — where this business differs"], search_page: "…", angle: "…"}),

    Step.new(key: :exclusions, scope: :brief, title: "Exclusion lists", kind: :exclusions,
      summary: "Negative keywords kept once, by theme, and shared by every campaign.",
      why: "Exclusions are how a small budget stays on the right searches. Kept as lists by theme (Residential, Maintenance, Jobs…), they're " \
           "synced to Google Ads as shared negative keyword lists and attached to each campaign, so a new campaign starts protected and one change reaches all of them.",
      tips: ["Words alone are phrase match: “mowing” blocks any search containing it. Use [brackets] for exact match when the word alone is fine in other searches.",
        "Don't exclude words your own keywords use: the guide checks for that.", "Expect to add to these every week from the search terms report."],
      task: "Build negative keyword lists for this business's Google Ads, grouped by theme, from what it doesn't sell, who isn't a customer, and " \
            "searches that never buy (jobs, training, DIY, free, supplies). Single words or short phrases, lower case, phrase match unless exact match " \
            "is safer (then put it in [brackets]). Never include words that appear in what it does sell.",
      answer_format: {lists: [{name: "Residential", description: "…", keywords: ["homeowner", "backyard", "[home]"]}]})
  ].freeze

  PLAN_STEPS = [
    Step.new(key: :goal, scope: :plan, title: "Goal and budget", kind: :goal,
      summary: "What this campaign must achieve, what it can spend, and when you'll decide.",
      why: "A campaign without a goal and a decision date runs until someone notices the bill. Set the bar now, while the numbers can't tempt you to move it. " \
           "The guide checks the budget against the economics: whether it buys enough clicks to learn anything.",
      tips: ["Aim for at least 10 clicks a day, or it takes months to learn anything.", "60–90 days is long enough for a few leads, short enough to stop a dud."],
      fields: [
        field(key: :name, label: "Campaign name", required: true),
        field(key: :goal, label: "Goal", type: :textarea, required: true, hint: GoogleAds::PlanTemplate::HINTS[:goal]),
        field(key: :success, label: "Success, and when to stop", type: :textarea, required: true, hint: GoogleAds::PlanTemplate::HINTS[:success]),
        field(key: :daily_budget, label: "Daily budget", type: :money, required: true, hint: GoogleAds::PlanTemplate::HINTS[:daily_budget]),
        field(key: :starts_on, label: "Starts", type: :date),
        field(key: :decision_on, label: "Decide by", type: :date, required: true, hint: GoogleAds::PlanTemplate::HINTS[:decision_on])
      ],
      task: "Pressure-test this campaign's goal and budget against the business's economics: is the goal realistic for the budget, how many clicks " \
            "and leads should it expect a month, what should count as success on the decision date, and what result should make it stop.",
      answer_format: {goal: "…", success: "…", daily_budget: 30, notes: "the reasoning"}),

    Step.new(key: :audience, scope: :plan, title: "Audience, place and time",
      summary: "Which segment this campaign is for, where, and when ads show.",
      why: "One campaign, one segment. Locations and schedule are the cheapest exclusions there are: no click from outside the area, none at 2am when no one answers.",
      tips: ["Locations: choose Presence (people in or regularly in your area), never “interested in”.", "Schedule the hours someone can answer."],
      fields: [
        field(key: :segment, label: "Segment", required: true, hint: "From Customers and market."),
        field(key: :audience, label: "Who it's for, and who it isn't", type: :textarea, required: true, hint: GoogleAds::PlanTemplate::HINTS[:audience]),
        field(key: :locations, label: "Locations", type: :textarea, required: true, hint: GoogleAds::PlanTemplate::HINTS[:locations]),
        field(key: :schedule, label: "Schedule", hint: GoogleAds::PlanTemplate::HINTS[:schedule])
      ]),

    Step.new(key: :structure, scope: :plan, title: "Ad groups", kind: :structure,
      summary: "The themes inside the campaign, each with its own keywords, ad and landing page.",
      why: "An ad group is a promise kept three times: the search, the ad and the page all say the same thing. Tight themes get better click rates, " \
           "cheaper clicks and more leads. Fewer groups with more clicks each beat many starved ones.",
      tips: ["3–5 ad groups for a small budget.", "Each needs a landing page about exactly that theme, ideally one built for it."],
      task: "Propose 3 to 5 tightly themed ad groups for this Google Ads search campaign, each a distinct reason to search that the business serves, " \
            "with the landing page on its website that matches it best (a path), and why it's worth its share of the budget.",
      answer_format: {ad_groups: [{name: "…", theme: "…", landing_path: "/…", why: "…"}]}),

    Step.new(key: :keywords, scope: :plan, title: "Keywords", kind: :keywords,
      summary: "The searches each ad group should show for, and campaign-only exclusions.",
      why: "Keywords decide whose searches you pay for. On a small budget, phrase and exact match keep you on searches you chose; broad match hands the choice to Google. " \
           "Check the searches exist (Keyword Planner) before relying on them.",
      tips: ["\"Quotes\" for phrase match, [brackets] for exact. Avoid bare (broad) keywords.", "5–20 per ad group, all one theme.",
        "Paste Keyword Planner's volumes into the notes if you have them."],
      task: "Write the keywords for each of this campaign's ad groups: 5 to 15 each, the way buyers search, as phrase match in \"quotes\" or exact match in [brackets], " \
            "no broad match. Leave out anything the exclusion lists block. Also list negatives that apply only to this campaign.",
      answer_format: {ad_groups: [{name: "…", keywords: ["\"phrase keyword\"", "[exact keyword]"]}], campaign_negatives: ["…"]}),

    Step.new(key: :ads, scope: :plan, title: "Ad copy", kind: :ads,
      summary: "A responsive search ad for each ad group.",
      why: "The ad is the only thing a searcher sees before deciding to cost you money. It should echo the search, make the offer, give a reason " \
           "to trust you, and screen out the wrong people so they don't click.",
      tips: ["Up to 15 headlines of 30 characters, 4 descriptions of 90.", "Use the keyword in a few headlines, your angle in one, proof in one, and one that screens out (“For businesses only”).",
        "Display paths (15 characters each) show what the page is about."],
      task: "Write a responsive search ad for each ad group: 10 to 15 headlines of at most 30 characters (count them; include the theme's keyword in a few, " \
            "the business's angle, proof, and one that screens out the wrong searchers), 3 or 4 descriptions of at most 90 characters, and two display path " \
            "segments of at most 15 characters. Follow the brand's voice.",
      answer_format: {ad_groups: [{name: "…", headlines: ["…"], descriptions: ["…"], path1: "…", path2: "…"}]}),

    Step.new(key: :landing_pages, scope: :plan, title: "Landing pages", kind: :landing_pages,
      summary: "Each ad group's page: published, on theme, and built to turn a click into a lead.",
      why: "You pay for the click; the page earns the lead. Message match (the page says what the ad said), a form above the fold, proof and one clear " \
           "next step decide the conversion rate, and the conversion rate decides what you can afford to pay per click.",
      tips: ["Load it on a phone over mobile data.", "One form, few fields, a visible phone number.", "Keep the ad-click tracking on the form (the tracking field)."],
      fields: [field(key: :landing_review, label: "What to fix on the pages", type: :lines)],
      task: "Review each of this campaign's landing pages (on the website) against its ad group's keywords and ad: does it say what the ad said, is the form " \
            "easy to find on a phone, is there proof, is there one clear next step? List specific fixes, page by page.",
      answer_format: {landing_review: ["/page: the fix"]}),

    Step.new(key: :setup, scope: :plan, title: "Settings and exclusions", kind: :setup,
      summary: "Networks, bidding, tracking, and which exclusion lists this campaign uses.",
      why: "The defaults Google offers spend your money on Display, search partners and its own guesses. These settings keep the campaign on the searches you planned.",
      tips: [GoogleAds::PlanTemplate::HINTS[:networks], GoogleAds::PlanTemplate::HINTS[:bidding]],
      fields: [
        field(key: :networks, label: "Networks", type: :select, choices: GoogleAds::Plan::NETWORKS.invert, required: true, hint: GoogleAds::PlanTemplate::HINTS[:networks]),
        field(key: :bidding, label: "Bidding", required: true, hint: GoogleAds::PlanTemplate::HINTS[:bidding]),
        field(key: :final_url_suffix, label: "Final URL suffix", hint: GoogleAds::PlanTemplate::HINTS[:final_url_suffix]),
        field(key: :campaign_id, label: "Campaign ID", hint: GoogleAds::PlanTemplate::HINTS[:campaign_id])
      ]),

    Step.new(key: :preflight, scope: :plan, title: "Pre-flight", kind: :preflight,
      summary: "Everything checked, the campaign built, exclusions synced and attached.",
      why: "Like a walk-around before take-off: nothing here is hard, and skipping any of it is how campaigns burn their first week. " \
           "When the checks are clear, build it (Ads Editor download), link it, sync the exclusions, and launch.",
      tips: ["Set up conversion tracking and test it before any spend.", "Launch paused, review in Google Ads, then enable."])
  ].freeze

  STEPS = (BRIEF_STEPS + PLAN_STEPS).freeze

  def self.steps(scope) = (scope.to_sym == :brief) ? BRIEF_STEPS : PLAN_STEPS
  def self.step(key) = STEPS.find { it.key == key.to_s }
end
