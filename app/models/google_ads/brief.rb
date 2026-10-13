# frozen_string_literal: true

# The strategy every campaign shares, answered once in the guide's first
# steps (Guide::BRIEF_STEPS): the business and its offer, its customers and
# market, what a customer is worth, its competitors. One per install.
class GoogleAds::Brief < ApplicationRecord
  include GoogleAds::Answerable

  def self.current = first || create!

  def guide_scope = :brief
end
