#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

import holidays
import numpy as np
import pandas as pd

# --------------------------------------------------------------------------
# Global settings
# --------------------------------------------------------------------------
START = pd.Timestamp("2023-01-01")
END = pd.Timestamp("2026-09-30")          # data cut-off ("today" in the ERP)
EXCISE_EUR_PER_HL_PURE_ALCOHOL = 1303.00  # German Alkoholsteuer, spirits
EXCISE_EUR_PER_L_PURE = EXCISE_EUR_PER_HL_PURE_ALCOHOL / 100
VAT = 0.19
FREIGHT = 0.04                            # inbound freight/handling on purchase cost
LOCATION = "BREMEN-HQ"

CATEGORIES = ["WHISKY", "GIN", "RUM", "VODKA", "LIQUEUR", "BRANDY"]
CATEGORY_COUNTS = {"WHISKY": 70, "GIN": 45, "RUM": 40, "VODKA": 30, "LIQUEUR": 40, "BRANDY": 25}

# Monthly seasonality per category (Jan..Dec)
SEASON = {
    "WHISKY":  [0.75, 0.80, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.95, 1.05, 1.45, 1.90],
    "GIN":     [0.70, 0.75, 0.90, 1.05, 1.25, 1.40, 1.45, 1.35, 1.05, 0.90, 0.95, 1.20],
    "RUM":     [0.75, 0.80, 0.90, 1.00, 1.15, 1.30, 1.35, 1.30, 1.00, 0.90, 1.00, 1.35],
    "VODKA":   [0.85, 0.85, 0.90, 0.95, 1.00, 1.05, 1.05, 1.00, 0.95, 0.95, 1.10, 1.70],
    "LIQUEUR": [0.85, 0.85, 0.90, 0.95, 1.00, 1.05, 1.05, 1.00, 0.95, 1.00, 1.30, 1.80],
    "BRANDY":  [0.80, 0.80, 0.80, 0.80, 0.75, 0.70, 0.70, 0.75, 0.90, 1.10, 1.60, 2.20],
}
# Long-term category trend by year (gin boom fading, rum rising)
TREND = {
    "WHISKY":  {2023: 1.00, 2024: 1.03, 2025: 1.05, 2026: 1.08},
    "GIN":     {2023: 1.00, 2024: 0.94, 2025: 0.86, 2026: 0.80},
    "RUM":     {2023: 1.00, 2024: 1.08, 2025: 1.17, 2026: 1.25},
    "VODKA":   {2023: 1.00, 2024: 1.00, 2025: 0.99, 2026: 0.98},
    "LIQUEUR": {2023: 1.00, 2024: 1.02, 2025: 1.05, 2026: 1.06},
    "BRANDY":  {2023: 1.00, 2024: 0.98, 2025: 0.96, 2026: 0.94},
}
# Yearly list-price increase (sales) and vendor-price increase (purchasing)
SALES_PRICE_IDX = {2023: 1.000, 2024: 1.040, 2025: 1.071, 2026: 1.098}
VENDOR_PRICE_IDX = {2023: 1.000, 2024: 1.050, 2025: 1.082, 2026: 1.114}

CHANNELS = {
    #            share  price factor  order freq  lines  pay terms
    "HORECA":    (0.62, 1.00, 1.0,  5, "P14"),
    "RETAIL":    (0.25, 0.90, 0.9,  8, "P30"),
    "WHOLESALE": (0.08, 0.86, 1.6, 10, "P45"),
    "ONLINE":    (0.05, 0.92, 1.5,  6, "P14"),
}
PAYMENT_TERMS = {"P14": 14, "P30": 30, "P45": 45}

# Category affinity per channel (bars sell gin/rum, retail sells more vodka/liqueur ...)
CHANNEL_CAT_AFFINITY = {
    "HORECA":    {"WHISKY": 1.0, "GIN": 1.4, "RUM": 1.3, "VODKA": 1.1, "LIQUEUR": 0.9, "BRANDY": 0.6},
    "RETAIL":    {"WHISKY": 1.1, "GIN": 0.9, "RUM": 0.9, "VODKA": 1.2, "LIQUEUR": 1.3, "BRANDY": 1.1},
    "WHOLESALE": {"WHISKY": 1.0, "GIN": 1.0, "RUM": 1.0, "VODKA": 1.2, "LIQUEUR": 1.1, "BRANDY": 0.9},
    "ONLINE":    {"WHISKY": 1.6, "GIN": 1.1, "RUM": 1.1, "VODKA": 0.6, "LIQUEUR": 0.7, "BRANDY": 1.2},
}

SALESPEOPLE = [
    # code, name, region, territory, start date
    ("AK", "Anna Kramer",     "Nord", "Bremen & Weser-Ems",          "2016-03-01"),
    ("BM", "Ben Möller",      "Nord", "Hamburg, Schleswig-Holstein, MV", "2018-07-01"),
    ("CS", "Clara Schulz",    "Nord", "Niedersachsen Ost",           "2020-01-15"),
    ("DH", "David Hoffmann",  "West", "Rheinland",                   "2017-05-01"),
    ("EL", "Elena Lange",     "West", "Ruhr, Westfalen, Rhein-Main", "2019-09-01"),
    ("FW", "Felix Wagner",    "Süd",  "Bayern",                      "2018-02-01"),
    ("GT", "Greta Thiele",    "Süd",  "Baden-Württemberg",           "2021-04-01"),
    ("HN", "Hannes Neumann",  "Ost",  "Berlin & Ostdeutschland",     "2019-01-01"),
    ("IK", "Ines Kowalski",   "National", "Key Accounts Retail & Wholesale", "2015-10-01"),
    ("JS", "Jonas Seidel",    "National", "E-Commerce",              "2022-06-01"),
]

# city, post code, federal state, region, salesperson, lat, lon, weight
CITIES = [
    ("Bremen", "28195", "Bremen", "Nord", "AK", 53.0793, 8.8017, 9.0),
    ("Bremerhaven", "27568", "Bremen", "Nord", "AK", 53.5396, 8.5809, 2.5),
    ("Oldenburg", "26122", "Niedersachsen", "Nord", "AK", 53.1435, 8.2146, 2.5),
    ("Osnabrück", "49074", "Niedersachsen", "Nord", "AK", 52.2799, 8.0472, 2.0),
    ("Hamburg", "20095", "Hamburg", "Nord", "BM", 53.5511, 9.9937, 7.0),
    ("Kiel", "24103", "Schleswig-Holstein", "Nord", "BM", 54.3233, 10.1228, 1.8),
    ("Lübeck", "23552", "Schleswig-Holstein", "Nord", "BM", 53.8655, 10.6866, 1.6),
    ("Rostock", "18055", "Mecklenburg-Vorpommern", "Nord", "BM", 54.0924, 12.0991, 1.4),
    ("Hannover", "30159", "Niedersachsen", "Nord", "CS", 52.3759, 9.7320, 3.5),
    ("Braunschweig", "38100", "Niedersachsen", "Nord", "CS", 52.2689, 10.5268, 1.8),
    ("Göttingen", "37073", "Niedersachsen", "Nord", "CS", 51.5413, 9.9158, 1.2),
    ("Lüneburg", "21335", "Niedersachsen", "Nord", "CS", 53.2464, 10.4115, 1.0),
    ("Köln", "50667", "Nordrhein-Westfalen", "West", "DH", 50.9375, 6.9603, 4.5),
    ("Düsseldorf", "40213", "Nordrhein-Westfalen", "West", "DH", 51.2277, 6.7735, 3.5),
    ("Bonn", "53111", "Nordrhein-Westfalen", "West", "DH", 50.7374, 7.0982, 1.5),
    ("Aachen", "52062", "Nordrhein-Westfalen", "West", "DH", 50.7753, 6.0839, 1.3),
    ("Duisburg", "47051", "Nordrhein-Westfalen", "West", "DH", 51.4344, 6.7623, 1.3),
    ("Dortmund", "44135", "Nordrhein-Westfalen", "West", "EL", 51.5136, 7.4653, 2.2),
    ("Essen", "45127", "Nordrhein-Westfalen", "West", "EL", 51.4556, 7.0116, 2.0),
    ("Münster", "48143", "Nordrhein-Westfalen", "West", "EL", 51.9607, 7.6261, 1.6),
    ("Bielefeld", "33602", "Nordrhein-Westfalen", "West", "EL", 52.0302, 8.5325, 1.3),
    ("Frankfurt am Main", "60311", "Hessen", "West", "EL", 50.1109, 8.6821, 3.0),
    ("Mainz", "55116", "Rheinland-Pfalz", "West", "EL", 49.9929, 8.2473, 1.2),
    ("München", "80331", "Bayern", "Süd", "FW", 48.1351, 11.5820, 4.0),
    ("Nürnberg", "90402", "Bayern", "Süd", "FW", 49.4521, 11.0767, 2.0),
    ("Augsburg", "86150", "Bayern", "Süd", "FW", 48.3705, 10.8978, 1.2),
    ("Regensburg", "93047", "Bayern", "Süd", "FW", 49.0134, 12.1016, 1.0),
    ("Würzburg", "97070", "Bayern", "Süd", "FW", 49.7913, 9.9534, 0.9),
    ("Stuttgart", "70173", "Baden-Württemberg", "Süd", "GT", 48.7758, 9.1829, 3.0),
    ("Karlsruhe", "76133", "Baden-Württemberg", "Süd", "GT", 49.0069, 8.4037, 1.4),
    ("Mannheim", "68159", "Baden-Württemberg", "Süd", "GT", 49.4875, 8.4660, 1.4),
    ("Freiburg im Breisgau", "79098", "Baden-Württemberg", "Süd", "GT", 47.9990, 7.8421, 1.2),
    ("Ulm", "89073", "Baden-Württemberg", "Süd", "GT", 48.4011, 9.9876, 0.8),
    ("Berlin", "10115", "Berlin", "Ost", "HN", 52.5200, 13.4050, 6.0),
    ("Leipzig", "04109", "Sachsen", "Ost", "HN", 51.3397, 12.3731, 2.0),
    ("Dresden", "01067", "Sachsen", "Ost", "HN", 51.0504, 13.7373, 1.8),
    ("Potsdam", "14467", "Brandenburg", "Ost", "HN", 52.3906, 13.0645, 1.0),
    ("Magdeburg", "39104", "Sachsen-Anhalt", "Ost", "HN", 52.1205, 11.6276, 0.9),
    ("Erfurt", "99084", "Thüringen", "Ost", "HN", 50.9848, 11.0299, 0.8),
]

