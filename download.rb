require "selenium-webdriver"
require "json"
require "csv"
require "pry"

module ScraperLogger
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
end

class Scraper
  include ScraperLogger

  WEBDRIVER_URL = "http://127.0.0.1:4444/wd/hub".freeze
  DOWNLOAD_DIR = "./budgets".freeze
  DRIVER_TIMEOUT = 10

  attr_reader :driver, :driver_url, :download_dir, :wait

  def initialize(webdriver_url: WEBDRIVER_URL, download_dir: DOWNLOAD_DIR, driver_timeout: DRIVER_TIMEOUT)
    log "Opening driver for #{self.class}..."

    @driver_url = webdriver_url
    @download_dir = download_dir
    @wait = Selenium::WebDriver::Wait.new(timeout: driver_timeout) # seconds
    @driver = Selenium::WebDriver.for :chrome, url: driver_url
  end

  def close
    driver.close
  end
end

class EverydollarScraper < Scraper
  def download_everydollar_budget
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

  def login_to_everydollar
    log "Navigating to main page..."
    driver.navigate.to "https://www.everydollar.com/app/sign-in"

    # Sign-in Form
    log "Signing in..."
    driver.find_element(css: "form#emailForm input#emailInput").send_keys "tbtrevbroaddus@gmail.com"
    driver.find_element(css: "form#emailForm button[type='submit']").click

    wait.until { driver.find_element(css: "div.auth0-login input[type='password']") }

    puts "Whats your EveryDollar password?"
    pass = gets
    pass = pass.chomp
    driver.find_element(css: "div.auth0-login input[type='password']").send_keys pass
    driver.find_element(css: "div.auth0-login button.auth0-lock-submit").click

    # Wait for budget to load
    wait.until { driver.find_element(css: ".Budget-groupsList") }

    log "Budget loaded..."
    announcement = driver.find_elements(css: "#Modal_close")
    if announcement.size > 0
      announcement.first.click
    end
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

  def scrape_split_transactions(ed_split_transaction_el, usaa_amounts)
    day_el = ed_split_transaction_el.find_elements(css: ".day")
    return if day_el.size == 0
    return if day_el.first.text != "AUG"

    integer_sum = 0
    cents_sum = 0
    merchants = []
    ed_split_transaction_el.find_elements(css: ".split-transaction-card").each do |transaction|
      integer_sum += transaction.find_element(css: ".money .money-integer").text.to_i
      cents_sum += transaction.find_element(css: ".money .money-fractional").text.to_i
      merchant = transaction.find_element(css: ".transaction-card-merchant").text
      budget = transaction.find_element(css: ".transaction-card-budget-item").text
      merchants << "#{merchant} - #{budget}"
    end
    integer_sum += cents_sum / 100
    cents_sum = cents_sum % 100
    amount_string = "#{integer_sum}.#{cents_sum}"

    { amount: amount_string, desc: merchants.join(" & ") }
  end

  def load_all_easy_transactions
    driver.find_element(css: "#IconTray_transactions .IconTray-icon").click
    driver.execute_script("document.querySelector('.TransactionsTabs-tab#allocated').click()")

    wait.until { driver.find_element(css: ".ui-app-transaction-collection .transaction-card") }
    last_transaction_el = driver.find_element(css: '.ui-app-transaction-collection > div > div:last-child')
    day_el = last_transaction_el.find_elements(css: ".day")

    while (day_el.size > 0 && day_el.first.text == "AUG")
      driver.execute_script('document.querySelector(".TransactionDrawer-tabContent").scroll(0, 1000000000)')
      last_transaction_el = driver.find_element(css: '.ui-app-transaction-collection > div > div:last-child')
      day_el = last_transaction_el.find_elements(css: ".day")
    end
  end
end

