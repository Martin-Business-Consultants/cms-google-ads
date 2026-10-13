# frozen_string_literal: true

module GoogleAds
  module Api
    # POST /api/google_ads/queries {query: "SELECT …"}: any read-only GAQL, rows as Google returns them.
    class QueriesController < BaseController
      requires_capability "google_ads:read", only: :create

      def create
        rows = report.query(params.require(:query))
        render json: {count: rows.size, rows: rows}
      end
    end
  end
end
