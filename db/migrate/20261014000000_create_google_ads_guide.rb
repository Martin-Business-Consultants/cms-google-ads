# frozen_string_literal: true

# The guide from strategy to campaign: the brief (what every campaign
# shares: the business, its customers, what one is worth, competitors), the
# exclusion lists (negative keywords kept once, synced to Google Ads as
# shared sets), and each plan's answers to the campaign steps.
class CreateGoogleAdsGuide < ActiveRecord::Migration[8.1]
  def change
    create_table :google_ads_briefs do |t|
      t.json :answers, null: false, default: {}
      t.json :done_steps, null: false, default: []
      t.timestamps
    end

    create_table :google_ads_exclusion_lists do |t|
      t.string :name, null: false
      t.text :description
      t.text :keywords
      t.string :shared_set_id
      t.datetime :synced_at
      t.text :sync_error
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :google_ads_exclusion_lists, :name, unique: true

    add_column :google_ads_plans, :answers, :json, null: false, default: {}
    add_column :google_ads_plans, :done_steps, :json, null: false, default: []
    add_column :google_ads_plans, :exclusion_list_ids, :json, null: false, default: []
  end
end