class UsaaScraper < Scraper
  def login_to_usaa
    # previous_window_handle = driver.window_handle
    #
    # log "Opening tab for USAA..."
    # # Open new tab and navigate to usaa homepage
    # driver.execute_script("window.open()")
    # driver.switch_to.window( driver.window_handles.last )
    driver.navigate.to "https://www.usaa.com/"
    wait.until { driver.find_element(css: ".usaa-globalHeader-wrapper") }

    log "Navigating to login screen..."
    # Navigate to login screen
    driver.find_element(css: ".usaa-globalHeader-wrapper > a:last-of-type").click
    wait.until { driver.find_element(css: ".miam-logon-form") }

    log "Logging in..."
    # Enter login information
    driver.find_element(css: ".miam-logon-form form input[name='memberId']").send_keys "dudeman92"
    driver.find_element(css: ".miam-logon-form form button[type='submit']").click
    wait.until { driver.find_element(css: ".miam-logon-form form input[name='password']") }
    # puts "Whats your USAA password?"
    # pass = gets
    # pass = pass.chomp
    driver.find_element(css: ".miam-logon-form form input[name='password']").send_keys "" # pass
    driver.find_element(css: ".miam-logon-form form button[type='submit']").click

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
  end

  def download_usaa_export
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

    export_link = nil
    driver.find_elements(css: "#account-transactions-header .transtable-controls ul.first-of-type li a").each do |a|
      export_link = a if a.text.downcase.include? "export"
    end
    raise StandardError.new("Couldn't find export link.") if export_link.nil?

    export_link.click
  end

  def generate_transaction_csv
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
    filename = "#{DOWNLOAD_DIR}/09-2021-Usaa-Transactions.csv" # @todo rewrite so that filename is dynamic
    csv = CSV.open(filename)
    csv << %w[description amount]
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
      csv << [description, amount_string]
    end
    csv.close

    log "Saved purchases to #{filename}..."
  end
end

def scrape
  ed_scraper = EverydollarScraper.new
  usaa_scraper = UsaaScraper.new

  ed_scraper.login_to_everydollar
  ed_scraper.load_all_easy_transactions

  usaa_transactions = search_in_usaa(driver)
  usaa_amounts = usaa_transactions.map {|t| t[:amount]}

  ed_transactions = []
  not_tracked_in_usaa = []

  ed_easy_transactions = driver.find_elements(css: ".ui-app-transaction-collection .transaction-card").each do |ed_easy_transaction_el|
    result = scrape_easy_transactions(ed_easy_transaction_el, usaa_amounts)
    next if result.nil?

    ed_transactions << result

    next if usaa_amounts.include? result[:amount]

    not_tracked_in_usaa << result
  end

  ed_split_transactions = driver.find_elements(css: ".ui-app-transaction-collection .split-transaction-card .card-body").each do |ed_split_transaction_el|
    result = scrape_split_transactions(ed_split_transaction_el, usaa_amounts)
    next if result.nil?

    ed_transactions << result

    next if usaa_amounts.include? result[:amount]

    log "Discrepancy(not found in USAA) - split transaction #{result[:amount]} for #{result[:descr]}"
    not_tracked_in_usaa << result
  end

  ed_amounts = ed_transactions.map {|t| t[:amount]}
  not_tracked_in_ed = []
  usaa_transactions.each do |transaction|
    next if ed_amounts.include? transaction[:amount]

    log "Discrepancy(not found in ED) - #{transaction[:amount]} for #{transaction[:descr]}"
    not_tracked_in_ed << transaction
  end

  ed_scraper.output_discrepencies(:usaa, not_tracked_in_usaa)
  ed_scraper.output_discrepencies(:everdollar, not_tracked_in_ed)

  driver.quit
end

def download
  # ed_scraper = EverydollarScraper.new
  # ed_scraper.login_to_everydollar
  # ed_scraper.download_everydollar_budget
  # ed_scraper.close

  bank_scraper = UsaaScraper.new
  bank_scraper.login_to_usaa
  bank_scraper.generate_transaction_csv
  bank_scraper.close
end

download