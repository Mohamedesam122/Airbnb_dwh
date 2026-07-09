"""
fill_vatican_data.py
---------------------
Fills missing values for "Holy See (Vatican City State)" in `merged_df1`
by scraping Italy's data (since Vatican City is not listed separately on
most public data sources).

Data sources:
  1. Numbeo (https://www.numbeo.com/cost-of-living/rankings_by_country.jsp)
     -> Cost of Living Index, Rent Index, Groceries Index, Restaurant Price Index
  2. Wikipedia "World Happiness Report" article
     -> Happiness score and GDP per capita for Italy

Requirements:
  pip install selenium
  A matching ChromeDriver must be installed / available on PATH
  (Selenium Manager, bundled with Selenium 4.6+, will download it automatically
  if you don't already have one).

  On Google Colab specifically, do NOT use the apt `chromium-browser` /
  `chromium-chromedriver` packages — they are outdated and broken there.
  Instead run:
      !pip install -q selenium
      !wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
      !apt-get install -q -y /tmp/chrome.deb
  and call fill_vatican_missing_values(merged_df1, colab=True).

Usage:
  from fill_vatican_data import fill_vatican_missing_values
  merged_df1 = fill_vatican_missing_values(merged_df1)
"""

import re
import time
from typing import Optional

import pandas as pd
from selenium import webdriver
from selenium.common.exceptions import (
    NoSuchElementException,
    TimeoutException,
    WebDriverException,
)
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait



NUMBEO_URL = "https://www.numbeo.com/cost-of-living/rankings_by_country.jsp"
WIKI_HAPPINESS_URL = "https://en.wikipedia.org/wiki/World_Happiness_Report"

WAIT_TIMEOUT = 15  # seconds, used for every explicit wait


