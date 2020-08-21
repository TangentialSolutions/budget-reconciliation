require "selenium-webdriver"
require "json"
require "pry"

DOWNLOAD_DIR = "./budgets".freeze
WEBDRIVER_URL = "http://127.0.0.1:4444/wd/hub".freeze

def log(message, data = {})
  puts message
  logger = File.open("./download.json", "a+")
  logger.write({message: message, data: data}.to_json)
  logger.close
end

def output_discrepencies(data)
  logger = File.open("./discrepancies.json", "a+")
  logger.write(data.to_json)
  logger.close
end

def download_budget(driver)
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
end

def search_in_usaa(driver)
  wait = Selenium::WebDriver::Wait.new(timeout: 10) # seconds
  previous_window_handle = driver.window_handle

  # Open new tab and navigate to usaa homepage
  driver.execute_script("window.open()")
  driver.switch_to.window( driver.window_handles.last )
  driver.navigate.to "https://www.usaa.com/"
  wait.until { driver.find_element(css: ".profileWidget") }

  # Navigate to login screen
  driver.find_element(css: ".profileWidget .profileWidget-button--logon").click
  wait.until { driver.find_element(css: ".ent-logon-jump-body-container") }

  # Enter login information
  driver.find_element(css: ".ent-logon-jump-input[name='j_username']").send_keys "dudeman92"
  # puts "Whats your USAA password?"
  # pass = gets
  # pass = pass.chomp
  driver.find_element(css: ".ent-logon-jump-input[name='j_password']").send_keys "" # pass
  driver.find_element(css: ".ent-logon-jump-button").click

  # Send verification code to default selected (should be text message)
  wait.until { driver.find_element(css: ".usaa-button[value='Send']") }
  driver.find_element(css: ".usaa-button[value='Send']").click

  wait.until { driver.find_element(css: ".notice.noticeUser") }
  puts "What was that verification code you got on your phone?"
  verification_code = gets
  verification_code = verification_code.chomp
  document.find_element(css: "input[type='password']").send_keys verification_code
  document.find_element(css: "button[type='submit']").click

  wait.until { document.find_element(css: ".accountNameSection") }
  acct = nil
  driver.find_elements(css: ".accountNameSection .acctName a").each do |e|
    if e.text.include? "USAA CLASSIC CHECKING"
      acct = e
      break
    end
  end
  raise StandardError.new("Checking account not found.") if acct.nil?

  acct.click
  wait.until { driver.find_element(css: "#AccountSummaryTransactionTable") }
  purchase_amounts = []
  driver.find_elements(css: "#AccountSummaryTransactionTable tbody.yui-dt-data tr").each do |transaction_row|
    amount_string = transaction_row.find_element(css: "td .dataQuantityNegative").value
    description = transaction_row.find_element(css: "td .transDesc").value
    next if amount_string.nil?

    # Sanitize
    amount_string["($"] = '' unless amount_string["($"].nil?
    amount_string[")"] = '' unless amount_string[")"].nil?
    amount_string[","] = '' unless amount_string[","].nil?

    purchase_amounts << { amount: amount_string, descr: description }
  end

  log "Purchases from USAA...", purchase_amounts.to_json

  driver.switch_to.window(previous_window_handle)
  purchase_amounts
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

# download_budget(driver)
usaa_transactions = search_in_usaa(driver)
usaa_amounts = usaa_transactions.pluck(:amount)

driver.find_element(css: ".TransactionsTabs-tab#allocated").click
wait.until { driver.find_element(css: ".ui-app-transaction-collection .transaction-card" ) }
not_tracked_in_ed = []
ed_easy_transactions = driver.find_element(css: ".ui-app-transaction-collection .transaction-card").each do |ed_easy_transaction_el|
  integer = ed_easy_transaction_el.find_element(css: ".money .money-integer").value
  cents = ed_easy_transaction_el.find_element(css: ".money .money-fractional").value
  amount_string = "#{integer}.#{cents}"
  next if usaa_amounts.include? amount_string

  not_tracked_in_ed << usaa_transactions[usaa_amounts.find_index(amount_string)]
end


ed_split_transactions = driver.find_elements(css: ".ui-app-transaction-collection .split-transaction-card .card-body").each do |ed_split_transaction|
    integer_sum = 0
    cents_sum = 0
    ed_split_transaction.find_elements(css: ".split-transaction-card").each do |transaction|
      integer_sum += transaction.find_element(css: ".money .money-integer").value.to_i
      cents_sum += transaction.find_element(css: ".money .money-fractional").value.to_i
    end
    integer_sum += cents_sum / 100
    cents_sum = cents_sum % 100
    amount_string = "#{integer_sum}.#{cents_sum}"
    next if usaa_amounts.include? amount_string

    not_tracked_in_ed << usaa_transactions[usaa_amounts.find_index(amount_string)]
end

output_discrepencies not_tracked_in_ed

driver.quit