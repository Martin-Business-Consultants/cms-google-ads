# frozen_string_literal: true

# The ad accounts a sign-in reaches, named, to pick from in Settings ›
# Google Ads; when there's just one, it's chosen. A manager (MCC) account is
# listed too, marked, since its id is what goes in login_customer_id.
module GoogleAds::Accounts
  module_function

  def load(client: GoogleAds::Client.new)
    accounts = client.accessible_customers.first(25).map do |id|
      row = client.search("SELECT customer.id, customer.descriptive_name, customer.manager, customer.currency_code, customer.time_zone FROM customer LIMIT 1", customer_id: id).first.to_h
      customer = row["customer"].to_h
      ["#{customer["descriptiveName"].presence || "Account"} (#{id.scan(/\A(\d{3})(\d{3})(\d+)\z/).flatten.join("-").presence || id})", id,
        customer["manager"] ? "manager" : nil, customer["currencyCode"], customer["timeZone"]]
    rescue GoogleAds::Error
      ["#{id} (not readable without a manager id)", id, nil, nil, nil]
    end
    GoogleAds::Settings.remember("accounts" => accounts)
    choose(accounts)
    accounts
  end

  # The one non-manager account, chosen, when there's no choice to make; and its currency and time zone.
  def choose(accounts)
    settings = GoogleAds::Settings.current
    pick = accounts.find { it[1] == settings.customer_id } || (accounts.reject { it[2] }.one? && accounts.reject { it[2] }.first)
    return unless pick

    GoogleAds::Settings.remember({"customer_id" => pick[1], "currency" => pick[3], "time_zone" => pick[4]}.compact)
  end
end
