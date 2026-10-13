# frozen_string_literal: true

module GoogleAds
  # Builds an ad group's landing page with the install's AI (GoogleAds::LandingPageBuild).
  class LandingPageJob < ApplicationJob
    queue_as :default

    def perform(group, user = nil) = LandingPageBuild.new(group).run!(user: user)
  end
end