# name, country, currency, lead time days, on-time reliability, order cycle days, brand, categories
VENDORS = [
    ("Glen Corran Distillers Ltd", "GB", "GBP", 14, 0.90, 21, "Glen Corran", ["WHISKY"]),
    ("Loch Ardan Whisky Co. Ltd", "GB", "GBP", 15, 0.85, 28, "Loch Ardan", ["WHISKY"]),
    ("Kilbrae Blending House Ltd", "GB", "GBP", 12, 0.92, 21, "Kilbrae", ["WHISKY"]),
    ("Speyglen Malt Distillers Ltd", "GB", "GBP", 16, 0.80, 28, "Speyglen", ["WHISKY"]),
    ("Islay Peat & Barrel Ltd", "GB", "GBP", 18, 0.70, 35, "Port Fennach", ["WHISKY"]),
    ("Highland Cask Merchants Ltd", "GB", "GBP", 14, 0.88, 28, "Highland Cask", ["WHISKY"]),
    ("Dunmore Irish Distillery Ltd", "IE", "EUR", 9, 0.90, 21, "Dunmore", ["WHISKY"]),
    ("Copper Still Irish Spirits Ltd", "IE", "EUR", 10, 0.85, 28, "Copper Still", ["WHISKY"]),
    ("Old Harrow Bourbon Company", "US", "USD", 38, 0.75, 42, "Old Harrow", ["WHISKY"]),
    ("Bluegrass Barrel Works Inc.", "US", "USD", 40, 0.70, 42, "Bluegrass Barrel", ["WHISKY"]),
    ("Kentucky Ridge Spirits LLC", "US", "USD", 36, 0.80, 42, "Kentucky Ridge", ["WHISKY"]),
    ("Brennerei Nordheide GmbH", "DE", "EUR", 4, 0.95, 14, "Nordheide", ["WHISKY", "GIN"]),
    ("London Mill Distillers Ltd", "GB", "GBP", 12, 0.90, 21, "London Mill", ["GIN"]),
    ("Thameside Botanicals Ltd", "GB", "GBP", 13, 0.85, 28, "Thameside", ["GIN"]),
    ("Weserkönig Manufaktur GmbH", "DE", "EUR", 3, 0.97, 14, "Weserkönig", ["GIN", "LIQUEUR"]),
    ("Hafenrose Destille GmbH", "DE", "EUR", 4, 0.93, 14, "Hafenrose", ["GIN"]),
    ("Elbufer Craft Spirits GmbH", "DE", "EUR", 4, 0.90, 14, "Elbufer", ["GIN"]),
    ("Atlantic Gin Company S.L.", "ES", "EUR", 8, 0.85, 28, "Atlántico Verde", ["GIN"]),
    ("Alpenkraut Spirituosen GmbH", "DE", "EUR", 5, 0.94, 14, "Alpenkraut", ["LIQUEUR", "GIN"]),
    ("Isla Coral Rum Company", "DO", "USD", 42, 0.70, 42, "Isla Coral", ["RUM"]),
    ("Caribbean Cane Traders Ltd", "BB", "USD", 40, 0.75, 42, "Cane & Coral", ["RUM"]),
    ("Port Royal Spirits Ltd", "JM", "USD", 45, 0.65, 49, "Port Royal Reserve", ["RUM"]),
    ("Tropic Isle Spirits Ltd", "TT", "USD", 44, 0.72, 49, "Tropic Isle", ["RUM"]),
    ("Rhum Maison Belcourt SAS", "FR", "EUR", 12, 0.85, 28, "Belcourt", ["RUM"]),
    ("Hamburger Rumkontor GmbH", "DE", "EUR", 3, 0.96, 14, "Kapitän Hansen", ["RUM"]),
    ("Wolna Distillery Sp. z o.o.", "PL", "EUR", 6, 0.90, 21, "Wolna", ["VODKA"]),
    ("Nordfrost Spirits AB", "SE", "EUR", 8, 0.92, 21, "Nordfrost", ["VODKA"]),
    ("Baltic Grain Spirits UAB", "LT", "EUR", 9, 0.80, 28, "Baltyk", ["VODKA"]),
    ("Polar Clear Vodka Oy", "FI", "EUR", 10, 0.88, 28, "Polar Clear", ["VODKA"]),
    ("Kornbrennerei Ostfriesland GmbH", "DE", "EUR", 3, 0.96, 14, "Friesengold", ["VODKA", "LIQUEUR"]),
    ("Liquorificio Bella Arancia S.r.l.", "IT", "EUR", 9, 0.85, 28, "Bella Arancia", ["LIQUEUR"]),
    ("Distilleria Monte Sereno S.p.A.", "IT", "EUR", 10, 0.82, 28, "Monte Sereno", ["LIQUEUR"]),
    ("Amaro della Valle S.r.l.", "IT", "EUR", 10, 0.88, 28, "Della Valle", ["LIQUEUR"]),
    ("Kräuterhaus Harzblick GmbH", "DE", "EUR", 4, 0.95, 14, "Harzblick", ["LIQUEUR"]),
    ("Maison Delaure Cognac SAS", "FR", "EUR", 11, 0.90, 28, "Delaure", ["BRANDY"]),
    ("Cognac Fontaine Frères SAS", "FR", "EUR", 12, 0.86, 35, "Fontaine Frères", ["BRANDY"]),
    ("Domaine Vergier Calvados SARL", "FR", "EUR", 12, 0.84, 35, "Domaine Vergier", ["BRANDY"]),
    ("Bodegas Sierra Alta S.A.", "ES", "EUR", 10, 0.82, 35, "Sierra Alta", ["BRANDY"]),
    ("Weinbrennerei Rheingold GmbH", "DE", "EUR", 4, 0.95, 21, "Rheingold", ["BRANDY"]),
    ("Elbtal Destillerie GmbH", "DE", "EUR", 5, 0.90, 21, "Elbtal", ["GIN", "LIQUEUR"]),
]

VARIANTS = {
    "WHISKY": [("Single Malt 10 Jahre", 41, 1.4), ("Single Malt 12 Jahre", 43, 1.7), ("Single Malt 18 Jahre", 43, 3.5),
               ("Sherry Cask", 46, 2.0), ("Port Cask Finish", 46, 1.9), ("Cask Strength", 57.5, 2.6),
               ("Blended", 40, 0.7), ("Peated", 46, 1.8), ("Small Batch", 45, 1.5), ("Single Barrel", 47, 2.2),
               ("Rye", 45, 1.3), ("Straight Bourbon", 40, 0.9), ("Triple Distilled", 40, 0.9),
               ("Pot Still", 43, 1.6), ("Double Wood", 40, 1.3), ("Reserve", 43, 1.5)],
    "GIN": [("London Dry", 43, 1.0), ("Navy Strength", 57, 1.4), ("Pink", 37.5, 0.9), ("Sloe", 28, 0.9),
            ("Old Tom", 40, 1.1), ("Citrus", 41, 1.0), ("Barrel Aged", 44, 1.5), ("Dry", 44, 1.1),
            ("Mediterranean", 42, 1.2)],
    "RUM": [("Añejo 7", 40, 1.0), ("Añejo 12", 40, 1.6), ("White", 37.5, 0.7), ("Spiced", 35, 0.8),
            ("Dark", 40, 0.9), ("Overproof", 63, 1.1), ("Agricole Blanc", 50, 1.2), ("Agricole VSOP", 45, 1.9),
            ("Gold", 38, 0.8), ("XO", 40, 2.5)],
    "VODKA": [("Premium", 40, 1.2), ("Classic", 37.5, 0.8), ("Wheat", 40, 1.0), ("Rye", 40, 1.1),
              ("Citron", 37.5, 0.9), ("Black Edition", 40, 1.5), ("Single Estate", 40, 1.7), ("Potato", 40, 1.3)],
    "LIQUEUR": [("Kräuterlikör", 35, 1.0), ("Orangenlikör", 30, 1.1), ("Amaro", 28, 1.1), ("Limoncello", 28, 0.9),
                ("Kaffeelikör", 20, 0.9), ("Haselnusslikör", 24, 1.0), ("Pfefferminzlikör", 18, 0.7),
                ("Sahnelikör", 17, 0.9), ("Holunderlikör", 20, 1.0), ("Aperitivo", 15, 0.9)],
    "BRANDY": [("VS", 40, 1.0), ("VSOP", 40, 1.6), ("XO", 40, 3.2), ("Calvados Pays d'Auge", 40, 1.5),
               ("Brandy de Jerez", 36, 0.9), ("Weinbrand", 36, 0.6), ("Hors d'Âge", 42, 2.8)],
}
# Base vendor price per 0.7 L bottle in EUR before variant premium
CAT_BASE_PRICE = {"WHISKY": 13.0, "GIN": 9.5, "RUM": 9.0, "VODKA": 6.0, "LIQUEUR": 6.5, "BRANDY": 11.0}

