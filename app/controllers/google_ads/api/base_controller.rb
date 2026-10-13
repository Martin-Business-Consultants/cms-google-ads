# frozen_string_literal: true

module GoogleAds
  module Api
    # The plugin's API (/api/google_ads…): a 404 while it's off, every action
    # declaring its capability, and Google's refusals as a 422 that says why.
    class BaseController < ::Api::BaseController
      include PluginGated
      plugin :google_ads
      enforce_authorization

      rescue_from GoogleAds::Error do |error|
        render json: {error: "google_ads", message: error.message}, status: :unprocessable_content
      end

      # Every controller under this one says who may call it, on any core.
      def self.inherited(subclass)
        super
        subclass._skip_authorization = false
      end

      private

      def settings = @settings ||= GoogleAds::Settings.current

      def report
        raise GoogleAds::Error, "Google Ads isn't ready: add #{settings.missing.to_sentence} in Settings › Google Ads" unless settings.ready?

        GoogleAds::Report.new(settings: settings)
      end

      def range = GoogleAds::Report.range(days: params[:days], from: params[:from], to: params[:to])

      def period = {from: range.first, to: range.last}

      def validate_only? = ActiveModel::Type::Boolean.new.cast(params[:validate_only]).present?
    end
  end
end
