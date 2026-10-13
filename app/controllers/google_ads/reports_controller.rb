# frozen_string_literal: true

module GoogleAds
  # The Google Ads page: the account's figures for a range beside the range
  # before, its campaigns, and the search terms to add as negatives.
  class ReportsController < ApplicationController
    include PluginGated
    plugin :google_ads

    requires_capability "google_ads:read", only: :show

    RANGES = [7, 30, 90].freeze

    def show
      @settings = GoogleAds::Settings.current
      @days = RANGES.include?(params[:days].to_i) ? params[:days].to_i : 30
      return unless @settings.ready?

      report = GoogleAds::Report.new(settings: @settings)
      @range = GoogleAds::Report.range(days: @days)
      @overview = report.overview(@range)
      @campaigns = report.campaigns(@range)
      @daily = report.daily(@range)
      @search_terms = report.search_terms(@range, limit: 50)
    rescue GoogleAds::Error => error
      @error = error.message
    end
  end
end
