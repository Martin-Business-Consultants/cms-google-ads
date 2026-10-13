# frozen_string_literal: true

module GoogleAds
  module Api
    # GET /api/google_ads: the account's figures for ?days (or ?from&to) beside the period before.
    class OverviewController < BaseController
      requires_capability "google_ads:read", only: :show

      def show
        return render(json: {ready: false, missing: settings.missing}) unless settings.ready?

        render json: {ready: true, **report.overview(range)}
      end
    end
  end
end
