# frozen_string_literal: true

# What's wrong or missing in a plan, before it costs anything: the plan
# itself, each ad group (keywords, landing page, ad copy within Google's
# limits), negatives that would block the plan's own keywords, and, when it's
# linked to a live campaign (PlanLive), where the campaign differs from it.
# Each check is {level: "problem"|"warning"|"ok", area:, message:}.
class GoogleAds::PlanChecks
  LEVELS = %w[problem warning ok].freeze

  def initialize(plan, live: nil)
    @plan = plan
    @live = live
    @results = []
  end

  def results
    return @results if @checked

    @checked = true
    plan_checks
    @plan.ad_groups.each { ad_group_checks(it) }
    live_checks if @live
    @results.sort_by! { LEVELS.index(it[:level]) }
  end

  def problems = results.count { it[:level] == "problem" }
  def warnings = results.count { it[:level] == "warning" }

  private

  def add(level, area, message) = @results << {level: level, area: area, message: message}

  def plan_checks
    add("problem", "Plan", "No goal: say what the campaign is for, in leads or sales") if @plan.goal.blank?
    add("warning", "Plan", "No success measure: write what has to be true on the decision date") if @plan.success.blank?
    add("problem", "Plan", "No daily budget") unless @plan.daily_budget
    add("warning", "Plan", "No decision date: a campaign without one runs until someone notices") unless @plan.decision_on
    add("warning", "Plan", "No locations: a local business pays for clicks from everywhere") if @plan.locations.blank?
    add("warning", "Plan", "#{@plan.networks_label}: Search only keeps a small budget on searches") unless @plan.networks == "search"
    add("warning", "Plan", "No final URL suffix: leads can't be traced to their keyword") if @plan.final_url_suffix.blank?
    add("warning", "Plan", "No negatives or exclusion lists yet: the first days' clicks are the most wasted") if @plan.all_negatives.empty?
    if @plan.ad_groups.empty?
      add("problem", "Plan", "No ad groups yet")
    elsif @plan.daily_budget && @plan.daily_budget / @plan.ad_groups.size < 5
      add("warning", "Plan", "#{@plan.ad_groups.size} ad groups on #{format("%.2f", @plan.daily_budget)} a day: under 5 each, few will get enough clicks to learn from. Fewer, tighter groups.")
    end
    add("warning", "Plan", "Linked to no campaign: add its id once it exists, to check it against the plan") if @plan.status == "live" && @plan.campaign_id.blank?
  end

  def ad_group_checks(group)
    area = group.name
    keywords = group.keyword_list
    if keywords.empty? then add("problem", area, "No keywords")
    elsif keywords.size > 25 then add("warning", area, "#{keywords.size} keywords: more than 20 or so usually means two themes; split it")
    elsif keywords.size < 3 then add("warning", area, "Only #{keywords.size} keyword#{"s" if keywords.size > 1}: a few more close variants help it show")
    end
    broad = keywords.select { it[:match_type] == "BROAD" }
    add("warning", area, "Broad match: #{broad.map { it[:text] }.first(3).to_sentence}. On a small budget, use \"phrase\" or [exact]") if broad.any?

    landing_checks(group, area)

    headlines = group.headline_list
    descriptions = group.description_list
    long = headlines.select { it.length > GoogleAds::PlanAdGroup::HEADLINE_LIMIT }
    long.each { add("problem", area, "Headline over 30 characters (#{it.length}): “#{it}”") }
    if headlines.size < 3 then add("problem", area, "#{headlines.size} headline#{"s" unless headlines.size == 1}: a responsive search ad needs at least 3")
    elsif headlines.size < 8 then add("warning", area, "#{headlines.size} headlines: 8–15 give Google room to find what works")
    end
    add("problem", area, "#{headlines.size} headlines: at most 15") if headlines.size > 15
    group.description_list.select { it.length > GoogleAds::PlanAdGroup::DESCRIPTION_LIMIT }.each { add("problem", area, "Description over 90 characters (#{it.length}): “#{it.truncate(50)}”") }
    add("problem", area, "#{descriptions.size} description#{"s" unless descriptions.size == 1}: it needs at least 2") if descriptions.size < 2
    add("problem", area, "#{descriptions.size} descriptions: at most 4") if descriptions.size > 4
    duplicates = headlines.map(&:downcase).tally.select { _2 > 1 }.keys
    add("warning", area, "Repeated headline: #{duplicates.first}") if duplicates.any?
    if headlines.size >= 3 && keywords.any? && headlines.none? { |headline| keywords.any? { headline.downcase.include?(it[:text].split.first(2).join(" ")) } }
      add("warning", area, "No headline uses a keyword: ads that echo the search get clicked more")
    end
    conflict_checks(group)
    add("ok", area, "Keywords, landing page and ad copy look ready") if @results.none? { it[:area] == area && it[:level] != "ok" }
  end

  def landing_checks(group, area)
    path = group.landing_path
    return add("problem", area, "No landing page") if path.blank?
    return if path.match?(%r{\Ahttps?://}i)

    page = Page.where(path: path.delete_prefix("/").delete_suffix("/")).then { it.respond_to?(:kept) ? it.kept : it }.first
    if page.nil? then add("problem", area, "Landing page #{path} isn't a page on this site")
    elsif page.status != "published" then add("warning", area, "Landing page #{path} isn't published yet (#{page.status})")
    end
  end

  # A negative that matches one of the plan's own keywords blocks it.
  def conflict_checks(group)
    negatives = @negatives ||= @plan.all_negatives
    group.keyword_list.each do |keyword|
      blocker = negatives.find { |negative| (negative[:match_type] == "EXACT") ? keyword[:text] == negative[:text] : " #{keyword[:text]} ".include?(" #{negative[:text]} ") }
      add("problem", group.name, "The negative “#{blocker[:text]}” blocks the keyword “#{keyword[:text]}”") if blocker
    end
  end

  def live_checks
    campaign = @live.campaign
    return add("problem", "Campaign", @live.error) if @live.error
    return add("problem", "Campaign", "No campaign #{@plan.campaign_id} in this account") unless campaign

    area = "Campaign"
    add("warning", area, "It's #{campaign[:status].to_s.downcase}") unless campaign[:status] == "ENABLED"
    add("warning", area, "It's a #{campaign[:channel].to_s.humanize.downcase} campaign, not Search") unless campaign[:channel] == "SEARCH"
    add("problem", area, "It shows on the Display Network: turn that off") if campaign[:display_network] && @plan.networks != "search_display"
    add("warning", area, "It shows on search partners") if campaign[:partner_network] && @plan.networks == "search"
    if @plan.daily_budget && campaign[:daily_budget] && (campaign[:daily_budget] - @plan.daily_budget.to_f).abs > 0.5
      add("warning", area, "Budget is #{format("%.2f", campaign[:daily_budget])} a day; the plan says #{format("%.2f", @plan.daily_budget)}")
    end
    unattached = @live.unattached_lists
    unattached.each { add("warning", area, "The exclusion list “#{it.name}” #{it.shared_set_id ? "isn't attached to the campaign" : "isn't in Google Ads yet: sync it"}") }
    add("ok", area, "Its exclusion lists are attached") if unattached.empty? && @plan.exclusion_lists.any?
    missing = @live.missing_negatives
    if missing.any?
      add("warning", area, "#{missing.size} of the plan's negatives aren't on the campaign yet: #{missing.map { it[:text] }.first(5).join(", ")}#{"…" if missing.size > 5}")
    elsif @plan.negative_keywords.any?
      add("ok", area, "Every negative of the plan's own is on the campaign")
    end
  end
end