# Synthetic monthly FX anchors (units of currency per 1 EUR), close to ECB levels
FX_ANCHORS = {
    "USD": [1.07, 1.07, 1.07, 1.10, 1.09, 1.08, 1.11, 1.09, 1.07, 1.06, 1.08, 1.09,
            1.09, 1.08, 1.09, 1.07, 1.08, 1.08, 1.08, 1.10, 1.11, 1.09, 1.06, 1.05,
            1.04, 1.04, 1.08, 1.12, 1.13, 1.15, 1.17, 1.16, 1.17, 1.16, 1.16, 1.17,
            1.17, 1.18, 1.16, 1.17, 1.16, 1.17, 1.16, 1.17, 1.17],
    "GBP": [0.88, 0.89, 0.88, 0.88, 0.87, 0.86, 0.86, 0.86, 0.86, 0.87, 0.87, 0.86,
            0.86, 0.86, 0.85, 0.86, 0.85, 0.85, 0.85, 0.85, 0.84, 0.83, 0.83, 0.83,
            0.84, 0.83, 0.84, 0.86, 0.85, 0.85, 0.86, 0.86, 0.87, 0.87, 0.88, 0.88,
            0.87, 0.87, 0.87, 0.86, 0.87, 0.87, 0.87, 0.87, 0.87],
}

PURCHASE_USERS = ["MSCHULTE", "TFRANKE", "LMEYER"]
HEAD_OF_PURCHASING = "KVOGEL"
CFO = "RBRANDT"
SALES_ADMIN_USERS = ["SKAYA", "PJANSSEN", "NBERGER", "WOTTO"]

HORECA_TYPES = ["Bar", "Cocktailbar", "Restaurant", "Hotel", "Bistro", "Kneipe", "Lounge", "Brauhaus", "Café", "Club"]
HORECA_NAMES = ["Anker", "Hafenblick", "Möwe", "Leuchtturm", "Kompass", "Speicher", "Lotse", "Kajüte", "Seemann",
                "Roland", "Schlachte", "Viertel", "Kontor", "Linde", "Eiche", "Krone", "Stern", "Halbmond",
                "Sonne", "Löwe", "Adler", "Fuchs", "Rabe", "Blaue Stunde", "Goldener Hirsch", "Alte Liebe",
                "Nordwind", "Kranich", "Zollhaus", "Stadtgarten", "Weinberg", "Feierabend", "Marktplatz",
                "Brücke", "Mühle", "Uhrwerk", "Zeitgeist", "Fischmarkt", "Rosengarten", "Kaiserhof",
                "Lindenhof", "Seeblick", "Elbkind", "Rheinperle", "Isarblick", "Spreeufer", "Kiez", "Laterne"]
SURNAMES = ["Brandt", "Meyer", "Schröder", "Fischer", "Weber", "Becker", "Wolf", "Krüger", "Hartmann", "Lange",
            "Werner", "Lehmann", "Köhler", "Hahn", "Vogel", "Friedrich", "Keller", "Jansen", "Peters", "Ahrens",
            "Bruns", "Lüders", "Wessels", "Hinrichs", "Gerdes", "Behrens", "Ohlsen", "Petersen", "Albers", "Kuhn"]
RETAIL_TYPES = ["Getränkemarkt {s}", "Getränke {s} GmbH", "Weinhandlung {s}", "Feinkost {s} e.K.",
                "Spirituosen {s}", "Getränkewelt {s} GmbH", "{s} Getränkefachmarkt"]
WHOLESALE_TYPES = ["{s} Getränkegroßhandel GmbH", "Gastro-Service {s} KG", "{s} & Söhne Getränkelogistik GmbH",
                   "Getränke-Union {s} GmbH"]
ONLINE_WORDS = ["fassstark", "tropfenwerk", "barregal", "flaschenpost-nord", "edelbrand-shop", "spiritkiste",
                "malt-depot", "ginfinder", "rumregal", "korkenknall", "glaswerk-shop", "barfuchs"]


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def month_index(ts: pd.Timestamp) -> int:
    return (ts.year - START.year) * 12 + ts.month - 1


def build_fx(rng: np.random.Generator, fx_file: str | None) -> pd.DataFrame:
    """Daily ECB-style reference rates (business days), units per 1 EUR."""
    days = pd.bdate_range(START - pd.Timedelta(days=60), END)
    if fx_file:
        fx = pd.read_csv(fx_file, parse_dates=["Rate_Date"])
        fx = fx[(fx["Rate_Date"] >= days.min()) & (fx["Rate_Date"] <= END)]
        return fx[["Rate_Date", "Currency_Code", "Exchange_Rate"]].sort_values(["Currency_Code", "Rate_Date"])
    rows = []
    for cur, anchors in FX_ANCHORS.items():
        # anchor at mid-month, interpolate daily, add small noise
        anchor_dates = [START + pd.DateOffset(months=i, days=14) for i in range(len(anchors))]
        s = pd.Series(anchors, index=pd.DatetimeIndex(anchor_dates))
        s = s.reindex(s.index.union(days)).interpolate("time").bfill().ffill().reindex(days)
        noise = np.cumsum(rng.normal(0, 0.0012, len(days)))
        noise = noise - pd.Series(noise).rolling(15, min_periods=1).mean().to_numpy()
        vals = np.round(s.to_numpy() * (1 + noise), 4)
        rows.append(pd.DataFrame({"Rate_Date": days, "Currency_Code": cur, "Exchange_Rate": vals}))
    return pd.concat(rows, ignore_index=True)


