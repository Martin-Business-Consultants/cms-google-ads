# frozen_string_literal: true

# The chosen ad account read through GAQL, each answer cached ten minutes
# (and read fresh after any change made here): totals for a range beside the
# range before, by day, by campaign, the search terms and keywords, and the
# conversion actions. Money is in the account's currency, as decimals
# (Google's micros divided out); rates are fractions.
class GoogleAds::Report
  CACHE_TTL = 10.minutes
  METRICS = "metrics.impressions, metrics.clicks, metrics.cost_micros, metrics.conversions, metrics.conversions_value"

  # A range of whole days ending yesterday (today's figures are still coming in), or from..to.
  def self.range(days: nil, from: nil, to: nil)
    if from.present?
      from = Date.iso8601(from.to_s)
      to = to.present? ? Date.iso8601(to.to_s) : Date.current
      raise GoogleAds::Error, "from is after to" if from > to

      return from..to
    end
    days = days.to_i.clamp(1, 730).nonzero? || 30
    (Date.current - days)..(Date.current - 1)
  rescue Date::Error
    raise GoogleAds::Error, "from and to are dates: yyyy-mm-dd"
  end

  # The same number of days just before a range.
  def self.before(range)
    length = (range.last - range.first).to_i + 1
    (range.first - length)..(range.first - 1)
  end

  def initialize(settings: GoogleAds::Settings.current, client: nil)
    @settings = settings
    @client = client || GoogleAds::Client.new(settings: settings)
  end

  # The account's figures for a range, beside the range before.
  def overview(range)
    before = self.class.before(range)
    {account: {customer_id: @settings.customer_id, name: @settings.customer_name, currency: @settings.currency},
     period: {from: range.first, to: range.last}, before: {from: before.first, to: before.last},
     totals: totals(range), totals_before: totals(before)}
  end

  def totals(range)
    rows = rows("SELECT #{METRICS} FROM customer WHERE #{between(range)}")
    figures(rows.each_with_object(Hash.new(0)) { |row, sums| row["metrics"].to_h.each { |key, value| sums[key] += value.to_f } })
  end

  def daily(range)
    rows("SELECT segments.date, #{METRICS} FROM customer WHERE #{between(range)} ORDER BY segments.date")
      .map { {date: it.dig("segments", "date"), **figures(it["metrics"])} }
  end

  def campaigns(range)
    gaql = "SELECT campaign.id, campaign.name, campaign.status, campaign.advertising_channel_type, campaign.bidding_strategy_type, " \
           "campaign_budget.amount_micros, #{METRICS}, metrics.search_impression_share FROM campaign " \
           "WHERE #{between(range)} AND campaign.status != 'REMOVED' ORDER BY metrics.cost_micros DESC"
    rows(gaql).map do |row|
      campaign = row["campaign"].to_h
      {id: campaign["id"], name: campaign["name"], status: campaign["status"], channel: campaign["advertisingChannelType"],
       bidding: campaign["biddingStrategyType"], daily_budget: money(row.dig("campaignBudget", "amountMicros")),
       impression_share: row.dig("metrics", "searchImpressionShare")&.to_f&.round(3), **figures(row["metrics"])}
    end
  end

  # What people typed before clicking: the source of negative keywords. status
  # is Google's: ADDED (already a keyword), EXCLUDED (already a negative), NONE.
  def search_terms(range, campaign_id: nil, limit: 100)
    campaign = GoogleAds::Settings.customer_id(campaign_id)
    gaql = "SELECT search_term_view.search_term, search_term_view.status, campaign.id, campaign.name, ad_group.id, ad_group.name, #{METRICS} " \
           "FROM search_term_view WHERE #{between(range)}#{" AND campaign.id = #{campaign}" if campaign} " \
           "ORDER BY metrics.impressions DESC LIMIT #{limit.to_i.clamp(1, 1000)}"
    rows(gaql).map do |row|
      {search_term: row.dig("searchTermView", "searchTerm"), status: row.dig("searchTermView", "status"),
       campaign_id: row.dig("campaign", "id"), campaign: row.dig("campaign", "name"),
       ad_group_id: row.dig("adGroup", "id"), ad_group: row.dig("adGroup", "name"), **figures(row["metrics"])}
    end
  end

  def keywords(range)
    gaql = "SELECT ad_group_criterion.criterion_id, ad_group_criterion.keyword.text, ad_group_criterion.keyword.match_type, " \
           "ad_group_criterion.status, ad_group_criterion.quality_info.quality_score, ad_group.name, campaign.id, campaign.name, #{METRICS} " \
           "FROM keyword_view WHERE #{between(range)} AND ad_group_criterion.status != 'REMOVED' ORDER BY metrics.impressions DESC"
    rows(gaql).map do |row|
      criterion = row["adGroupCriterion"].to_h
      {id: criterion["criterionId"], keyword: criterion.dig("keyword", "text"), match_type: criterion.dig("keyword", "matchType"),
       status: criterion["status"], quality_score: criterion.dig("qualityInfo", "qualityScore"),
       campaign_id: row.dig("campaign", "id"), campaign: row.dig("campaign", "name"), ad_group: row.dig("adGroup", "name"), **figures(row["metrics"])}
    end
  end

  def conversion_actions
    gaql = "SELECT conversion_action.id, conversion_action.name, conversion_action.status, conversion_action.type, " \
           "conversion_action.category, conversion_action.primary_for_goal FROM conversion_action WHERE conversion_action.status != 'REMOVED'"
    rows(gaql).map do |row|
      action = row["conversionAction"].to_h
      {id: action["id"], name: action["name"], status: action["status"], type: action["type"], category: action["category"],
       primary: action["primaryForGoal"]}
    end
  end

  # Any read-only GAQL, rows as Google returns them (uncached).
  def query(gaql)
    gaql = gaql.to_s.strip
    raise GoogleAds::Error, "Only SELECT queries: GAQL reads, it can't change anything" unless gaql.match?(/\ASELECT\s/i)

    @client.search(gaql)
  end

  private

  def rows(gaql)
    key = ["google_ads", @settings.customer_id, @settings.login_customer_id, @settings.generation, Digest::SHA256.hexdigest(gaql)]
    Rails.cache.fetch(key, expires_in: CACHE_TTL) { @client.search(gaql) }
  end

  def between(range) = "segments.date BETWEEN '#{range.first.iso8601}' AND '#{range.last.iso8601}'"

  def money(micros) = micros && (micros.to_i / 1_000_000.0).round(2)

  # Google's metrics (int64s come as strings) as numbers, with the rates worked out.
  def figures(metrics)
    metrics = metrics.to_h
    impressions = metrics["impressions"].to_i
    clicks = metrics["clicks"].to_i
    cost = money(metrics["costMicros"].to_i)
    conversions = metrics["conversions"].to_f.round(2)
    {impressions: impressions, clicks: clicks, cost: cost, conversions: conversions, conversion_value: metrics["conversionsValue"].to_f.round(2),
     ctr: impressions.positive? ? (clicks.to_f / impressions).round(4) : nil,
     cpc: clicks.positive? ? (cost / clicks).round(2) : nil,
     cost_per_conversion: conversions.positive? ? (cost / conversions).round(2) : nil}
  end
end
