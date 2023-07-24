import time
import re
from selenium import webdriver
from bs4 import BeautifulSoup
from flask import Flask, render_template

# Function to connect to the remote Chrome WebDriver
def start_chrome():
    options = webdriver.ChromeOptions()
    options.add_argument("--headless")  # Optional: Run Chrome in headless mode (no GUI)
    driver = webdriver.Chrome(options=options)
    driver.get("https://thefly.com/news.php?fecha=2023-07-22&analyst_recommendations=on&upgrade_filter=on&downgrade_filter=on&initiate_filter=on&no_change_filter=on&symbol=")
    # Wait for some time (adjust the time as needed to ensure the content is loaded)
    time.sleep(10)
    return driver

# Function to scroll down the webpage using JavaScript
def scroll_down(driver):
    driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")

# Function to scroll down to load more tables
def scroll_down_to_load_tables(driver):
    max_scroll_attempts = 10  # Adjust this value based on how many times you want to scroll down
    tables_count = 0

    for attempt in range(max_scroll_attempts):
        tables = driver.find_elements_by_xpath("//table[contains(@class, 'week_day') and contains(@class, 'news_table')]")
        new_tables_count = len(tables)

        if new_tables_count > tables_count:
            # New tables are loaded, continue scrolling
            tables_count = new_tables_count
            scroll_down(driver)
            time.sleep(5)  # Wait for some time after scrolling to allow content to load
        else:
            # No new tables are loaded, stop scrolling
            break

def extract_price_target(text):
    # Use regular expression to extract the text between the words "to" and "from" or "at"
    matches = re.findall(r"to\s+(.*?)(?:\s+from|\s+at|$)", text, re.IGNORECASE)
    return matches[0] if matches else None

def scrape_data(driver):
    # Start the Chrome WebDriver and navigate to the webpage
    driver.get("https://thefly.com/news.php?fecha=2023-07-22&analyst_recommendations=on&upgrade_filter=on&downgrade_filter=on&initiate_filter=on&no_change_filter=on&symbol=")

    # Wait for some time to allow initial content to load
    time.sleep(5)

    # Scroll down to load more tables
    scroll_down_to_load_tables(driver)

    # Find all tables with class "week_day news_table"
    tables = driver.find_elements_by_xpath("//table[contains(@class, 'week_day') and contains(@class, 'news_table')]")

    # Scrape data from each table
    data = []
    for table in tables:
        table_html = table.get_attribute("outerHTML")
        soup = BeautifulSoup(table_html, "html.parser")

        # Extract data from the current table
        spans = soup.find_all("span", text=re.compile("price target", re.IGNORECASE))
        page_data = []
        for span in spans:
            text = span.get_text()
            sentences = re.split(r"price target", text, flags=re.IGNORECASE)
            sentences = [sentence.strip() for sentence in sentences]
            company_name = sentences[0]
            analyst = re.sub(r".* at\s+(.*)", "\\1", text)
            price_target = extract_price_target(text)
            upgrade_downgrade = "Raised" if re.search("target raised", text, re.IGNORECASE) else "Lowered"

            page_data.append({
                "CompanyName": company_name,
                "UpgradeDowngrade": upgrade_downgrade,
                "Analyst": analyst,
                "PriceTarget": price_target
            })

        # Append the data from the current table to the list
        data.extend(page_data)

    return data

# Step 1: Connect to the remote Chrome WebDriver
driver = start_chrome()

# Step 2: Build Flask app
app = Flask(__name__)

@app.route('/')
def index():
    # Call the scraper function to get the latest data
    scraped_data = scrape_data(driver)
    # Render the data in an HTML table
    return render_template("table.html", data=scraped_data)

# Step 3: Stop Chrome WebDriver when the Flask app is closed
@app.before_first_request
def setup():
    global driver
    def close_driver():
        driver.quit()
    app.teardown_appcontext(close_driver)

# Step 4: Run the Flask app
if __name__ == '__main__':
    app.run(debug=True)
