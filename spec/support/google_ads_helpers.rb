# frozen_string_literal: true

# Google Ads, answered without the network: each request is matched by a
# fragment of its address (and a search by what it selects FROM), and recorded.
module GoogleAdsHelpers
  def google_ads_requests = (@google_ads_requests ||= [])

  def fake_google_ads(failing: {})
    GoogleAds::Client.transport = lambda do |method, url, headers, body|
      google_ads_requests << {method: method, url: url, headers: headers, body: body}
      fragment = failing.keys.find { url.include?(it) }
      next [400, JSON.generate({"error" => {"message" => "Request contains an invalid argument.", "details" => [{"errors" => [{"message" => failing[fragment]}]}]}})] if fragment

      answer =
        if url.include?("oauth2.googleapis.com/token") then {"access_token" => "ya29.access", "expires_in" => 3599, "refresh_token" => "1//refresh"}
        elsif url.include?("userinfo") then {"email" => "owner@acme.example"}
        elsif url.include?("listAccessibleCustomers") then {"resourceNames" => ["customers/1234567890", "customers/9998887777"]}
        elsif url.include?("googleAds:search") then google_ads_search(url, body[:query])
        elsif url.include?("campaignCriteria:mutate") then {"results" => body[:operations].map.with_index { {"resourceName" => "customers/1234567890/campaignCriteria/111~#{_2}"} }}
        elsif url.include?("sharedSets:mutate") then {"results" => [{"resourceName" => "customers/1234567890/sharedSets/901"}]}
        elsif url.include?("sharedCriteria:mutate") || url.include?("campaignSharedSets:mutate") then {"results" => body[:operations].map { {"resourceName" => "x"} }}
        elsif url.include?("campaigns:mutate") then {"results" => [{"resourceName" => body.dig(:operations, 0, :update, :resourceName)}]}
        elsif url.include?(":uploadClickConversions") then {"results" => [{"gclid" => body.dig(:conversions, 0, :gclid)}]}
        end
      answer ? [200, JSON.generate(answer)] : [404, "{}"]
    end
  end

  def connect_google_ads
    GoogleAds::Settings.update("client_id" => "id.apps.googleusercontent.com", "client_secret" => "shh", "developer_token" => "dev-token", "customer_id" => "123-456-7890")
    GoogleAds::Settings.connect(refresh_token: "1//refresh", email: "owner@acme.example")
  end

  def metrics(impressions, clicks, cost, conversions)
    {"impressions" => impressions.to_s, "clicks" => clicks.to_s, "costMicros" => (cost * 1_000_000).to_i.to_s, "conversions" => conversions, "conversionsValue" => 0}
  end

  def google_ads_search(url, query)
    results =
      case query
      when /FROM customer LIMIT 1/
        manager = url.include?("9998887777")
        [{"customer" => {"id" => url[/customers\/(\d+)/, 1], "descriptiveName" => manager ? "Agency MCC" : "Healing Earth", "manager" => manager, "currencyCode" => "USD", "timeZone" => "America/Detroit"}}]
      when /SELECT segments.date.*FROM customer/m
        [{"segments" => {"date" => (Date.current - 2).iso8601}, "metrics" => metrics(400, 20, 60.5, 1)}, {"segments" => {"date" => (Date.current - 1).iso8601}, "metrics" => metrics(300, 10, 29.5, 0)}]
      when /FROM customer/
        before = query.include?("'#{(Date.current - 60).iso8601}'")
        [{"metrics" => before ? metrics(500, 20, 100, 1) : metrics(1000, 40, 300, 3)}]
      when /FROM campaign\b(?! WHERE campaign\.id)/
        [{"campaign" => {"id" => "555", "name" => "Commercial", "status" => "ENABLED", "advertisingChannelType" => "SEARCH", "biddingStrategyType" => "TARGET_SPEND"},
          "campaignBudget" => {"amountMicros" => "30000000"}, "metrics" => metrics(1000, 40, 300, 3).merge("searchImpressionShare" => 0.42)}]
      when /FROM search_term_view/
        [{"searchTermView" => {"searchTerm" => "lawn mowing service", "status" => "NONE"}, "campaign" => {"id" => "555", "name" => "Commercial"},
          "adGroup" => {"id" => "77", "name" => "Design"}, "metrics" => metrics(90, 6, 48, 0)},
          {"searchTermView" => {"searchTerm" => "commercial planters", "status" => "ADDED"}, "campaign" => {"id" => "555", "name" => "Commercial"},
           "adGroup" => {"id" => "78", "name" => "Seasonal"}, "metrics" => metrics(120, 9, 54, 2)}]
      when /FROM shared_set WHERE/
        [{"sharedSet" => {"id" => "900", "name" => "Jobs"}}]
      when /FROM shared_criterion/
        [{"sharedCriterion" => {"criterionId" => "1", "keyword" => {"text" => "jobs", "matchType" => "PHRASE"}}},
          {"sharedCriterion" => {"criterionId" => "2", "keyword" => {"text" => "salary", "matchType" => "PHRASE"}}}]
      when /FROM campaign_shared_set/
        [{"sharedSet" => {"id" => "900"}}]
      when /FROM campaign_criterion/
        [{"campaignCriterion" => {"keyword" => {"text" => "jobs", "matchType" => "PHRASE"}}}]
      when /FROM campaign WHERE campaign.id = 555/
        [{"campaign" => {"id" => "555", "name" => "Commercial", "status" => "ENABLED", "advertisingChannelType" => "SEARCH",
          "networkSettings" => {"targetSearchNetwork" => true, "targetContentNetwork" => true, "targetPartnerSearchNetwork" => false}},
          "campaignBudget" => {"amountMicros" => "40000000"}}]
      when /FROM campaign WHERE campaign.id/
        []
      when /FROM keyword_view/
        [{"adGroupCriterion" => {"criterionId" => "9", "keyword" => {"text" => "commercial planters", "matchType" => "PHRASE"}, "status" => "ENABLED", "qualityInfo" => {"qualityScore" => 7}},
          "adGroup" => {"name" => "Seasonal"}, "campaign" => {"id" => "555", "name" => "Commercial"}, "metrics" => metrics(120, 9, 54, 2)}]
      when /FROM conversion_action/
        [{"conversionAction" => {"id" => "321", "name" => "Planner submitted", "status" => "ENABLED", "type" => "WEBPAGE", "category" => "SUBMIT_LEAD_FORM", "primaryForGoal" => true}}]
      else []
      end
    {"results" => results}
  end
end

RSpec.configure do |config|
  config.include GoogleAdsHelpers
  config.after { GoogleAds::Client.transport = nil }
end
