# frozen_string_literal: true

# What a new plan starts with: the phases a campaign goes through, a
# checklist for each with a hint on how (and why), the hints shown beside a
# plan's settings, and sensible settings for a small lead-generation Search
# campaign. The advice is opinionated on purpose: for a small budget, the
# usual way to lose money is to let Google decide where it goes.
module GoogleAds::PlanTemplate
  PHASES = {
    "research" => "Before you build",
    "setup" => "Build the campaign",
    "launch" => "Launch week",
    "weekly" => "Every week",
    "monthly" => "Every month",
    "decision" => "Decision"
  }.freeze

  TEMPLATES = {"search_leads" => "Search campaign for leads", "blank" => "Blank: no checklist"}.freeze

  # Beside each of a plan's settings, on its form and its page.
  HINTS = {
    goal: "One sentence, in leads or sales, not clicks: “2 qualified commercial leads a month”. Clicks are what you pay for, not what you want.",
    success: "What has to be true on the decision date to keep going, and what would make you stop. Write it now, before the numbers tempt you to move the goalposts.",
    audience: "Who should click, and who shouldn't. The second half becomes your negative keywords.",
    daily_budget: "Google may spend up to twice this on a busy day, but no more than 30.4× it in a month. Start where losing it all would be an acceptable price for learning.",
    decision_on: "Usually 60–90 days after launch: long enough for a few conversions, short enough that a dud doesn't run all year.",
    locations: "Counties, cities or a radius. Under Location options, choose Presence: people in or regularly in your locations, not people interested in them.",
    schedule: "The hours someone can answer the phone or the form. Leads that wait overnight go cold.",
    bidding: "Start with Maximize clicks and a max CPC cap, or Manual CPC. Smart bidding (Maximize conversions, Target CPA) needs 15–30 conversions a month to learn; below that it guesses with your money.",
    networks: "Search only. Search partners and the Display Network bring cheap clicks that rarely convert for a local service; turn them off in the campaign settings.",
    final_url_suffix: "Tags every click so a lead can be traced to its campaign and keyword: utm_source=google&utm_medium=cpc&utm_campaign={campaignid}&utm_content={adgroupid}&utm_term={keyword}. Keep auto-tagging on too, for the gclid.",
    campaign_id: "Once the campaign exists, its id (in the address bar as campaignId=…, or from the Google Ads page here) links this plan to it: checks then compare plan and campaign, and negatives can be applied.",
    negatives: "One a line. # starts a group. Words alone are phrase match (blocks any search containing them); [brackets] are exact. Add them before launch: the first days' clicks are the most wasted.",
    keywords: "One a line: \"quotes\" for phrase, [brackets] for exact, bare words for broad. 5–20 per ad group, all one theme, so the ad and landing page can match it. Avoid broad match on a small budget.",
    headlines: "Up to 15, 30 characters each; Google mixes them. Use the keyword in a few, the offer, a proof point, and one that screens out the wrong people (“For businesses only”).",
    descriptions: "2–4, 90 characters each. What you do, for whom, where, and the next step.",
    landing_path: "The page clicks land on: matching this ad group's theme, with the form above the fold. A published page on this site, e.g. /business-seasonal-displays."
  }.freeze

  TASKS = [
    ["research", "Write the goal and the decision date", "Fill in the plan's goal, success and decision date. If you can't say what a lead is worth, work it out first: client value × the share of leads that become clients."],
    ["research", "Find out what a lead is worth", "Average first-year client value × close rate = what you can afford per lead. If ads can't beat that, no setting will save the campaign."],
    ["research", "Check the searches exist", "Keyword Planner (Tools › Keyword Planner › Get search volume) for each ad group's keywords, in your locations. Under ~50 searches a month for a group, merge it into another."],
    ["research", "Search your own keywords", "Search them on Google, logged out, from your area. Who advertises? What do their ads promise? Is the top result even selling what you sell? If not, the keyword is wrong."],
    ["research", "List what you don't sell", "Every service people confuse with yours, every job-seeker and DIY search: these are the negatives. Add them to the plan now."],
    ["setup", "Set up conversion tracking, and test it", "A conversion for the form's thank-you page and for calls from ads (60 seconds or longer). Submit a test lead and see it in Goals › Conversions › Summary within a day. No spend until this works."],
    ["setup", "Turn on auto-tagging", "Admin › Account settings › Auto-tagging. Every click gets a gclid, which the site's forms keep, so a lead can be traced to its click and uploaded later as an offline conversion."],
    ["setup", "Create the campaign: Search only", "New campaign › Leads › Search. Untick Search partners and Display Network. Don't accept Performance Max or the 'enhance' suggestions."],
    ["setup", "Set locations to Presence", "Locations › Location options › Presence: people in or regularly in your included locations."],
    ["setup", "Set the schedule, budget and bidding from the plan", "Ad schedule, daily budget, and bidding as the plan says. Add the final URL suffix under Campaign URL options."],
    ["setup", "Build the ad groups", "One per ad group in this plan, with its keywords and its landing page as the final URL. Download for Ads Editor builds them in one import."],
    ["setup", "Add the negatives", "Link the plan to the campaign (its id) and use Apply negatives here, or paste them into the campaign's negative keywords."],
    ["setup", "Add assets", "At least 4 sitelinks, 4 callouts, a call asset with your hours, and the location from your Business Profile. They make the ad bigger for free."],
    ["setup", "Check each landing page on a phone", "Load fast? Form visible without scrolling far? Phone number tappable? Submit the form once from a phone."],
    ["launch", "Read the search terms every day", "Google Ads page › Search terms (or cms ads-terms --days 1). Exclude anything that will never buy. The first week sets the tone for the rest."],
    ["launch", "Check ads are approved", "Ads & assets: status Eligible, not Limited or Disapproved. A disapproved ad shows nothing and says little; read the reason."],
    ["launch", "Confirm a real conversion arrived", "The first lead from an ad should show in Google Ads and arrive by email with its tracking (campaign, keyword, gclid). If not, stop and fix tracking."],
    ["weekly", "Exclude bad search terms", "Sort search terms by cost. Anything irrelevant becomes a negative (phrase match on the word that makes it wrong). Expect fewer each week.", "weekly"],
    ["weekly", "Check cost per click and impression share", "Rising CPC with a falling impression share means competitors are bidding up; falling share from budget means the budget runs out early in the day.", "weekly"],
    ["weekly", "Log the leads", "Each lead: date, ad group, keyword, gclid, whether it was qualified, a meeting, a client. The log is the only honest measure of the campaign.", "weekly"],
    ["monthly", "Compare cost per qualified lead with the goal", "Spend ÷ qualified leads, not ÷ form fills. Compare with what a lead is worth.", "monthly"],
    ["monthly", "Prune ad groups and keywords", "A keyword with spend and no leads after a month is a candidate to pause. An ad group whose terms are still mostly wrong after a month of negatives: pause it.", "monthly"],
    ["monthly", "Upload offline conversions", "For leads that became meetings or clients, upload their gclid (Changes › conversions, or cms ads-conversion). Google learns which clicks matter.", "monthly"],
    ["monthly", "Test one ad change", "Change one headline or description at a time, and leave it a month. More than that and you won't know what worked.", "monthly"],
    ["decision", "Decide: keep, change or stop", "On the decision date, against the success you wrote at the start. Keep and scale if it's paying for itself; change one big thing if leads came but didn't close; stop if search terms are clean and still nothing came."]
  ].freeze

  # The setup filled in for a new plan, where the plan doesn't say otherwise.
  DEFAULTS = {
    "search_leads" => {schedule: "Mon–Fri, business hours", bidding: "Maximize clicks with a max CPC cap for the first month, then manual CPC",
                       networks: "search", final_url_suffix: "utm_source=google&utm_medium=cpc&utm_campaign={campaignid}&utm_content={adgroupid}&utm_term={keyword}",
                       negatives: "# Jobs and learning\njobs\ncareers\nhiring\nsalary\ncourse\ndegree\n\n# Free and DIY\nfree\ndiy\nhow to\n"}
  }.freeze

  def self.apply(plan, template)
    template = TEMPLATES.key?(template.to_s) ? template.to_s : "search_leads"
    return plan if template == "blank"

    DEFAULTS.fetch(template, {}).each { |field, value| plan[field] = value if plan[field].blank? }
    TASKS.each_with_index { |(phase, title, hint, repeats), index| plan.tasks.build(phase: phase, title: title, hint: hint, repeats: repeats, position: index + 1) }
    plan
  end
end
