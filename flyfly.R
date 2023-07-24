# Install necessary packages (if not already installed)
required_packages <- c("RSelenium", "rvest", "shiny", "DT")

# Check if each package is installed, and if not, install it
for (package in required_packages) {
  if (!requireNamespace(package, quietly = TRUE)) {
    install.packages(package, repos = "https://cran.rstudio.com")
  }
}

# Load necessary libraries
library(RSelenium)
library(rvest)
library(shiny)
library(DT)

# Function to connect to the remote Chrome WebDriver
start_chrome <- function() {
  driver <- rsDriver(browser = "chrome", chromever = "115.0.5790.102")
  driver$client$navigate("https://thefly.com/news.php?fecha=2023-07-22&analyst_recommendations=on&upgrade_filter=on&downgrade_filter=on&initiate_filter=on&no_change_filter=on&symbol=")
  # Wait for some time (adjust the time as needed to ensure the content is loaded)
  Sys.sleep(10)
  return(driver)
}

# Function to scroll down the webpage using JavaScript
scroll_down <- function(driver) {
  driver$client$executeScript("window.scrollTo(0, document.body.scrollHeight);")
}

# Function to scroll down to load more tables
scroll_down_to_load_tables <- function(driver) {
  max_scroll_attempts <- 10  # Adjust this value based on how many times you want to scroll down
  tables_count <- 0
  
  for (attempt in 1:max_scroll_attempts) {
    tables <- driver$client$findElements("xpath", "//table[contains(@class, 'week_day') and contains(@class, 'news_table')]")
    new_tables_count <- length(tables)
    
    if (new_tables_count > tables_count) {
      # New tables are loaded, continue scrolling
      tables_count <- new_tables_count
      scroll_down(driver)
      Sys.sleep(5)  # Wait for some time after scrolling to allow content to load
    } else {
      # No new tables are loaded, stop scrolling
      break
    }
  }
}
extract_price_target <- function(text) {
  # Use regular expression to extract the text between the words "to" and "from" or "at"
  matches <- gregexpr("to\\s+(.*?)(?:\\s+from|\\s+at|$)", text, ignore.case = TRUE)
  price_target <- regmatches(text, matches)[[1]]
  return(price_target)
}

scrape_data <- function(driver) {
  # Start the Chrome WebDriver and navigate to the webpage
  driver$client$navigate("https://thefly.com/news.php?fecha=2023-07-22&analyst_recommendations=on&upgrade_filter=on&downgrade_filter=on&initiate_filter=on&no_change_filter=on&symbol=")
  
  # Wait for some time to allow initial content to load
  Sys.sleep(5)
  
  # Scroll down to load more tables
  scroll_down_to_load_tables(driver)
  
  # Find all tables with class "week_day news_table"
  tables <- driver$client$findElements("xpath", "//table[contains(@class, 'week_day') and contains(@class, 'news_table')]")
  
  # Scrape data from each table
  data <- list()
  for (table in tables) {
    table_html <- table$getElementAttribute("outerHTML")[[1]]
    table <- read_html(table_html)
    
    # Extract data from the current table
    spans <- table %>% html_nodes(xpath = "//span[contains(., 'price target')]")
    page_data <- lapply(spans, function(span) {
      text <- html_text(span)
      sentences <- strsplit(text, "price target", fixed = TRUE)[[1]]
      sentences <- trimws(sentences)
      company_name <- sentences[1]
      analyst <- gsub(".* at\\s+(.*)", "\\1", text)
      price_target <- extract_price_target(text)
      upgrade_downgrade <- ifelse(grepl("target raised", text), "Raised", "Lowered")
      
      data.frame(CompanyName = company_name, UpgradeDowngrade = upgrade_downgrade, Analyst = analyst, PriceTarget = price_target)
    })
    
    # Append the data from the current table to the list
    data <- c(data, page_data)
  }
  
  # Combine data from multiple tables into a single data frame
  final_data <- do.call(rbind, data)
  
  
  
  return(final_data)
}

# Step 1: Connect to the remote Chrome WebDriver
driver <- start_chrome()

# Step 2: Build Shiny app
ui <- fluidPage(
  titlePanel("Real-Time Stock Recommendations"),
  DTOutput("table")
)

server <- function(input, output, session) {
  # Use a reactive value to store the data
  data <- reactiveVal(NULL)
  
  # Function to refresh data at regular intervals
  autoInvalidate <- reactiveTimer(300000)
  
  observeEvent(autoInvalidate(), {
    # Call the scraper function to get the latest data
    scraped_data <- scrape_data(driver)
    # Update the reactive value with the new data
    data(scraped_data)
  })
  
  output$table <- renderDT({
    # Get the data from the reactive value
    current_data <- data()
    # Show the data in the table
    datatable(current_data, options = list(pageLength = 10))
  })
}

# Step 3: Stop Chrome WebDriver when the Shiny app is closed
onStop(function() {
  driver$client$close()
})

# Step 4: Run the Shiny app
shinyApp(ui = ui, server = server, options = list(port = 8080))
