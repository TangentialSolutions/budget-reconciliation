require "selenium-webdriver"

puts "Opening driver..."
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument('--ignore-certificate-errors')
options.add_argument('--disable-popup-blocking')
options.add_argument('--disable-translate')
driver = Selenium::WebDriver.for :chrome, options: options

puts "Navigating to main page..."
driver.navigate.to "https://www.everydollar.com/"

puts "Quitting..."
driver.quit
