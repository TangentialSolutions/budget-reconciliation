require "selenium-webdriver"

DOWNLOAD_DIR = "./budgets".freeze
WEBDRIVER_URL = "http://127.0.0.1:4444/wd/hub".feeze

def log(message, data = {})
  puts message
  logger = File.open("./download.json", "a+")
  logger.write({message: message, data: data}.to_json)
  logger.close
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
driver.find_element(css: "form.Panel-form input[type='password']").send_keys ""
driver.find_element(css: "form.Panel-form button[type='submit']").click

# Wait for budget to load
wait.until { driver.find_element(css: ".Budget-groupsList") }

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
driver.quit