def _build_driver(
    headless: bool = True,
    colab: bool = False,
    chromedriver_path: Optional[str] = "/usr/local/bin/chromedriver",
) -> webdriver.Chrome:
    """
    Create and configure a Chrome WebDriver instance (Selenium 4 style).

    Set colab=True when running inside Google Colab.

    IMPORTANT: Colab's apt `chromium-browser` / `chromium-chromedriver` packages
    are outdated and broken (they depend on snapd, which doesn't work in the
    Colab container, and pull in a ~2020-era Chromium build). Do NOT use them.
    Instead, install real Google Chrome directly:

        !pip install -q selenium
        !wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
        !apt-get install -q -y /tmp/chrome.deb

    Selenium Manager (Selenium 4.6+'s built-in driver auto-downloader)
    sometimes fails inside Colab's container ("Unable to obtain driver for
    chrome"), so on Colab we instead download a matching chromedriver
    ourselves and point Selenium at it explicitly via chromedriver_path:

        CHROME_VERSION=$(google-chrome-stable --version | grep -oP '[\\d]+\\.[\\d]+\\.[\\d]+\\.[\\d]+')
        MILESTONE=$(echo $CHROME_VERSION | cut -d. -f1)
        DRIVER_URL=$(curl -s https://googlechromelabs.github.io/chrome-for-testing/latest-versions-per-milestone-with-downloads.json \
          | python3 -c "import json,sys; d=json.load(sys.stdin); print([x['url'] for x in d['milestones']['$MILESTONE']['downloads']['chromedriver'] if x['platform']=='linux64'][0])")
        wget -q -O /tmp/chromedriver.zip "$DRIVER_URL"
        unzip -o -q /tmp/chromedriver.zip -d /tmp/chromedriver_extracted
        find /tmp/chromedriver_extracted -name chromedriver -exec cp {} /usr/local/bin/chromedriver \\;
        chmod +x /usr/local/bin/chromedriver
    """
    import os
    from selenium.webdriver.chrome.service import Service

    options = Options()
    if headless:
        options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=1920,1080")
    options.add_argument(
        "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    )

    if colab:
        # Real Google Chrome, installed via the .deb (see docstring above).
        options.binary_location = "/usr/bin/google-chrome-stable"

        # Prefer an explicitly downloaded chromedriver over Selenium Manager,
        # since Selenium Manager can fail to resolve a driver inside Colab.
        if chromedriver_path and os.path.exists(chromedriver_path):
            service = Service(executable_path=chromedriver_path)
            return webdriver.Chrome(service=service, options=options)

    # Selenium 4.6+ ships Selenium Manager, which auto-detects the browser
    # (via binary_location, if set) and downloads a matching chromedriver.
    driver = webdriver.Chrome(options=options)
    return driver


def _parse_float(text: str) -> Optional[float]:
    """Extract the first float found in a string, e.g. '65.1' from '65.1 ' or '65.1%'."""
    match = re.search(r"[-+]?\d*\.\d+|\d+", text)
    return float(match.group()) if match else None


def _cell_text(element) -> str:
    """
    Get an element's text content reliably.

    Selenium's `.text` property depends on the element being "visible"
    (non-zero rendered size), which can silently return "" in headless mode
    for some pages/skins even when the element clearly has content. Reading
    the `textContent` DOM attribute instead works regardless of visibility.
    """
    value = element.get_attribute("textContent")
    return value.strip() if value else ""


def scrape_cost_of_living_indices(driver: webdriver.Chrome) -> dict:
    """
    Scrape Cost of Living Index, Rent Index, Groceries Index and
    Restaurant Price Index for Italy from Numbeo's "Cost of Living Index by
    Country" ranking page (one row per country).

    Returns a dict with any of the four keys that were successfully scraped.
    Missing/failed values are simply omitted from the dict.
    """
    results = {}
    wait = WebDriverWait(driver, WAIT_TIMEOUT)

    # Column headers we care about, as they appear on the Numbeo ranking page,
    # mapped to our target DataFrame column names.
    wanted_headers = {
        "cost of living index": "Cost of Living Index",
        "rent index": "Rent Index",
        "groceries index": "Groceries Index",
        "restaurant price index": "Restaurant Price Index",
    }

    try:
        driver.get(NUMBEO_URL)

        # Wait until at least one table is present, then find the *specific*
        # table that has the columns we need (the page also contains layout/
        # navigation tables that aren't the data table).
        wait.until(EC.presence_of_element_located((By.TAG_NAME, "table")))
        candidate_tables = driver.find_elements(By.TAG_NAME, "table")

        table = None
        country_col_idx = None
        target_col_idx = {}  # column_index -> our column name

        for candidate in candidate_tables:
            header_cells = candidate.find_elements(By.TAG_NAME, "th")
            if not header_cells:
                continue

            header_texts = [_cell_text(cell).lower() for cell in header_cells]
            if "country" not in header_texts:
                continue

            local_country_idx = None
            local_target_idx = {}
            for idx, text in enumerate(header_texts):
                if text == "country":
                    local_country_idx = idx
                elif text in wanted_headers:
                    local_target_idx[idx] = wanted_headers[text]

            if local_country_idx is not None and local_target_idx:
                table = candidate
                country_col_idx = local_country_idx
                target_col_idx = local_target_idx
                break

        if table is None:
            print("[Numbeo] Could not locate the country ranking table on the page.")
            return results

        # Scan data rows for Italy.
        rows = table.find_elements(By.TAG_NAME, "tr")
        for row in rows:
            cells = row.find_elements(By.TAG_NAME, "td")
            if len(cells) <= country_col_idx:
                continue

            country_name = _cell_text(cells[country_col_idx])
            if country_name.lower() != "italy":
                continue

            for col_idx, target_col in target_col_idx.items():
                if col_idx >= len(cells):
                    continue
                value = _parse_float(_cell_text(cells[col_idx]))
                if value is not None:
                    results[target_col] = value

            break  # found Italy's row, no need to keep scanning

    except TimeoutException:
        print("[Numbeo] Timed out waiting for the cost of living ranking table to load.")
    except NoSuchElementException:
        print("[Numbeo] Expected table structure (header row) was not found.")
    except WebDriverException as e:
        print(f"[Numbeo] WebDriver error while scraping cost of living data: {e}")

    return results


def scrape_happiness_and_gdp(driver: webdriver.Chrome, verbose: bool = True) -> dict:
    """
    Scrape Italy's happiness score and GDP-per-capita figure from the
    Wikipedia "World Happiness Report" article.

    The article contains one ranking table per report year. Only the most
    recent table has the full set of columns (score + GDP per capita, etc.);
    older ones are score-only or rank-only. We scan tables in order and use
    the first one whose header row contains both a "country" column and a
    "score" column, then read Italy's row from it by header position (not by
    a fixed column index, since layouts vary by year).

    Returns a dict with 'happiness_score' and/or 'gdp_per_capita' if found.
    """
    results = {}
    wait = WebDriverWait(driver, WAIT_TIMEOUT)

    try:
        driver.get(WIKI_HAPPINESS_URL)

        wait.until(
            EC.presence_of_element_located((By.CSS_SELECTOR, "table.wikitable"))
        )
        tables = driver.find_elements(By.CSS_SELECTOR, "table.wikitable")

        if verbose:
            print(f"[Wikipedia] Found {len(tables)} table(s) with class 'wikitable'.")

        for table_num, table in enumerate(tables):
            header_cells = table.find_elements(By.TAG_NAME, "th")
            header_texts = [_cell_text(cell).lower() for cell in header_cells]

            if verbose:
                print(f"[Wikipedia] Table {table_num} headers: {header_texts}")

            if not header_texts:
                continue

            country_idx = None
            score_idx = None
            gdp_idx = None
            for idx, text in enumerate(header_texts):
                if country_idx is None and ("country" in text or "nation" in text):
                    country_idx = idx
                elif score_idx is None and "score" in text:
                    score_idx = idx
                elif gdp_idx is None and "gdp" in text:
                    gdp_idx = idx

            if country_idx is None or score_idx is None:
                if verbose:
                    print(
                        f"[Wikipedia] Table {table_num} skipped "
                        f"(country_idx={country_idx}, score_idx={score_idx})."
                    )
                continue

            rows = table.find_elements(By.TAG_NAME, "tr")
            found_italy = False
            for row in rows:
                cells = row.find_elements(By.TAG_NAME, "td")

                needed_indices = [i for i in (country_idx, score_idx, gdp_idx) if i is not None]
                if not cells or len(cells) <= max(needed_indices):
                    continue

                country_name = _cell_text(cells[country_idx])
                if country_name.lower() != "italy":
                    continue

                found_italy = True

                if score_idx < len(cells):
                    score_val = _parse_float(_cell_text(cells[score_idx]))
                    if score_val is not None:
                        results["happiness_score"] = score_val

                if gdp_idx is not None and gdp_idx < len(cells):
                    gdp_val = _parse_float(_cell_text(cells[gdp_idx]))
                    if gdp_val is not None:
                        results["gdp_per_capita"] = gdp_val

                break  # found Italy's row in this table

            if verbose and not found_italy:
                print(f"[Wikipedia] Table {table_num} matched headers but no 'Italy' row was found.")

            if "happiness_score" in results:
                break

        if verbose and not results:
            print("[Wikipedia] No qualifying table/row produced any values.")

    except TimeoutException:
        print("[Wikipedia] Timed out waiting for the happiness report table to load.")
    except WebDriverException as e:
        print(f"[Wikipedia] WebDriver error while scraping happiness data: {e}")

    return results


def fill_vatican_missing_values(
    merged_df1: pd.DataFrame,
    headless: bool = True,
    colab: bool = False,
    chromedriver_path: Optional[str] = "/usr/local/bin/chromedriver",
) -> pd.DataFrame:
    """
    Fill missing values for 'Holy See (Vatican City State)' rows in merged_df1
    using data scraped for Italy (used as a proxy since Vatican City isn't
    listed separately in these datasets).

    Only NaN cells are overwritten; existing values are left untouched.

    Parameters
    ----------
    merged_df1 : pd.DataFrame
        The DataFrame containing a 'country' column and the target columns:
        'Cost of Living Index', 'Rent Index', 'Groceries Index',
        'Restaurant Price Index', 'happiness_score', 'gdp_per_capita'.
    headless : bool
        Whether to run Chrome in headless mode (default True).
    colab : bool
        Set True when running in Google Colab, so the driver points at the
        apt-installed Google Chrome binary (default False).
    chromedriver_path : Optional[str]
        Path to an explicitly downloaded chromedriver binary, used when
        colab=True to bypass Selenium Manager (which can fail to resolve a
        driver inside Colab's container). Ignored if the path doesn't exist.

    Returns
    -------
    pd.DataFrame
        The updated DataFrame (modified copy).
    """
    target_country = "Holy See (Vatican City State)"
    df = merged_df1.copy()

    mask = df["country"] == target_country
    if not mask.any():
        print(f"No rows found for '{target_country}'. Nothing to update.")
        return df

    driver = None
    scraped_values = {}

    try:
        driver = _build_driver(headless=headless, colab=colab, chromedriver_path=chromedriver_path)

        # 1. Cost of living style indices from Numbeo
        scraped_values.update(scrape_cost_of_living_indices(driver))

        # 2. Happiness score / GDP per capita from Wikipedia
        scraped_values.update(scrape_happiness_and_gdp(driver))

    except WebDriverException as e:
        print(f"Failed to start or drive the browser: {e}")
    finally:
        if driver is not None:
            driver.quit()

    if not scraped_values:
        print("No data could be scraped; DataFrame returned unchanged.")
        return df

    # Only fill columns that were actually scraped, and only where the
    # existing value is missing (NaN). Existing non-null values are preserved.
    for column, value in scraped_values.items():
        if column not in df.columns:
            continue
        rows_to_fill = mask & df[column].isna()
        df.loc[rows_to_fill, column] = value

    print("Scraped values applied:", scraped_values)
    return df


if __name__ == "__main__":
    # Example / manual test run.
    # Replace this block with your real merged_df1 when importing the module.
    example_df = pd.DataFrame(
        {
            "country": ["Italy", "Holy See (Vatican City State)"],
            "Cost of Living Index": [65.1, None],
            "Rent Index": [20.5, None],
            "Groceries Index": [60.0, None],
            "Restaurant Price Index": [55.0, None],
            "happiness_score": [6.0, None],
            "gdp_per_capita": [1.3, None],
        }
    )

    updated = fill_vatican_missing_values(example_df)
    print(updated)
