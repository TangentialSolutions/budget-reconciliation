require "selenium-webdriver"
DOWNLOAD_DIR = "~/Downloads".freeze

def log(message, data = {})
  puts message
  logger = File.open("./download.json", "a+")
  logger.write({message: message, data: data}.to_json)
  logger.close
end

def get_password
  `gpg --output doc --decrypt password.gpg`
  File.open("./doc", "r") do |file|
    password = file.readline
  end

  password
end

wait = Selenium::WebDriver::Wait.new(timeout: 10) # seconds

log "Opening driver..."
driver = Selenium::WebDriver.for :chrome

log "Navigating to main page..."
driver.navigate.to "https://www.everydollar.com/"

# Click login link
driver.find_elements(css: ".DesktopBanner .DesktopBanner-link[href='/app/sign-in'").first.click

wait.until { driver.find_element(css: "form.Panel-form") }

# Sign-in Form
driver.find_element(css: "form.Panel-form input[type='email']").send_keys "tbtrevbroaddus@gmail.com"
driver.find_element(css: "form.Panel-form input[type='password']").send_keys get_password
driver.find_element(css: "form.Panel-form button[type='submit']").click

# Wait for budget to load
wait.until { driver.find_element(css: ".Budget-groupsList") }

# Scroll to bottom of page
driver.execute_script("document.querySelectorAll('.Budget-bottomActions')[0].scrollIntoView(false)")

# Download CSV
download_csv_link = driver.find_element(css: ".Budget-bottomActions a.DownloadCSV")
download_filename = download_csv_link["download"]
download_csv_link.click

wait.until { File.exist?(File.expand_path "#{DOWNLOAD_DIR}/#{download_filename}") }

if !File.exist?(File.expand_path "#{DOWNLOAD_DIR}/#{download_filename}")
  log "Unable to download CSV", {
      filename: download_filename,
      download_element: download_csv_link.as_json
  }
end

log "Successfully downloaded csv", {location: "#{DOWNLOAD_DIR}/#{download_filename}"}
driver.quit