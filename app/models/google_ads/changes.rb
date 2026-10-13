# frozen_string_literal: true

# The changes the plugin can make to the ad account, each one small and
# each able to dry-run (validate_only: Google checks it and changes
# nothing): negative keywords on a campaign, a campaign paused or enabled,
# and an offline conversion uploaded by the click's gclid. Each is recorded
# in the audit log and makes the cached reports read fresh.
class GoogleAds::Changes
  MATCH_TYPES = %w[PHRASE EXACT BROAD].freeze
  STATUSES = %w[PAUSED ENABLED].freeze

  def initialize(settings: GoogleAds::Settings.current, client: nil)
    @settings = settings
    @client = client || GoogleAds::Client.new(settings: settings)
  end

  # Negative keywords on a campaign: {added: [...], failed: "…" or nil, validate_only:}.
  def negative_keywords(campaign_id:, keywords:, match_type: "PHRASE", validate_only: false)
    campaign = GoogleAds::Settings.customer_id(campaign_id) or raise GoogleAds::Error, "campaign_id is required"
    keywords = Array(keywords).flat_map { it.to_s.split(/[\n,]/) }.map { it.squish.downcase }.compact_blank.uniq
    raise GoogleAds::Error, "Name at least one keyword" if keywords.empty?
    raise GoogleAds::Error, "At most 200 keywords at a time" if keywords.size > 200

    match_type = match_type.to_s.upcase.presence || "PHRASE"
    raise GoogleAds::Error, "match_type is one of #{MATCH_TYPES.join(", ")}" unless MATCH_TYPES.include?(match_type)

    operations = keywords.map do |text|
      {create: {campaign: "customers/#{@settings.customer_id}/campaigns/#{campaign}", negative: true, keyword: {text: text, matchType: match_type}}}
    end
    answer = @client.mutate("campaignCriteria:mutate", {operations: operations, partialFailure: true, validateOnly: validate_only.present?})
    failed = answer.dig("partialFailureError", "message").presence
    added = validate_only ? keywords : keywords.zip(Array(answer["results"])).filter_map { |text, result| text if result.to_h["resourceName"].present? }
    record("google_ads.negative_keywords_added", campaign_id: campaign, keywords: added, match_type: match_type) unless validate_only || added.empty?
    {campaign_id: campaign, match_type: match_type, added: added, failed: failed, validate_only: validate_only.present?}
  end

  # A plan's negatives that aren't on its campaign yet, applied by match type.
  def apply_plan_negatives(plan, validate_only: false)
    raise GoogleAds::Error, "Link the plan to its campaign first (the campaign id)" if plan.campaign_id.blank?

    live = GoogleAds::PlanLive.new(plan, report: GoogleAds::Report.new(settings: @settings, client: @client))
    raise GoogleAds::Error, live.error if live.error
    raise GoogleAds::Error, "No campaign #{plan.campaign_id} in this account" unless live.campaign

    missing = live.missing_negatives
    results = missing.group_by { it[:match_type] }.map do |match_type, negatives|
      negative_keywords(campaign_id: plan.campaign_id, keywords: negatives.map { it[:text] }, match_type: match_type, validate_only: validate_only)
    end
    {campaign_id: plan.campaign_id, added: results.flat_map { it[:added] }, failed: results.filter_map { it[:failed] }.join("; ").presence,
     already: live.negatives.size, validate_only: validate_only.present?}
  end

  # An exclusion list made the same in Google Ads (a shared negative keyword set).
  def sync_exclusion_list(list, validate_only: false)
    answer = GoogleAds::SharedSets.new(settings: @settings, client: @client).sync(list, validate_only: validate_only)
    record("google_ads.exclusion_list_synced", list: list.name, added: answer[:added].size, removed: answer[:removed].size) unless validate_only
    answer
  end

  # A plan's exclusion lists synced, then attached to its campaign.
  def attach_exclusion_lists(plan, validate_only: false)
    raise GoogleAds::Error, "Link the plan to its campaign first (the campaign id)" if plan.campaign_id.blank?
    raise GoogleAds::Error, "Choose the plan's exclusion lists first" if plan.exclusion_lists.empty?

    synced = plan.exclusion_lists.map { sync_exclusion_list(it, validate_only: validate_only) }
    attached = GoogleAds::SharedSets.new(settings: @settings, client: @client).attach(plan.exclusion_lists.reload, plan.campaign_id, validate_only: validate_only)
    record("google_ads.exclusion_lists_attached", campaign_id: plan.campaign_id, shared_set_ids: attached) unless validate_only || attached.empty?
    {campaign_id: plan.campaign_id, synced: synced, attached: attached, validate_only: validate_only.present?}
  end

  def campaign_status(campaign_id:, status:, validate_only: false)
    campaign = GoogleAds::Settings.customer_id(campaign_id) or raise GoogleAds::Error, "campaign_id is required"
    status = status.to_s.upcase
    raise GoogleAds::Error, "status is #{STATUSES.join(" or ")}" unless STATUSES.include?(status)

    resource = "customers/#{@settings.customer_id}/campaigns/#{campaign}"
    @client.mutate("campaigns:mutate", {operations: [{update: {resourceName: resource, status: status}, updateMask: "status"}], validateOnly: validate_only.present?})
    record("google_ads.campaign_#{status.downcase}", campaign_id: campaign) unless validate_only
    {campaign_id: campaign, status: status, validate_only: validate_only.present?}
  end

  # An offline conversion: a lead from an ad click that became something worth
  # counting (a meeting, a client), told to Google by the click's gclid.
  def upload_conversion(gclid:, conversion_action_id:, at: nil, value: nil, currency: nil, validate_only: false)
    raise GoogleAds::Error, "gclid is required" if gclid.blank?

    action = GoogleAds::Settings.customer_id(conversion_action_id) or raise GoogleAds::Error, "conversion_action_id is required"
    time = at.present? ? Time.zone.parse(at.to_s) : Time.current
    raise GoogleAds::Error, "at is a time: yyyy-mm-dd hh:mm" unless time

    conversion = {gclid: gclid.to_s.strip, conversionAction: "customers/#{@settings.customer_id}/conversionActions/#{action}",
                  conversionDateTime: time.strftime("%Y-%m-%d %H:%M:%S%:z")}
    conversion.merge!(conversionValue: value.to_f, currencyCode: currency.presence || @settings.currency) if value.present?
    answer = @client.mutate(":uploadClickConversions", {conversions: [conversion], partialFailure: true, validateOnly: validate_only.present?})
    failed = answer.dig("partialFailureError", "message").presence
    raise GoogleAds::Error, failed if failed

    record("google_ads.conversion_uploaded", conversion_action_id: action, gclid: conversion[:gclid], value: value) unless validate_only
    {conversion_action_id: action, gclid: conversion[:gclid], at: conversion[:conversionDateTime], value: conversion[:conversionValue],
     validate_only: validate_only.present?}
  end

  private

  def record(action, **particulars)
    GoogleAds::Settings.changed!
    Event.record(action, customer_id: @settings.customer_id, **particulars)
  end
end