def write_csv(df: pd.DataFrame, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out = df.copy()
    for c in out.columns:
        if pd.api.types.is_datetime64_any_dtype(out[c]):
            out[c] = out[c].dt.strftime("%Y-%m-%d")
        elif pd.api.types.is_float_dtype(out[c]):
            out[c] = out[c].round(6)      # BigQuery NUMERIC allows max. 9 decimals
    out.to_csv(path, index=False, encoding="utf-8")
    print(f"  {path.relative_to(path.parents[2]) if len(path.parents) > 2 else path}: {len(out):,} rows")


# --------------------------------------------------------------------------
# Master data
# --------------------------------------------------------------------------
def build_salespeople() -> pd.DataFrame:
    return pd.DataFrame(
        [{"Code": c, "Name": n, "Region": r, "Territory": t, "E_Mail": f"{c.lower()}@hanse-spirits.example",
          "Start_Date": pd.Timestamp(d)} for c, n, r, t, d in SALESPEOPLE])


def build_vendors() -> pd.DataFrame:
    rows = []
    for i, (name, country, cur, lead, rel, cycle, brand, cats) in enumerate(VENDORS):
        rows.append({
            "No": f"V-{1001 + i}", "Name": name, "Country_Region_Code": country,
            "Currency_Code": "" if cur == "EUR" else cur,
            "Payment_Terms_Code": "P30" if country != "DE" else "P14",
            "Lead_Time_Days": lead, "Vendor_Posting_Group": "DOMESTIC" if country == "DE" else
            ("EU" if cur == "EUR" else "FOREIGN"),
            "Blocked": False,
            # helper columns (dropped before export)
            "_reliability": rel, "_cycle": cycle, "_brand": brand, "_cats": cats, "_cur": cur,
        })
    return pd.DataFrame(rows)


def build_items(rng, vendors: pd.DataFrame) -> pd.DataFrame:
    rows = []
    item_no = 10001
    for cat in CATEGORIES:
        cat_vendors = vendors[vendors["_cats"].apply(lambda cs: cat in cs)]
        n = CATEGORY_COUNTS[cat]
        # distribute items over vendors (primary category vendors get more)
        weights = np.array([2.0 if cs[0] == cat else 0.8 for cs in cat_vendors["_cats"]])
        alloc = rng.multinomial(n - len(cat_vendors), weights / weights.sum()) + 1
        for (_, v), k in zip(cat_vendors.iterrows(), alloc):
            variants = VARIANTS[cat]
            picks = rng.choice(len(variants), size=min(k, len(variants)), replace=False)
            extra = k - len(picks)
            picks = list(picks) + list(rng.choice(len(variants), size=extra))
            seen = set()
            for p in picks:
                vname, abv, premium = variants[p]
                size = 0.7
                if cat in ("VODKA", "GIN", "RUM") and rng.random() < 0.25:
                    size = 1.0
                if cat == "LIQUEUR" and rng.random() < 0.3:
                    size = 0.5
                if (vname, size) in seen:
                    size = 0.35 if size != 0.35 else 1.0
                seen.add((vname, size))
                abv = round(abv + rng.choice([0, 0, 0.5, 1, -0.5]), 1) if abv < 55 else abv
                base_eur = CAT_BASE_PRICE[cat] * premium * (size / 0.7) ** 0.9 * rng.lognormal(0, 0.15)
                rows.append({
                    "No": f"I-{item_no}",
                    "Description": f"{v['_brand']} {vname} {abv:g}% {size:g}L",
                    "Item_Category_Code": cat,
                    "Brand": v["_brand"],
                    "Vendor_No": v["No"],
                    "Base_Unit_of_Measure": "FL",          # Flasche (bottle)
                    "Bottle_Size_L": size,
                    "Alcohol_Pct": abv,
                    "Country_of_Origin": v["Country_Region_Code"],
                    "_vendor_cur": v["_cur"],
                    "_base_eur": base_eur,
                    "_popularity": rng.lognormal(0, 1.15) / (premium ** 0.8),
                })
                item_no += 1
    items = pd.DataFrame(rows)
    n = len(items)
    # vendor price in vendor currency (2023 level), using 2023 avg FX
    fx_2023 = {"EUR": 1.0, "USD": 1.08, "GBP": 0.87}
    items["_vendor_price_2023"] = [round(b * fx_2023[c], 2) for b, c in zip(items["_base_eur"], items["_vendor_cur"])]
    items["_excise_per_bottle"] = (items["Bottle_Size_L"] * items["Alcohol_Pct"] / 100 * EXCISE_EUR_PER_L_PURE).round(4)
    items["_markup"] = rng.uniform(1.45, 1.75, n)
    # launches and discontinuations
    launch = np.full(n, pd.Timestamp("2015-01-01").value)
    new_mask = rng.random(n) < 0.14
    launch_days = rng.integers(60, (END - START).days - 120, new_mask.sum())
    launch[new_mask] = [(START + pd.Timedelta(days=int(d))).value for d in launch_days]
    items["_launch"] = pd.to_datetime(launch)
    disc = np.full(n, np.datetime64("NaT", "ns"), dtype="datetime64[ns]")
    disc_mask = (~new_mask) & (rng.random(n) < 0.09)
    disc_days = rng.integers(365, (END - START).days - 60, disc_mask.sum())
    disc[disc_mask] = [np.datetime64(START + pd.Timedelta(days=int(d))) for d in disc_days]
    items["_discontinued"] = pd.to_datetime(disc)
    items["Blocked"] = items["_discontinued"].notna()
    items["Blocked_Date"] = items["_discontinued"]
    items["Created_Date"] = items["_launch"].where(new_mask, pd.Timestamp("2014-06-01") +
                                                   pd.to_timedelta(rng.integers(0, 3000, n), unit="D"))
    return items


def build_customers(rng) -> pd.DataFrame:
    n = 1200
    ch_names = list(CHANNELS)
    shares = np.array([CHANNELS[c][0] for c in ch_names])
    channels = rng.choice(ch_names, size=n, p=shares / shares.sum())
    cw = np.array([c[7] for c in CITIES])
    city_idx = rng.choice(len(CITIES), size=n, p=cw / cw.sum())
    rows = []
    used_names = set()
    for i in range(n):
        ch = channels[i]
        city = CITIES[city_idx[i]]
        for _ in range(50):
            if ch == "HORECA":
                nm = f"{rng.choice(HORECA_TYPES)} {rng.choice(HORECA_NAMES)}"
            elif ch == "RETAIL":
                nm = rng.choice(RETAIL_TYPES).format(s=rng.choice(SURNAMES))
            elif ch == "WHOLESALE":
                nm = rng.choice(WHOLESALE_TYPES).format(s=rng.choice(SURNAMES))
            else:
                nm = f"{rng.choice(ONLINE_WORDS)}.de GmbH"
            key = (nm, city[0])
            if key not in used_names:
                used_names.add(key)
                break
        size = rng.lognormal(0, 0.6)
        freq = CHANNELS[ch][2] * rng.lognormal(0, 0.5)
        rep = city[4]
        if ch == "ONLINE":
            rep = "JS"
        elif ch in ("RETAIL", "WHOLESALE") and size > 1.6:
            rep = "IK"
        credit = {"HORECA": (3000, 15000), "RETAIL": (15000, 60000),
                  "WHOLESALE": (60000, 250000), "ONLINE": (15000, 50000)}[ch]
        credit_limit = round(rng.uniform(*credit) * min(size, 2.5) / 1000) * 1000
        rows.append({
            "No": f"C-{10001 + i}", "Name": nm, "Address": f"{rng.choice(['Hauptstraße', 'Bahnhofstraße', 'Am Markt', 'Hafenstraße', 'Lindenweg', 'Industriestraße', 'Gewerbering', 'Kirchstraße'])} {rng.integers(1, 180)}",
            "Post_Code": city[1], "City": city[0], "County": city[2], "Country_Region_Code": "DE",
            "Latitude": round(city[5] + rng.normal(0, 0.02), 5), "Longitude": round(city[6] + rng.normal(0, 0.03), 5),
            "Customer_Posting_Group": "DOMESTIC", "Customer_Price_Group": ch, "Gen_Bus_Posting_Group": "NATIONAL",
            "Salesperson_Code": rep, "Payment_Terms_Code": CHANNELS[ch][4],
            "Credit_Limit_LCY": max(credit_limit, 2000.0),
            "_size": size, "_freq": freq, "_region": city[3],
        })
    cust = pd.DataFrame(rows)
    # created dates: 72% existing before start, rest onboarded during the period (growth)
    existing = rng.random(n) < 0.72
    created = np.where(existing,
                       (pd.Timestamp("2012-01-01") + pd.to_timedelta(rng.integers(0, 4000, n), unit="D")).values,
                       (START + pd.to_timedelta(rng.integers(0, (END - START).days - 30, n), unit="D")).values)
    cust["Created_Date"] = pd.to_datetime(created)
    # churn: 13% stop buying at some point
    churn = np.full(n, np.datetime64("NaT", "ns"), dtype="datetime64[ns]")
    cm = rng.random(n) < 0.13
    churn[cm] = (START + pd.to_timedelta(rng.integers(120, (END - START).days - 10, cm.sum()), unit="D")).values
    cust["_churn"] = pd.to_datetime(churn)
    cust.loc[cust["_churn"] <= cust["Created_Date"] + pd.Timedelta(days=60), "_churn"] = pd.NaT
    # one big wholesale key account lost in spring 2025 (story for the dashboard)
    big = cust[(cust["Customer_Price_Group"] == "WHOLESALE") & cust["Created_Date"].lt(START)].sort_values("_size").index[-1]
    cust.loc[big, "_churn"] = pd.Timestamp("2025-04-11")
    cust.loc[big, "_size"] = 3.2
    cust.loc[big, "_freq"] = 3.5
    # payment behaviour
    cust["_pay_profile"] = rng.choice(["good", "avg", "late", "bad"], size=n, p=[0.55, 0.32, 0.11, 0.02])
    # blocked: half of churned customers get blocked a few weeks after churn
    cust["Blocked"] = ""
    cust["Blocked_Date"] = pd.NaT
    bm = cust["_churn"].notna() & (rng.random(n) < 0.5)
    cust.loc[bm, "Blocked"] = "All"
    cust.loc[bm, "Blocked_Date"] = cust.loc[bm, "_churn"] + pd.to_timedelta(rng.integers(20, 90, bm.sum()), unit="D")
    cust.loc[cust["Blocked_Date"] > END, ["Blocked", "Blocked_Date"]] = ["", pd.NaT]
    return cust


# --------------------------------------------------------------------------
# Prices & costs
# --------------------------------------------------------------------------
def monthly_fx(fx: pd.DataFrame) -> dict:
    m = fx.assign(ym=fx["Rate_Date"].dt.to_period("M")).groupby(["Currency_Code", "ym"])["Exchange_Rate"].mean()
    return {k: v for k, v in m.items()}


def item_cost_matrix(items: pd.DataFrame, fxm: dict) -> np.ndarray:
    """Unit cost in EUR (landed, duty-paid) per month index x item."""
    n_months = month_index(END) + 1
    out = np.zeros((n_months, len(items)))
    for mi in range(n_months):
        ym = (START + pd.DateOffset(months=mi)).to_period("M")
        vidx = VENDOR_PRICE_IDX[ym.year]
        rate = items["_vendor_cur"].map(lambda c: 1.0 if c == "EUR" else fxm[(c, ym)]).to_numpy()
        vp = items["_vendor_price_2023"].to_numpy() * vidx
        out[mi] = np.round(vp / rate * (1 + FREIGHT) + items["_excise_per_bottle"].to_numpy(), 2)
    return out


def list_price_by_year(items: pd.DataFrame) -> dict:
    """HORECA list price (net, EUR) per year. Set once a year from 2023 cost basis."""
    base_cost = items["_vendor_price_2023"].to_numpy() / items["_vendor_cur"].map(
        {"EUR": 1.0, "USD": 1.08, "GBP": 0.87}).to_numpy() * (1 + FREIGHT) + items["_excise_per_bottle"].to_numpy()
    base = base_cost * items["_markup"].to_numpy()
    out = {}
    for y, idx in SALES_PRICE_IDX.items():
        p = base * idx
        out[y] = np.where(p < 10, np.round(p, 1) - 0.01 + 0.0, np.round(p) - 0.01)
        out[y] = np.round(np.maximum(out[y], 2.99), 2)
    return out


# --------------------------------------------------------------------------
# Sales
# --------------------------------------------------------------------------
def generate_sales(rng, cust, items, cost_m, price_y, hol_dates):
    days = pd.date_range(START, END, freq="D")
    bdays = [d for d in days if d.weekday() < 5 and d not in hol_dates]
    cat_arr = items["Item_Category_Code"].to_numpy()
    pop = items["_popularity"].to_numpy()
    launch = items["_launch"].to_numpy()
    disc = items["_discontinued"].to_numpy()
    cust_created = cust["Created_Date"].to_numpy()
    cust_churn = cust["_churn"].to_numpy()
    cust_freq = cust["_freq"].to_numpy()
    cust_size = cust["_size"].to_numpy()
    cust_ch = cust["Customer_Price_Group"].to_numpy()
    cust_no = cust["No"].to_numpy()
    cust_rep = cust["Salesperson_Code"].to_numpy()
    cust_block = cust["Blocked_Date"].to_numpy()

    item_no_arr = items["No"].to_numpy()
    aff_arr = {ch: np.array([CHANNEL_CAT_AFFINITY[ch][c] for c in cat_arr]) for ch in CHANNELS}
    total_season = np.array([np.mean([SEASON[c][m] for c in CATEGORIES]) for m in range(12)])
    weekday_f = [1.12, 1.02, 1.00, 1.00, 0.86]
    base_per_day = 40.0

    headers, lines = [], []
    inv_id = 0
    for d in bdays:
        dn = np.datetime64(d)
        yrs = (d - START).days / 365.25
        mean_inv = base_per_day * (1.055 ** yrs) * total_season[d.month - 1] * weekday_f[d.weekday()]
        active_c = (cust_created <= dn) & (np.isnat(cust_churn) | (cust_churn > dn)) & \
                   (np.isnat(cust_block) | (cust_block > dn))
        idx_c = np.flatnonzero(active_c)
        k = min(rng.poisson(mean_inv), len(idx_c))
        if k == 0:
            continue
        pc = cust_freq[idx_c]
        chosen = rng.choice(idx_c, size=k, replace=False, p=pc / pc.sum())
        active_i = (launch <= dn) & (np.isnat(disc) | (disc > dn))
        idx_i = np.flatnonzero(active_i)
        cat_w = np.array([SEASON[c][d.month - 1] * TREND[c][d.year] for c in cat_arr[idx_i]])
        mi = month_index(d)
        lp = price_y[d.year]
        w_ch = {}
        for ch_ in CHANNELS:
            w_ = pop[idx_i] * cat_w * aff_arr[ch_][idx_i]
            w_ch[ch_] = w_ / w_.sum()
        for ci in chosen:
            ch = cust_ch[ci]
            n_lines = min(1 + rng.poisson(CHANNELS[ch][3] * min(cust_size[ci], 2.0) ** 0.5), len(idx_i), 40)
            picks = rng.choice(idx_i, size=n_lines, replace=False, p=w_ch[ch])
            inv_id += 1
            headers.append((inv_id, cust_no[ci], d, cust_rep[ci], ch))
            for ln, it in enumerate(picks, start=1):
                if ch == "HORECA":
                    q = rng.choice([2, 3, 4, 6, 6, 12, 12, 18], p=[0.14, 0.12, 0.14, 0.2, 0.12, 0.12, 0.08, 0.08])
                elif ch == "RETAIL":
                    q = 6 * rng.integers(1, 6)
                elif ch == "WHOLESALE":
                    q = 6 * rng.integers(2, 9)
                else:
                    q = 6 * rng.integers(1, 4)
                q = int(max(1, round(q * min(cust_size[ci], 2.5) ** 0.6 / (6 if ch != "HORECA" else 1)) *
                            (6 if ch != "HORECA" else 1)))
                price = round(lp[it] * CHANNELS[ch][1], 2)
                disc_pct = {"HORECA": rng.choice([0, 0, 0, 0, 0, 5, 5, 10]),
                            "RETAIL": rng.choice([0, 0, 5, 5, 10, 15]),
                            "WHOLESALE": rng.choice([5, 10, 10, 15]),
                            "ONLINE": rng.choice([0, 0, 5, 10])}[ch]
                if d.month == 12 and rng.random() < 0.15:
                    disc_pct = min(disc_pct + 5, 25)
                lines.append((inv_id, ln * 10000, item_no_arr[it], q, price, float(disc_pct),
                              cost_m[mi, it]))
    hdr = pd.DataFrame(headers, columns=["_id", "Sell_to_Customer_No", "Posting_Date", "Salesperson_Code", "_ch"])
    ln = pd.DataFrame(lines, columns=["_id", "Line_No", "No", "Quantity", "Unit_Price", "Line_Discount_Pct",
                                      "Unit_Cost_LCY"])
    return hdr, ln


def plant_sales_issues(rng, hdr, ln, cust, items, hol_dates, issues):
    """Insert realistic data-quality / control issues (documented in docs/INTERNAL_CONTROLS.md)."""
    # 1) Price below cost - concentrated on one rep (story for the controls page)
    rep_of = hdr.set_index("_id")["Salesperson_Code"]
    ln_rep = ln["_id"].map(rep_of)
    p = np.where(ln_rep == "DH", 6.0, 1.0)
    idx = rng.choice(ln.index, size=int(len(ln) * 0.0025), replace=False, p=p / p.sum())
    ln.loc[idx, "Unit_Price"] = (ln.loc[idx, "Unit_Cost_LCY"] * rng.uniform(0.72, 0.97, len(idx))).round(2)
    ln.loc[idx, "Line_Discount_Pct"] = 0.0
    issues["PRICE_BELOW_COST"] = len(idx)

    # 2) Discounts above the 25 % policy limit
    idx = rng.choice(ln.index.difference(idx), size=int(len(ln) * 0.004), replace=False)
    ln.loc[idx, "Line_Discount_Pct"] = rng.choice([30.0, 35.0, 40.0, 50.0], size=len(idx), p=[0.5, 0.25, 0.15, 0.1])
    issues["DISCOUNT_ABOVE_POLICY"] = len(idx)

    # 3) Duplicate invoices (same customer, date, lines - posted twice)
    dup_ids = rng.choice(hdr["_id"], size=18, replace=False)
    next_id = hdr["_id"].max() + 1
    new_h, new_l = [], []
    for did in dup_ids:
        h = hdr[hdr["_id"] == did].iloc[0].copy()
        h["_id"] = next_id
        new_h.append(h)
        l = ln[ln["_id"] == did].copy()
        l["_id"] = next_id
        new_l.append(l)
        next_id += 1
    hdr = pd.concat([hdr, pd.DataFrame(new_h)], ignore_index=True)
    ln = pd.concat([ln] + new_l, ignore_index=True)
    issues["DUPLICATE_INVOICE"] = len(dup_ids)

    # 4) Sales to blocked customers (posted after the block date)
    blocked = cust[cust["Blocked"] == "All"].sample(9, random_state=7)
    for _, c in blocked.iterrows():
        d = c["Blocked_Date"] + pd.Timedelta(days=int(rng.integers(3, 40)))
        while d.weekday() >= 5:
            d += pd.Timedelta(days=1)
        if d > END:
            continue
        h = {"_id": next_id, "Sell_to_Customer_No": c["No"], "Posting_Date": d,
             "Salesperson_Code": c["Salesperson_Code"], "_ch": c["Customer_Price_Group"]}
        hdr = pd.concat([hdr, pd.DataFrame([h])], ignore_index=True)
        its = items[~items["Blocked"]].sample(int(rng.integers(2, 6)), random_state=int(rng.integers(1e6)))
        mi = month_index(d)
        for k, (_, it) in enumerate(its.iterrows(), start=1):
            new_l.append(pd.DataFrame([{"_id": next_id, "Line_No": k * 10000, "No": it["No"],
                                        "Quantity": int(rng.choice([6, 12, 18])),
                                        "Unit_Price": round(float(it["Unit_Price"]) * CHANNELS[c["Customer_Price_Group"]][1], 2),
                                        "Line_Discount_Pct": 0.0, "Unit_Cost_LCY": np.nan}]))
        next_id += 1
        issues["SALES_TO_BLOCKED_CUSTOMER"] = issues.get("SALES_TO_BLOCKED_CUSTOMER", 0) + 1
    ln = pd.concat([ln] + new_l[len(dup_ids):], ignore_index=True)

    # 5) Postings on weekends / public holidays
    idx = rng.choice(hdr.index[hdr["Posting_Date"] < END - pd.Timedelta(days=10)], size=7, replace=False)
    for i in idx:
        d = hdr.at[i, "Posting_Date"]
        hdr.at[i, "Posting_Date"] = d + pd.Timedelta(days=(6 - d.weekday()) % 7 or 7)  # next Sunday
    issues["POSTING_ON_NON_BUSINESS_DAY"] = len(idx)

    # 6) Lines with item numbers missing from the item master (orphans)
    idx = rng.choice(ln.index, size=6, replace=False)
    ln.loc[idx, "No"] = [f"I-{n}" for n in rng.integers(19000, 19999, 6)]
    issues["ORPHAN_ITEM_ON_INVOICE"] = len(idx)
    return hdr, ln


def finalize_sales(rng, hdr, ln, cust, items, cost_m):
    # number invoices chronologically per year (BC-style number series)
    hdr = hdr.sort_values(["Posting_Date", "_id"]).reset_index(drop=True)
    hdr["_seq"] = hdr.groupby(hdr["Posting_Date"].dt.year).cumcount() + 1
    hdr["No"] = "SI" + hdr["Posting_Date"].dt.strftime("%y") + "-" + hdr["_seq"].astype(str).str.zfill(6)
    id2no = hdr.set_index("_id")["No"]
    ln["Document_No"] = ln["_id"].map(id2no)
    # unit cost for the inserted lines
    item_pos = pd.Series(range(len(items)), index=items["No"])
    miss = ln["Unit_Cost_LCY"].isna()
    if miss.any():
        dates = ln.loc[miss, "_id"].map(hdr.set_index("_id")["Posting_Date"])
        ln.loc[miss, "Unit_Cost_LCY"] = [cost_m[month_index(d), item_pos.get(n, 0)] for d, n in
                                         zip(dates, ln.loc[miss, "No"])]
    ln["Amount"] = (ln["Quantity"] * ln["Unit_Price"] * (1 - ln["Line_Discount_Pct"] / 100)).round(2)
    ln["Line_Discount_Amount"] = (ln["Quantity"] * ln["Unit_Price"] - ln["Amount"]).round(2)
    ln["Amount_Including_VAT"] = (ln["Amount"] * (1 + VAT)).round(2)
    ln["Type"] = "Item"
    ln["Unit_of_Measure_Code"] = "FL"
    ln["Location_Code"] = LOCATION
    ln = ln.sort_values(["Document_No", "Line_No"])

    terms = cust.set_index("No")["Payment_Terms_Code"]
    hdr["Payment_Terms_Code"] = hdr["Sell_to_Customer_No"].map(terms)
    hdr["Due_Date"] = hdr["Posting_Date"] + pd.to_timedelta(hdr["Payment_Terms_Code"].map(PAYMENT_TERMS), unit="D")
    hdr["Document_Date"] = hdr["Posting_Date"]
    hdr["Order_No"] = "SO" + hdr["Posting_Date"].dt.strftime("%y") + "-" + hdr["_seq"].astype(str).str.zfill(6)
    hdr["Currency_Code"] = ""
    hdr["Location_Code"] = LOCATION
    hdr["Shipment_Method_Code"] = np.where(hdr["_ch"] == "WHOLESALE", "PALETTE", "SPEDITION")
    hdr["User_ID"] = rng.choice(SALES_ADMIN_USERS, size=len(hdr))
    hdr = hdr.merge(cust[["No", "Name", "City", "Post_Code"]].rename(columns={
        "No": "Sell_to_Customer_No", "Name": "Sell_to_Customer_Name", "City": "Sell_to_City",
        "Post_Code": "Sell_to_Post_Code"}), on="Sell_to_Customer_No", how="left")
    totals = ln.groupby("_id")[["Amount", "Amount_Including_VAT"]].sum().round(2)
    hdr = hdr.join(totals, on="_id")
    hdr_out = hdr[["No", "Sell_to_Customer_No", "Sell_to_Customer_Name", "Sell_to_City", "Sell_to_Post_Code",
                   "Posting_Date", "Document_Date", "Due_Date", "Payment_Terms_Code", "Salesperson_Code",
                   "Currency_Code", "Location_Code", "Shipment_Method_Code", "Order_No", "User_ID",
                   "Amount", "Amount_Including_VAT"]]
    ln_out = ln[["Document_No", "Line_No", "Type", "No", "Location_Code", "Unit_of_Measure_Code", "Quantity",
                 "Unit_Price", "Line_Discount_Pct", "Line_Discount_Amount", "Amount", "Amount_Including_VAT",
                 "Unit_Cost_LCY"]]
    return hdr, hdr_out, ln_out


def build_customer_ledger(rng, hdr, cust):
    prof = cust.set_index("No")["_pay_profile"]
    p = hdr["Sell_to_Customer_No"].map(prof).to_numpy()
    n = len(hdr)
    delay = np.select(
        [p == "good", p == "avg", p == "late", p == "bad"],
        [rng.integers(-5, 4, n), rng.integers(0, 21, n), rng.integers(12, 75, n), rng.integers(30, 200, n)])
    never = (p == "bad") & (rng.random(n) < 0.35)
    pay = hdr["Due_Date"] + pd.to_timedelta(delay, unit="D")
    pay = pay.where(pay >= hdr["Posting_Date"], hdr["Posting_Date"] + pd.Timedelta(days=1))
    open_ = (pay > END) | never
    cle = pd.DataFrame({
        "Entry_No": np.arange(1, n + 1),
        "Customer_No": hdr["Sell_to_Customer_No"],
        "Posting_Date": hdr["Posting_Date"],
        "Document_Type": "Invoice",
        "Document_No": hdr["No"],
        "Amount_LCY": hdr["Amount_Including_VAT"],
        "Remaining_Amt_LCY": np.where(open_, hdr["Amount_Including_VAT"], 0.0),
        "Due_Date": hdr["Due_Date"],
        "Open": open_,
        "Closed_at_Date": pay.where(~open_),
        "Salesperson_Code": hdr["Salesperson_Code"],
    })
    return cle


# --------------------------------------------------------------------------
# Purchasing & inventory simulation
# --------------------------------------------------------------------------
def simulate_purchasing(rng, items, vendors, ln, hdr, issues):
    days = pd.date_range(START, END, freq="D")
    nd, ni = len(days), len(items)
    item_pos = {n: i for i, n in enumerate(items["No"])}
    dmap = hdr.set_index("No")["Posting_Date"]
    ln_dates = ln["Document_No"].map(dmap)
    di = ((ln_dates - START).dt.days).to_numpy()
    ii = ln["No"].map(item_pos)
    ok = ii.notna().to_numpy()
    sales = np.zeros((nd, ni))
    np.add.at(sales, (di[ok], ii[ok].astype(int).to_numpy()), ln["Quantity"].to_numpy()[ok])

    # "oracle" demand rate for items with short history (buyer's forecast)
    launch = items["_launch"].to_numpy()
    disc = items["_discontinued"].to_numpy()
    life_start = np.maximum((pd.to_datetime(launch) - START).days.to_numpy(), 0)
    life_end = np.where(pd.isna(disc), nd, (pd.to_datetime(disc) - START).days.to_numpy())
    total = sales.sum(axis=0)
    rate_life = total / np.maximum(life_end - life_start, 30)

    vendor_of = items["Vendor_No"].to_numpy()
    vend = vendors.set_index("No")
    # opening stock = ~50 days of demand
    stock = np.round(rate_life * 70 / 6) * 6
    stock[life_start > 0] = 0
    receipts = np.zeros((nd, ni))
    on_order = np.zeros(ni)
    po_headers, po_lines, ile = [], [], []
    ile.extend([("OPENING", items["No"].iat[i], START - pd.Timedelta(days=1), "Positive Adjmt.", "",
                 "INV-OPEN-2022", "", stock[i], "OPENING") for i in range(ni) if stock[i] > 0])
    next_order = {v: START + pd.Timedelta(days=int(rng.integers(0, vend.loc[v, "_cycle"])))
                  for v in vend.index}
    pending = []  # (arrival_day_index, item_idx, qty, po_no, line_no)
    po_seq = {}
    overstock_items = set(rng.choice(ni, size=6, replace=False))
    express_until = np.full(ni, -1)

    for t, d in enumerate(days):
        # receipts arriving today
        still = []
        for arr, i, q, po, lno in pending:
            if arr == t:
                receipts[t, i] += q
                on_order[i] -= q
            else:
                still.append((arr, i, q, po, lno))
        pending = still
        stock = stock + receipts[t] - sales[t]
        # monthly breakage & count differences
        if d.day == 28:
            br = (rng.random(ni) < 0.035) & (stock > 6)
            q = rng.integers(1, 4, ni) * br
            for i in np.flatnonzero(br):
                ile.append(("ADJ", items["No"].iat[i], d, "Negative Adjmt.", "", f"ADJ{d:%y%m}-{i:03d}", "",
                            -float(q[i]), "BREAKAGE"))
            stock = stock - q
        if d.weekday() >= 5:
            continue

        def create_po(v, vr, order_lines, lead, express=False):
            yy = d.strftime("%y")
            po_seq[yy] = po_seq.get(yy, 0) + 1
            po_no = f"PO{yy}-{po_seq[yy]:05d}"
            cur = vr["_cur"]
            vidx = VENDOR_PRICE_IDX[d.year]
            exp = d + pd.Timedelta(days=lead)
            reliability = 0.95 if express else vr["_reliability"]
            total_fc = 0.0
            for lno, (i, q) in enumerate(order_lines, start=1):
                cost_fc = round(items["_vendor_price_2023"].iat[i] * vidx * (1.06 if express else 1.0), 2)
                total_fc += cost_fc * q
                late = rng.random() > reliability
                delay = int(rng.integers(3, 22)) if late else int(rng.integers(-2, 2))
                if express:
                    delay = max(delay, 0) if not late else int(rng.integers(1, 4))
                arr = max(exp + pd.Timedelta(days=delay), d + pd.Timedelta(days=1))
                while arr.weekday() >= 5:
                    arr += pd.Timedelta(days=1)
                received = q
                if not express and rng.random() < 0.04:
                    received = int(np.floor(q * rng.uniform(0.6, 0.95) / 6) * 6)
                arrived = arr <= END
                on_order[i] += received
                if arrived:
                    pending.append(((arr - START).days, i, received, po_no, lno * 10000))
                po_lines.append({
                    "Document_No": po_no, "Line_No": lno * 10000, "Type": "Item", "No": items["No"].iat[i],
                    "Location_Code": LOCATION, "Unit_of_Measure_Code": "FL", "Quantity": q,
                    "Direct_Unit_Cost": cost_fc, "Line_Amount": round(cost_fc * q, 2),
                    "Expected_Receipt_Date": exp, "Quantity_Received": received if arrived else 0,
                    "_arrival": arr if arrived else pd.NaT,
                })
                if arrived:
                    ile.append(("PURCH", items["No"].iat[i], arr, "Purchase", "Purchase Receipt",
                                f"PR{arr:%y}-{po_no[5:]}", po_no, float(received), ""))
            po_headers.append({"No": po_no, "Buy_from_Vendor_No": v, "Buy_from_Vendor_Name": vr["Name"],
                               "Order_Date": d, "Expected_Receipt_Date": exp,
                               "Currency_Code": "" if cur == "EUR" else cur,
                               "Shipment_Method_Code": "EXPRESS" if express else "STANDARD",
                               "_amount_fc": total_fc})

        # express re-orders when cover drops below ~6 days and nothing arrives soon
        rate14 = sales[max(0, t - 14):t + 1].mean(axis=0)
        arriving_soon = np.zeros(ni)
        for arr, i, q, po, lno in pending:
            if arr <= t + 5:
                arriving_soon[i] += q
        low = np.flatnonzero((stock + arriving_soon < rate14 * 6) & (rate14 > 0) & (express_until < t))
        by_vendor = {}
        for i in low:
            if not pd.isna(disc[i]) and pd.Timestamp(disc[i]) <= d:
                continue
            by_vendor.setdefault(vendor_of[i], []).append(i)
        for v, its in by_vendor.items():
            vr = vend.loc[v]
            lead_x = max(2, int(vr["Lead_Time_Days"]) // 4)
            lines_x = [(i, int(np.ceil(rate14[i] * (lead_x + 21) / 6) * 6)) for i in its]
            create_po(v, vr, lines_x, lead_x, express=True)
            for i in its:
                express_until[i] = t + lead_x + 5

        for v, nxt in list(next_order.items()):
            if d < nxt:
                continue
            vr = vend.loc[v]
            next_order[v] = d + pd.Timedelta(days=int(vr["_cycle"] + rng.integers(-3, 4)))
            v_items = np.flatnonzero(vendor_of == v)
            lead = int(vr["Lead_Time_Days"])
            horizon = int(vr["_cycle"]) + lead + 35
            order_lines = []
            for i in v_items:
                if not pd.isna(disc[i]) and pd.Timestamp(disc[i]) <= d + pd.Timedelta(days=lead):
                    continue
                if pd.Timestamp(launch[i]) > d + pd.Timedelta(days=lead + 20):
                    continue
                hist_days = t - life_start[i]
                rate = max(sales[max(0, t - 56):t, i].mean(), sales[max(0, t - 21):t, i].mean()) \
                    if hist_days >= 56 else rate_life[i]
                # seasonal look-ahead (buyers know December is big)
                ahead = (d + pd.Timedelta(days=horizon // 2)).month
                cat = items["Item_Category_Code"].iat[i]
                rate *= SEASON[cat][ahead - 1] / SEASON[cat][d.month - 1]
                target = rate * horizon * rng.lognormal(0, 0.12)
                q = target - (stock[i] + on_order[i])
                if q < 12:
                    continue
                q = int(np.ceil(q / 6) * 6)
                if i in overstock_items and d.year == 2025 and d.month in (2, 3) and rng.random() < 0.7:
                    q *= 6     # buyer error / bulk deal -> slow-moving stock
                order_lines.append((i, q))
            if order_lines:
                create_po(v, vr, order_lines, lead)

    # sales ILE
    s_ile = pd.DataFrame({
        "Item_No": ln["No"], "Posting_Date": ln_dates, "Entry_Type": "Sale",
        "Document_Type": "Sales Invoice", "Document_No": ln["Document_No"], "Order_No": "",
        "Quantity": -ln["Quantity"].astype(float), "Reason_Code": ""})
    o_ile = pd.DataFrame([r[1:] for r in ile], columns=["Item_No", "Posting_Date", "Entry_Type",
                                                        "Document_Type", "Document_No", "Order_No",
                                                        "Quantity", "Reason_Code"])
    # planted: large negative adjustments without reason code (shrinkage control)
    sus = []
    for k in range(9):
        i = int(rng.integers(0, ni))
        d = START + pd.Timedelta(days=int(rng.integers(100, nd - 5)))
        sus.append({"Item_No": items["No"].iat[i], "Posting_Date": d, "Entry_Type": "Negative Adjmt.",
                    "Document_Type": "", "Document_No": f"ADJ{d:%y%m}-X{k:02d}", "Order_No": "",
                    "Quantity": -float(rng.choice([24, 36, 48, 72, 120])), "Reason_Code": ""})
    issues["LARGE_ADJUSTMENT_NO_REASON"] = len(sus)
    ile_df = pd.concat([o_ile, s_ile, pd.DataFrame(sus)], ignore_index=True)
    ile_df = ile_df.sort_values(["Posting_Date", "Entry_Type", "Document_No"], kind="stable").reset_index(drop=True)
    ile_df.insert(0, "Entry_No", np.arange(1, len(ile_df) + 1))
    ile_df["Location_Code"] = LOCATION
    ile_df = ile_df[["Entry_No", "Item_No", "Posting_Date", "Entry_Type", "Document_Type", "Document_No",
                     "Order_No", "Location_Code", "Quantity", "Reason_Code"]]

    ph = pd.DataFrame(po_headers)
    pl = pd.DataFrame(po_lines)
    # status
    ph["Status"] = "Released"
    # approvals - policy: approver != creator; POs >= 50k EUR need CFO approval
    ph["Created_By"] = rng.choice(PURCHASE_USERS, size=len(ph))
    fx_rough = ph["Currency_Code"].map({"": 1.0, "USD": 1.10, "GBP": 0.86}).fillna(1.0)
    ph["Amount_EUR_approx"] = (ph["_amount_fc"] / fx_rough).round(2)
    ph["Approved_By"] = np.where(ph["Amount_EUR_approx"] >= 50000, CFO, HEAD_OF_PURCHASING)
    ph["Approval_Date"] = ph["Order_Date"] - pd.to_timedelta(rng.integers(0, 2, len(ph)), unit="D")
    sod = rng.choice(ph.index, size=int(len(ph) * 0.03), replace=False)
    ph.loc[sod, "Approved_By"] = ph.loc[sod, "Created_By"]
    big = ph.index[ph["Amount_EUR_approx"] >= 50000]
    wrong = rng.choice(big, size=min(6, len(big)), replace=False) if len(big) else []
    ph.loc[wrong, "Approved_By"] = HEAD_OF_PURCHASING
    noapp = rng.choice(ph.index.difference(sod), size=5, replace=False)
    ph.loc[noapp, ["Approved_By", "Approval_Date"]] = ["", pd.NaT]
    issues["PO_SELF_APPROVED"] = len(sod)
    issues["PO_ABOVE_LIMIT_WITHOUT_CFO"] = len(wrong)
    issues["PO_WITHOUT_APPROVAL"] = len(noapp)
    ph = ph.drop(columns=["_amount_fc", "Amount_EUR_approx"])
    pl = pl.drop(columns=["_arrival"])
    return ph, pl, ile_df, stock


# --------------------------------------------------------------------------
# Excel budget (wide format, like a real controlling file)
# --------------------------------------------------------------------------
def build_budget(rng, hdr, ln, items, out_path: Path):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    cat = items.set_index("No")["Item_Category_Code"]
    df = ln.merge(hdr[["No", "Posting_Date", "Salesperson_Code"]], left_on="Document_No", right_on="No",
                  suffixes=("", "_h"))
    df["cat"] = df["No"].map(cat)
    df = df.dropna(subset=["cat"])
    df = df[df["Salesperson_Code"].isin([s[0] for s in SALESPEOPLE])]
    df["y"] = df["Posting_Date"].dt.year
    df["m"] = df["Posting_Date"].dt.month
    act = df.groupby(["Salesperson_Code", "cat", "y", "m"])["Amount"].sum()
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    rep_growth = {s[0]: rng.uniform(1.03, 1.09) for s in SALESPEOPLE}
    cat_growth = {"WHISKY": 1.03, "GIN": 1.02, "RUM": 1.06, "VODKA": 1.00, "LIQUEUR": 1.02, "BRANDY": 1.00}
    rows = []
    for y in (2024, 2025, 2026):
        for s in SALESPEOPLE:
            for c in CATEGORIES:
                vals = []
                for m in range(1, 13):
                    base = act.get((s[0], c, y - 1, m), 0.0)
                    vals.append(round(base * rep_growth[s[0]] * cat_growth[c] * rng.normal(1, 0.04) / 100) * 100)
                rows.append([s[0], s[1], c, y] + vals + [sum(vals)])
    wb = Workbook()
    ws = wb.active
    ws.title = "Budget"
    ws["A1"] = "Hanse Spirits Trading GmbH – Sales Budget (net revenue, EUR)"
    ws["A1"].font = Font(bold=True, size=14)
    ws["A2"] = "Version: FINAL · approved by management board · Owner: Controlling"
    ws["A2"].font = Font(italic=True, color="666666")
    header = ["Salesperson_Code", "Salesperson", "Item_Category", "Year"] + months + ["Total"]
    ws.append([])
    ws.append(header)
    for r in rows:
        ws.append(r)
    fill = PatternFill("solid", fgColor="1F3A5F")
    for col in range(1, len(header) + 1):
        c = ws.cell(row=4, column=col)
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = fill
        c.alignment = Alignment(horizontal="center")
        ws.column_dimensions[get_column_letter(col)].width = 12 if col > 4 else 18
    for row in ws.iter_rows(min_row=5, min_col=5, max_col=len(header)):
        for c in row:
            c.number_format = "#,##0"
    ws.freeze_panes = "E5"
    notes = wb.create_sheet("Notes")
    for r in [["Sales budget 2024–2026"],
              ["Granularity: salesperson x item category x month (net revenue after line discounts, EUR)"],
              ["Basis: prior-year actuals x growth targets agreed in the annual planning round"],
              ["Key accounts (IK) and e-commerce (JS) are planned separately from regional reps"],
              ["Format: months as columns (wide) – unpivot in Power Query before loading"]]:
        notes.append(r)
    notes.column_dimensions["A"].width = 100
    out_path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(out_path)
    print(f"  {out_path.name}: {len(rows)} budget rows (wide)")


# --------------------------------------------------------------------------
# Master-data issues
# --------------------------------------------------------------------------
def plant_master_issues(rng, cust, items, vendors, issues):
    # duplicate customers (same company created twice, slightly different spelling)
    src = cust[(cust["Customer_Price_Group"] == "HORECA") & (cust["Blocked"] == "")].sample(8, random_state=3)
    dups = []
    for k, (_, c) in enumerate(src.iterrows()):
        d = c.copy()
        d["No"] = f"C-{12001 + k}"
        d["Name"] = rng.choice([c["Name"].upper(), c["Name"] + " ", c["Name"].replace(" ", "  ", 1),
                                c["Name"] + " GmbH"])
        d["Created_Date"] = END - pd.Timedelta(days=int(rng.integers(30, 400)))
        d["_freq"] = 0.0
        dups.append(d)
    cust = pd.concat([cust, pd.DataFrame(dups)], ignore_index=True)
    issues["DUPLICATE_CUSTOMER"] = len(dups)
    # missing master data
    idx = rng.choice(cust.index[cust["Salesperson_Code"] != "IK"], size=10, replace=False)
    cust.loc[idx[:6], "Salesperson_Code"] = ""
    cust.loc[idx[6:], "Post_Code"] = ""
    idx = rng.choice(items.index, size=5, replace=False)
    items.loc[idx, "Item_Category_Code"] = ""
    vendors.loc[rng.choice(vendors.index, size=3, replace=False), "Payment_Terms_Code"] = ""
    issues["MISSING_MASTER_DATA"] = 6 + 4 + 5 + 3
    return cust, items, vendors


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[1] / "data"))
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--fx-file", default=None, help="optional real ECB rates (see fetch_ecb_rates.py)")
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)
    out = Path(args.out)
    issues: dict[str, int] = {}

    print("Building master data ...")
    sp = build_salespeople()
    vendors = build_vendors()
    items = build_items(rng, vendors)
    cust = build_customers(rng)
    hol = holidays.Germany(subdiv="HB", years=range(2022, 2027), language="de")
    hol_dates = {pd.Timestamp(d) for d in hol}

    print("Building FX & cost / price tables ...")
    fx = build_fx(rng, args.fx_file)
    fxm = monthly_fx(fx)
    cost_m = item_cost_matrix(items, fxm)
    price_y = list_price_by_year(items)
    items["Unit_Price"] = price_y[END.year]
    items["Unit_Cost"] = cost_m[-1]
    items["Last_Direct_Cost"] = np.round(items["_vendor_price_2023"] * VENDOR_PRICE_IDX[END.year], 2)

    print("Simulating sales (this takes ~1-2 minutes) ...")
    hdr, ln = generate_sales(rng, cust, items, cost_m, price_y, hol_dates)
    hdr, ln = plant_sales_issues(rng, hdr, ln, cust, items, hol_dates, issues)
    hdr_full, hdr_out, ln_out = finalize_sales(rng, hdr, ln, cust, items, cost_m)
    cle = build_customer_ledger(rng, hdr_full, cust)

    print("Simulating purchasing & inventory ...")
    ph, pl, ile, _ = simulate_purchasing(rng, items, vendors, ln_out, hdr_full, issues)

    build_budget(rng, hdr_full, ln_out, items, out / "excel" / "sales_budget_2024_2026.xlsx")
    cust, items, vendors = plant_master_issues(rng, cust, items, vendors, issues)

    print(f"Writing files to {out} ...")
    erp = out / "erp"
    write_csv(sp, erp / "salesperson.csv")
    write_csv(cust[["No", "Name", "Address", "Post_Code", "City", "County", "Country_Region_Code", "Latitude",
                    "Longitude", "Customer_Posting_Group", "Customer_Price_Group", "Gen_Bus_Posting_Group",
                    "Salesperson_Code", "Payment_Terms_Code", "Credit_Limit_LCY", "Blocked", "Blocked_Date",
                    "Created_Date"]], erp / "customer.csv")
    write_csv(vendors[["No", "Name", "Country_Region_Code", "Currency_Code", "Payment_Terms_Code",
                       "Lead_Time_Days", "Vendor_Posting_Group", "Blocked"]], erp / "vendor.csv")
    write_csv(items[["No", "Description", "Item_Category_Code", "Brand", "Vendor_No", "Base_Unit_of_Measure",
                     "Bottle_Size_L", "Alcohol_Pct", "Country_of_Origin", "Unit_Price", "Unit_Cost",
                     "Last_Direct_Cost", "Blocked", "Blocked_Date", "Created_Date"]], erp / "item.csv")
    write_csv(hdr_out, erp / "sales_invoice_header.csv")
    write_csv(ln_out, erp / "sales_invoice_line.csv")
    write_csv(ph, erp / "purchase_header.csv")
    write_csv(pl, erp / "purchase_line.csv")
    write_csv(ile, erp / "item_ledger_entry.csv")
    write_csv(cle, erp / "cust_ledger_entry.csv")

    ext = out / "external"
    write_csv(fx, ext / "fx_rates_daily.csv")
    write_csv(pd.DataFrame([{"Holiday_Date": pd.Timestamp(d), "Holiday_Name": n, "Subdivision": "HB"}
                            for d, n in sorted(hol.items())]), ext / "public_holidays_de_hb.csv")
    write_csv(pd.DataFrame([{"Product_Group": "SPIRITS", "Valid_From": pd.Timestamp("2010-01-01"),
                             "Valid_To": pd.NaT, "Rate_EUR_per_hl_pure_alcohol": EXCISE_EUR_PER_HL_PURE_ALCOHOL,
                             "Legal_Basis": "Alkoholsteuergesetz (AlkStG) §2"}]),
              ext / "excise_duty_rates.csv")

    print("\nPlanted data-quality / control issues:")
    for k, v in issues.items():
        print(f"  {k:32s} {v}")
    print("\nDone.")


if __name__ == "__main__":
    main()
