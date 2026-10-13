# frozen_string_literal: true

require "google_ads/version"
require "google_ads/engine"

# Google Ads for the CMS: one ad account, connected once (Settings › Google
# Ads), read live through the Google Ads REST API (a plugin may use only the
# gems the core bundles, so no google-ads-googleads): figures by day and by
# campaign, search terms, keywords and conversion actions, in the admin's
# Google Ads page, at /api/google_ads and in the cms CLI; and a few careful
# changes (negative keywords, pausing a campaign, uploading a conversion by
# its gclid), each able to dry-run first. Off by default.
module GoogleAds
  class Error < StandardError; end

  # Plugin tables (there are none yet) and its setting are prefixed with its key.
  def self.table_name_prefix = "google_ads_"

  # The Google Ads API version spoken: a REST path segment, e.g. v25.
  API_VERSION = "v25"
  SCOPE = "https://www.googleapis.com/auth/adwords"

  def self.ready? = Cms::Plugins.enabled?(:google_ads) && GoogleAds::Settings.current.ready?
end
