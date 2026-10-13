# frozen_string_literal: true

require "csv"

# A plan as a CSV for Google Ads Editor (Account › Import › From file): the
# campaign, its ad groups, keywords, a responsive search ad each, and the
# negatives (its own and its exclusion lists', as campaign negatives, for an
# account the API can't reach), so it's built in one import and reviewed there before posting.
class GoogleAds::PlanExport
  HEADERS = ["Campaign", "Campaign Daily Budget", "Campaign Type", "Networks", "Campaign Status", "Ad Group", "Ad Group Status",
    "Keyword", "Criterion Type", "Ad type", *(1..15).map { "Headline #{it}" }, *(1..4).map { "Description #{it}" },
    "Path 1", "Path 2", "Final URL", "Final URL suffix"].freeze

  MATCH = {"PHRASE" => "Phrase", "EXACT" => "Exact", "BROAD" => "Broad"}.freeze
  NETWORKS = {"search" => "Google search", "search_partners" => "Google search;Search Partners", "search_display" => "Google search;Display Network"}.freeze

  def initialize(plan, site_url: nil)
    @plan = plan
    @site_url = site_url.to_s.chomp("/")
  end

  def filename = "#{@plan.name.parameterize}-ads-editor.csv"

  def to_csv
    CSV.generate do |csv|
      csv << HEADERS
      csv << row("Campaign Daily Budget" => @plan.daily_budget&.to_f, "Campaign Type" => "Search", "Networks" => NETWORKS.fetch(@plan.networks),
        "Campaign Status" => "Paused", "Final URL suffix" => @plan.final_url_suffix)
      @plan.ad_groups.each do |group|
        csv << row("Ad Group" => group.name, "Ad Group Status" => "Enabled")
        group.keyword_list.each { csv << row("Ad Group" => group.name, "Keyword" => it[:text], "Criterion Type" => MATCH.fetch(it[:match_type])) }
        ad = {"Ad Group" => group.name, "Ad type" => "Responsive search ad", "Path 1" => group.path1, "Path 2" => group.path2, "Final URL" => url(group.landing_path)}
        group.headline_list.first(15).each_with_index { |text, index| ad["Headline #{index + 1}"] = text }
        group.description_list.first(4).each_with_index { |text, index| ad["Description #{index + 1}"] = text }
        csv << row(ad)
      end
      @plan.all_negatives.uniq { [it[:text], it[:match_type]] }.each { csv << row("Keyword" => it[:text], "Criterion Type" => "Negative #{MATCH.fetch(it[:match_type])}") }
    end
  end

  private

  def row(values) = HEADERS.map { (it == "Campaign") ? @plan.name : values[it] }

  def url(path)
    return path if path.blank? || path.match?(%r{\Ahttps?://}i)

    "#{@site_url}/#{path.delete_prefix("/")}"
  end
end
