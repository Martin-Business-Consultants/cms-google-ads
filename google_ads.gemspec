# frozen_string_literal: true

require_relative "lib/google_ads/version"

Gem::Specification.new do |spec|
  spec.name = "google_ads"
  spec.version = GoogleAds::VERSION
  spec.summary = "Google Ads for Libre Publish: one ad account's figures, search terms and conversions, in the admin, the API and the cms CLI"
  spec.authors = ["Martin Business Consultants"]
  spec.license = "FSL-1.1-MIT"
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
