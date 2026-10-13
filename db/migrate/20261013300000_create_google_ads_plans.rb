# frozen_string_literal: true

# Campaign plans: what a campaign is for and how it's set up, its ad groups
# (keywords, landing page, ad copy), the negatives, and a checklist from
# research to the decision date.
class CreateGoogleAdsPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :google_ads_plans do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "planning"
      t.text :goal
      t.text :success
      t.text :audience
      t.decimal :daily_budget, precision: 10, scale: 2
      t.date :starts_on
      t.date :decision_on
      t.text :locations
      t.text :schedule
      t.string :bidding
      t.string :networks, null: false, default: "search"
      t.text :final_url_suffix
      t.string :campaign_id
      t.text :negatives
      t.text :notes
      t.timestamps
    end

    create_table :google_ads_plan_ad_groups do |t|
      t.references :plan, null: false, foreign_key: {to_table: :google_ads_plans, on_delete: :cascade}
      t.string :name, null: false
      t.string :landing_path
      t.text :keywords
      t.text :headlines
      t.text :descriptions
      t.string :path1
      t.string :path2
      t.text :notes
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :google_ads_plan_tasks do |t|
      t.references :plan, null: false, foreign_key: {to_table: :google_ads_plans, on_delete: :cascade}
      t.string :phase, null: false
      t.string :title, null: false
      t.text :hint
      t.string :repeats
      t.datetime :done_at
      t.string :done_by
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
