# frozen_string_literal: true

# Exclusion lists in Google Ads: each one a shared negative keyword set,
# kept the same as the list (keywords added and removed), and attached to
# the campaigns that use it.
class GoogleAds::SharedSets
  def initialize(settings: GoogleAds::Settings.current, client: nil)
    @settings = settings
    @client = client || GoogleAds::Client.new(settings: settings)
  end

  # Makes the shared set match the list: {added:, removed:}.
  def sync(list, validate_only: false)
    set_id = find_or_create_set(list, validate_only: validate_only)
    current = set_id ? criteria(set_id) : []
    want = list.keyword_list
    adds = want.reject { |keyword| current.any? { it[:text] == keyword[:text] && it[:match_type] == keyword[:match_type] } }
    removes = current.reject { |criterion| want.any? { it[:text] == criterion[:text] && it[:match_type] == criterion[:match_type] } }
    if set_id && (adds.any? || removes.any?)
      operations = adds.map { {create: {sharedSet: set_resource(set_id), keyword: {text: it[:text], matchType: it[:match_type]}}} } +
        removes.map { {remove: "customers/#{@settings.customer_id}/sharedCriteria/#{set_id}~#{it[:criterion_id]}"} }
      operations.each_slice(1000) { @client.mutate("sharedCriteria:mutate", {operations: it, validateOnly: validate_only}) }
    end
    list.update_columns(shared_set_id: set_id, synced_at: Time.current, sync_error: nil) unless validate_only
    {list: list.name, shared_set_id: set_id, added: adds.map { it[:text] }, removed: removes.map { it[:text] }, validate_only: validate_only}
  rescue GoogleAds::Error => error
    list.update_columns(sync_error: error.message) unless validate_only
    raise
  end

  # The shared set ids attached to a campaign.
  def attached(campaign_id)
    campaign = GoogleAds::Settings.customer_id(campaign_id) or return []
    @client.search("SELECT shared_set.id FROM campaign_shared_set WHERE campaign.id = #{campaign} AND campaign_shared_set.status = 'ENABLED'")
      .filter_map { it.dig("sharedSet", "id") }
  end

  # Attaches synced lists to a campaign, skipping the ones already attached: the ids attached.
  def attach(lists, campaign_id, validate_only: false)
    campaign = GoogleAds::Settings.customer_id(campaign_id) or raise GoogleAds::Error, "The plan needs its campaign id"
    already = attached(campaign)
    todo = lists.select { it.shared_set_id.present? && !already.include?(it.shared_set_id) }
    if todo.any?
      operations = todo.map { {create: {campaign: "customers/#{@settings.customer_id}/campaigns/#{campaign}", sharedSet: set_resource(it.shared_set_id)}} }
      @client.mutate("campaignSharedSets:mutate", {operations: operations, validateOnly: validate_only})
    end
    todo.map(&:shared_set_id)
  end

  private

  def set_resource(id) = "customers/#{@settings.customer_id}/sharedSets/#{id}"

  def find_or_create_set(list, validate_only:)
    sets = @client.search("SELECT shared_set.id, shared_set.name FROM shared_set WHERE shared_set.type = 'NEGATIVE_KEYWORDS' AND shared_set.status = 'ENABLED'")
      .map { {id: it.dig("sharedSet", "id"), name: it.dig("sharedSet", "name").to_s} }
    found = sets.find { it[:id] == list.shared_set_id } || sets.find { it[:name].casecmp?(list.name) }
    return found[:id] if found
    return nil if validate_only

    answer = @client.mutate("sharedSets:mutate", {operations: [{create: {name: list.name, type: "NEGATIVE_KEYWORDS"}}]})
    answer.dig("results", 0, "resourceName").to_s.split("/").last.presence or raise GoogleAds::Error, "Google Ads didn't create the list “#{list.name}”"
  end

  def criteria(set_id)
    @client.search("SELECT shared_criterion.criterion_id, shared_criterion.keyword.text, shared_criterion.keyword.match_type FROM shared_criterion " \
                   "WHERE shared_set.id = #{set_id} AND shared_criterion.type = KEYWORD")
      .map { {criterion_id: it.dig("sharedCriterion", "criterionId"), text: it.dig("sharedCriterion", "keyword", "text").to_s.downcase, match_type: it.dig("sharedCriterion", "keyword", "matchType")} }
  end
end
