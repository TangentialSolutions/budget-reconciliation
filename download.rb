require "selenium-webdriver"
require "json"
require "csv"
require "pry"

DOWNLOAD_DIR = "./budgets".freeze
WEBDRIVER_URL = "http://127.0.0.1:4444/wd/hub".freeze

def log(message, data = {})
  puts message
  logger = File.open("./download.json", "a+")
  logger.write({message: message, data: data}.to_json)
  logger.close
end

def output_discrepencies(subject, data)
  logger = File.open("./not_tracked_in_#{subject}_discrepancies.json", "a+")
  logger.write(data.to_json)
  logger.close
end

def download_budget(driver)
  # return CSV.read "./budgets/08-2020-EveryDollar-Transactions.csv", quote_char: "|"

  wait = Selenium::WebDriver::Wait.new(timeout: 10) # seconds

  # Scroll to bottom of page
  driver.execute_script("document.querySelectorAll('.Budget-bottomActions')[0].scrollIntoView(false)")

  # Download CSV
  download_csv_link = driver.find_element(css: ".Budget-bottomActions a.DownloadCSV")
  download_filename = download_csv_link["download"]

  log "Starting download..."
  download_csv_link.click

  log "Waiting to for download to finish..."
  wait.until { File.exist?(File.expand_path "#{DOWNLOAD_DIR}/#{download_filename}") }

  if !File.exist?(File.expand_path "#{DOWNLOAD_DIR}/#{download_filename}")
    log "Unable to download CSV", {
        filename: download_filename,
        download_element: download_csv_link.as_json
    }
  end

  log "Successfully downloaded csv", {location: "#{DOWNLOAD_DIR}/#{download_filename}"}
  CSV.read "#{DOWNLOAD_DIR}/#{download_filename}", quote_char: "|"
end

def search_in_usaa(driver)
  # Simple/rough cache so I don't have to peg USAA
  # @todo Smart'en this up to check if the file exists first
  # file = File.open "./usaa_cache.json"
  # cached = JSON.load file
  # return cached unless cached.empty?

  wait = Selenium::WebDriver::Wait.new(timeout: 10) # seconds
  previous_window_handle = driver.window_handle

  log "Opening tab for USAA..."
  # Open new tab and navigate to usaa homepage
  driver.execute_script("window.open()")
  driver.switch_to.window( driver.window_handles.last )
  driver.navigate.to "https://www.usaa.com/"
  wait.until { driver.find_element(css: ".profileWidget") }

  log "Navigating to login screen..."
  # Navigate to login screen
  driver.find_element(css: ".profileWidget .profileWidget-button--logon").click
  wait.until { driver.find_element(css: ".ent-logon-jump-body-container") }

  log "Logging in..."
  # Enter login information
  driver.find_element(css: ".ent-logon-jump-input[name='j_username']").send_keys "dudeman92"
  # puts "Whats your USAA password?"
  # pass = gets
  # pass = pass.chomp
  driver.find_element(css: ".ent-logon-jump-input[name='j_password']").send_keys "" # pass
  driver.find_element(css: ".ent-logon-jump-button").click

  log "Sending verification code..."
  # Send verification code to default selected (should be text message)
  wait.until { driver.find_element(css: ".usaa-button[value='Send']") }
  driver.find_element(css: ".usaa-button[value='Send']").click

  log "Prepare to enter verification code on cell..."
  wait.until { driver.find_element(css: ".notice.noticeUser") }
  puts "What was that verification code you got on your phone?"
  verification_code = gets
  verification_code = verification_code.chomp
  driver.find_element(css: "input[type='password']").send_keys verification_code
  driver.find_element(css: "button[type='submit']").click

  log "Finding checking account..."
  wait.until { driver.find_element(css: ".portalContent-container") }
  driver.navigate.to driver.find_element(css: ".gadgets-gadget").attribute("src")
  acct = nil
  driver.find_elements(css: ".accountNameSection .acctName a").each do |e|
    puts "Checking element: #{e.text}"
    if e.text.include? "USAA CLASSIC CHECKING"
      acct = e
      break
    end
  end
  raise StandardError.new("Checking account not found.") if acct.nil?

  log "Navigating to checking account page..."
  acct.click
  wait.until { driver.find_element(css: "#AccountSummaryTransactionTable tbody.yui-dt-data tr") }
  purchase_amounts = []

  log "Parsing transactions..."
  driver.find_elements(css: "#AccountSummaryTransactionTable tbody.yui-dt-data tr").each do |transaction_row|
    # Transactions that are income (not expenses) will not have this class. Using #find_elements allows us to
    # get an empty [] as a return, which lets us know if it exists or not. We know there is only one element,
    # so we grab .first and are on our happy path way.
    found_quantity = transaction_row.find_elements(css: "td .dataQuantityNegative")
    next if found_quantity.size == 0
    amount_string = found_quantity.first.text
    description = transaction_row.find_element(css: "td .transDesc").text
    next if amount_string.nil?

    # Sanitize
    amount_string["($"] = '' unless amount_string["($"].nil?
    amount_string[")"] = '' unless amount_string[")"].nil?
    amount_string[","] = '' unless amount_string[","].nil?

    log "Amount found: $#{amount_string} - #{description}"
    purchase_amounts << { amount: amount_string, descr: description }
  end

  log "Purchases from USAA...", purchase_amounts.to_json

  driver.switch_to.window(previous_window_handle)
  purchase_amounts
end

