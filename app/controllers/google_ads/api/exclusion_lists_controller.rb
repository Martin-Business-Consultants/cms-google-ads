# frozen_string_literal: true

module GoogleAds
  module Api
    # /api/google_ads/exclusion_lists: negative keyword lists kept once, synced to Google Ads as shared sets.
    class ExclusionListsController < BaseController
      requires_capability "google_ads:read", only: [:index, :show]
      requires_capability "google_ads:plan", only: [:create, :update, :destroy]
      requires_capability "google_ads:write", only: :sync

      before_action(except: [:index, :create]) { @list = GoogleAds::ExclusionList.find(params[:id]) }

      def index = render(json: {exclusion_lists: GoogleAds::ExclusionList.ordered.map(&:as_json)})
      def show = render(json: @list.as_json)

      # {exclusion_list: {name, description, keywords: [...] or "one a line"}}
      def create
        render json: GoogleAds::ExclusionList.create!(attributes).as_json, status: :created
      end

      def update
        @list.update!(attributes)
        render json: @list.as_json
      end

      def destroy
        @list.destroy!
        render json: {deleted: @list.id}
      end

      # POST {validate_only}: the shared set in Google Ads made the same as the list.
      def sync
        report # the readiness check
        render json: GoogleAds::Changes.new(settings: settings).sync_exclusion_list(@list, validate_only: validate_only?)
      end

      private

      def attributes
        values = params.require(:exclusion_list).permit(:name, :description, :keywords, keywords: [])
        values[:keywords] = values[:keywords].join("\n") if values[:keywords].is_a?(Array)
        values
      end
    end
  end
end