def scrape_easy_transactions(ed_easy_transaction_el, usaa_amounts)
  day_el = ed_easy_transaction_el.find_elements(css: ".day")
  return nil if day_el.size == 0
  return nil if day_el.first.text != "AUG"

  integer = ed_easy_transaction_el.find_element(css: ".money .money-integer").text
  cents = ed_easy_transaction_el.find_element(css: ".money .money-fractional").text
  amount_string = "#{integer}.#{cents}"

  merchant = ed_easy_transaction_el.find_element(css: ".transaction-card-merchant").text
  budget = ed_easy_transaction_el.find_element(css: ".transaction-card-budget-item").text

  return nil if usaa_amounts.include? amount_string

  log "Discrepancy(not found in USAA) #{amount_string} for #{merchant} - #{budget}"

  {amount: amount_string, desc: "#{merchant} - #{budget}"}
end

def load_all_easy_transactions(driver)
  last_transaction_el = driver.find_element(css: '.ui-app-transaction-collection > div > div:last-child')
  day_el = last_transaction_el.find_elements(css: ".day")

  while (day_el.size > 0 && day_el.first.text == "AUG")
    driver.execute_script('document.querySelector(".TransactionDrawer-tabContent").scroll(0, 1000000000)')
    last_transaction_el = driver.find_element(css: '.ui-app-transaction-collection > div > div:last-child')
    day_el = last_transaction_el.find_elements(css: ".day")
  end
end

wait = Selenium::WebDriver::Wait.new(timeout: 10) # seconds

log "Opening driver..."
driver = Selenium::WebDriver.for :chrome, url: WEBDRIVER_URL

log "Navigating to main page..."
driver.navigate.to "https://www.everydollar.com/"

# Click login link
driver.find_elements(css: ".DesktopBanner .DesktopBanner-link[href='/app/sign-in'").first.click

wait.until { driver.find_element(css: "form.Panel-form") }

# Sign-in Form
log "Signing in..."
driver.find_element(css: "form.Panel-form input[type='email']").send_keys "tbtrevbroaddus@gmail.com"
puts "Whats your EveryDollar password?"
pass = gets
pass = pass.chomp
driver.find_element(css: "form.Panel-form input[type='password']").send_keys pass
driver.find_element(css: "form.Panel-form button[type='submit']").click

# Wait for budget to load
wait.until { driver.find_element(css: ".Budget-groupsList") }
announcement = driver.find_elements(css: "#Modal_close")
if announcement.size > 0
  announcement.first.click
end

usaa_transactions = search_in_usaa(driver)
usaa_amounts = usaa_transactions.map {|t| t[:amount]}
# data = download_budget(driver)

# log "Reconciling ED -> USAA", {data: data}
# not_tracked_in_usaa = []
# data.each_with_index do |item, index|
#   # header row
#   next if index == 0
#
#   # The CSV file is read in such a way that it stores the strings with double quotes **sigh**
#   next if item[2] != "\"expense\""
#   next unless item[3]["07"].nil?
#   amount_string = item.last
#
#   # Sanitize
#   amount_string["\""] = ""
#   amount_string["\""] = ""
#   amount_string["-"] = "" unless amount_string["-"].nil?
#   log "Processing #{amount_string}"
#   next if usaa_amounts.include? amount_string
#
#   log "ED amount not in USAA: #{amount_string}"
#   not_tracked_in_usaa << {amount: amount_string, desc: item[4]}
# end

driver.find_element(css: "#IconTray_transactions .IconTray-icon").click
driver.execute_script("document.querySelector('.TransactionsTabs-tab#allocated').click()")

wait.until { driver.find_element(css: ".ui-app-transaction-collection .transaction-card") }
ed_transactions = []
not_tracked_in_usaa = []

load_all_easy_transactions(driver)

ed_easy_transactions = driver.find_elements(css: ".ui-app-transaction-collection .transaction-card").each do |ed_easy_transaction_el|

  result = scrape_easy_transactions(ed_easy_transaction_el, usaa_amounts)
  ed_transactions << result

  next if result.nil?

  not_tracked_in_usaa << result
end

ed_split_transactions = driver.find_elements(css: ".ui-app-transaction-collection .split-transaction-card .card-body").each do |ed_split_transaction_el|
  day_el = ed_split_transaction_el.find_elements(css: ".day")
  next if day_el.size == 0
  next if day_el.first.text != "AUG"

  integer_sum = 0
  cents_sum = 0
  merchants = []
  ed_split_transaction_el.find_elements(css: ".split-transaction-card").each do |transaction|
    binding.pry
    integer_sum += transaction.find_element(css: ".money .money-integer").text.to_i
    cents_sum += transaction.find_element(css: ".money .money-fractional").text.to_i
    merchant = transaction.find_element(css: ".transaction-card-merchant").text
    budget = transaction.find_element(css: ".transaction-card-budget-item").text
    merchants << "#{merchant} - #{budget}"
  end
  integer_sum += cents_sum / 100
  cents_sum = cents_sum % 100
  amount_string = "#{integer_sum}.#{cents_sum}"

  ed_transactions << {amount: amount_string, desc: merchants.join(" & ")}

  next if usaa_amounts.include? amount_string

  log "Discrepancy(not found in USAA) - split transaction #{amount_string} for #{merchants.join(" & ")}"
  not_tracked_in_usaa << {amount: amount_string, desc: merchants.join(" & ")}
end

ed_amounts = ed_transactions.map {|t| t[:amount]}
not_tracked_in_ed = []
binding.pry
usaa_transactions.each do |transaction|
  next if ed_amounts.include? transaction[:amount]

  log "Discrepancy(not found in ED) - #{transaction[:amount]} for #{transaction[:descr]}"
  not_tracked_in_ed << transaction
end

output_discrepencies(:usaa, not_tracked_in_usaa)
output_discrepencies(:everdollar, not_tracked_in_ed)

driver.quit