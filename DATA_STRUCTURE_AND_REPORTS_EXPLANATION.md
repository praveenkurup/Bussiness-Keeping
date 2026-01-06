# Firebase Data Structure & Reports Details Page - Complete Explanation

## Table of Contents
1. [Firebase Database Structure](#firebase-database-structure)
2. [Data Flow in Reports Detail Screen](#data-flow-in-reports-detail-screen)
3. [Data Aggregation Process](#data-aggregation-process)
4. [Calculations and Display Logic](#calculations-and-display-logic)
5. [Key Data Transformations](#key-data-transformations)

---

## Firebase Database Structure

### 1. **Configs Collection** (`configs/{uid}`)
This stores the business configuration and master data:

```dart
{
  'business_name': String,
  'address': String,
  'email': String,
  'phone': String,
  'vendors': List<String>,              // List of vendor names
  'expenses': List<String>,              // List of expense category names
  'special_pricing_vendors': List<String>, // Vendors with special pricing
  'special_prices': {                    // Special prices per vendor
    'vendorName': {
      'itemCode': price (double)
    }
  },
  'staffs_email': List<String>,
  'staffs_uid': List<String>,
  'fcm_token': String,
  'fcm_token_updated_at': Timestamp
}
```

**Subcollection: `items`** (`configs/{uid}/items/{itemId}`)
```dart
{
  'name': String,    // Item display name
  'code': String,    // Item code (unique identifier)
  'price': double    // Default price per unit
}
```

### 2. **Daily Sales Collection** (`daily_sales/{uid}/{YYYY-MM-DD}/data`)
This stores individual daily reports:

```dart
{
  'items_sales': {                    // Total quantity per item across all vendors
    'itemCode1': quantity (int),
    'itemCode2': quantity (int),
    ...
  },
  'vendor_sales': {                   // Sales breakdown by vendor
    'vendorName1': {
      'sale': totalQuantity (int),    // Total items sold to this vendor
      'revenue': totalRevenue (int),   // Total revenue from this vendor
      'items': {                      // Item breakdown for this vendor
        'itemCode1': quantity (int),
        'itemCode2': quantity (int),
        ...
      }
    },
    'vendorName2': { ... },
    ...
  },
  'expenses': {                       // Expenses by category
    'expenseCategory1': amount (int),
    'expenseCategory2': amount (int),
    ...
  },
  'total_sales': int,                 // Total quantity of all items sold
  'total_revenue': int,               // Total revenue from all sales
  'total_expenses': int,              // Sum of all expenses
  'net_profit': int,                 // total_revenue - total_expenses
  'addition_revenue': int,           // Additional revenue (non-item sales)
  'item_prices_snapshot': {           // Prices at time of report creation
    'itemCode': price (double)
  },
  'special_prices': {                 // Special prices used in this report
    'vendorName': {
      'itemCode': price (double)
    }
  }
}
```

**Metadata Document:** `daily_sales/{uid}/{YYYY-MM-DD}/metadata`
```dart
{
  'exists': bool,
  'added_by': String,  // UID of user who created/edited
  'added_at': String   // Formatted date/time string
}
```

### 3. **Total Report Collection** (`total_report/{uid}`)
Aggregated totals across all dates (not used in reports detail screen, but exists for reference):
```dart
{
  'items_sales': { ... },
  'vendor_sales': { ... },
  'total_sales': int,
  'total_revenue': int,
  'total_expenses': int,
  'net_profit': int,
  'addition_revenue': int,
  'dates_with_data': List<String>  // List of YYYY-MM-DD dates
}
```

---

## Data Flow in Reports Detail Screen

### Step 1: Initialization (`_loadData()`)
When `ReportsDetailScreen` is opened with a date range:

1. **Load User Config** (`FirestoreService.getUserConfig()`)
   - Fetches from `configs/{uid}` document
   - Retrieves items subcollection
   - Returns map with business info, vendors, expenses, items, and special pricing

2. **Load Aggregated Report** (`FirestoreService.getReportsByDateRange()`)
   - Iterates through each date from `startDate` to `endDate`
   - For each date, fetches `daily_sales/{uid}/{YYYY-MM-DD}/data`
   - Aggregates all daily reports using `_aggregateReports()` method
   - Returns single aggregated report map

### Step 2: Data Aggregation (`_aggregateReports()`)
Located in `firestore_service.dart`, this method:

1. **Initializes aggregation maps:**
   ```dart
   Map<String, int> aggregatedItemsSales = {};  // itemCode -> total quantity
   Map<String, Map<String, dynamic>> aggregatedVendorSales = {};  // vendor -> data
   Map<String, int> aggregatedExpenses = {};  // expenseCategory -> total amount
   ```

2. **Iterates through each daily report:**
   - Sums `total_sales`, `total_revenue`, `total_expenses`, `addition_revenue`
   - Aggregates `items_sales`: adds quantities for each item code
   - Aggregates `vendor_sales`: 
     - For each vendor, sums `sale` (quantity) and `revenue`
     - Aggregates `items` map within each vendor
   - Aggregates `expenses`: sums amounts for each expense category

3. **Calculates final totals:**
   ```dart
   net_profit = total_revenue - total_expenses
   ```

4. **Returns aggregated map:**
   ```dart
   {
     'total_sales': int,
     'total_revenue': int,
     'total_expenses': int,
     'net_profit': int,
     'addition_revenue': int,
     'items_sales': Map<String, int>,
     'vendor_sales': Map<String, Map<String, dynamic>>,
     'expenses': Map<String, int>
   }
   ```

---

## Calculations and Display Logic

### 1. **Item Display Processing** (Lines 378-443)

The screen processes `items_sales` from the aggregated report:

```dart
final Map<String, dynamic> itemsSales = 
    _aggregatedReport!['items_sales'] as Map<String, dynamic>? ?? {};
```

**For each item code:**
1. **Get Display Name:** Uses `_getItemDisplayName(code)` which:
   - Looks up item in `_userConfig['items']`
   - Returns format: `"ItemName (CODE)"` or just `"CODE"` if name not found

2. **Get Price:** Uses `_getNormalPriceForItem(code)`:
   - Searches config items for matching code
   - Returns the `price` field from config

3. **Build Vendor Breakdown:**
   - Iterates through `vendor_sales`
   - For each vendor, checks if vendor's `items` map contains this item code
   - Creates list: `["Vendor1 - 10", "Vendor2 - 5"]`

4. **Create `_ItemData` object:**
   ```dart
   _ItemData(
     title: displayName,
     quantity: totalQuantity,
     pricePerItem: price,
     vendors: vendorBreakdown,
     color: assignedColor
   )
   ```

5. **Sort by quantity** (highest first)

### 2. **Vendor Display Processing** (Lines 465-530)

The screen processes `vendor_sales` from the aggregated report:

**For each vendor:**
1. **Calculate Vendor Revenue:**
   ```dart
   vendorRevenue = 0
   for each item in vendor.items:
     quantity = vendor.items[itemCode]
     price = _getCorrectPriceForVendorAndItem(vendorName, itemCode)
     itemRevenue = quantity * price
     vendorRevenue += itemRevenue
   ```

2. **Price Resolution Logic** (`_getCorrectPriceForVendorAndItem`):
   - First checks `special_prices` in config for this vendor
   - If special price exists for this item code, use it
   - Otherwise, falls back to normal price from config

3. **Calculate Pie Chart Percentages:**
   - First pass: Calculate total revenue across all vendors
   - Second pass: Calculate each vendor's percentage:
     ```dart
     percentage = (vendorRevenue / totalRevenueForPieChart) * 100
     ```

4. **Sort vendors by revenue percentage** (highest first)

### 3. **Summary Metrics Display** (Lines 604-625)

Directly displays from aggregated report:
- **Total Sales:** `_aggregatedReport['total_sales']` (total quantity)
- **Total Revenue:** `_aggregatedReport['total_revenue']` (total money)
- **Total Expense:** `_aggregatedReport['total_expenses']`
- **Addition Revenue:** `_aggregatedReport['addition_revenue']`
- **Net Profit:** `_aggregatedReport['net_profit']` (calculated as revenue - expenses)
- **Best Performing Item:** First item in sorted items list (highest quantity)
- **Best Performing Vendor:** First vendor in sorted vendor map (highest revenue)

### 4. **Pie Charts** (Lines 632-721)

**Items Pie Chart:**
- Data: Percentage of each item's quantity relative to total quantity
- Calculation: `(item.quantity / totalQuantity) * 100`
- Colors: Assigned from color palette based on sorted order

**Vendors Pie Chart:**
- Data: Percentage of each vendor's revenue relative to total revenue
- Calculation: `(vendorRevenue / totalRevenueForPieChart) * 100`
- Colors: Assigned from color palette based on sorted order

### 5. **Quantity Produced Section** (Lines 725-748)

Displays expandable cards for each item:
- Shows item name, total quantity, color indicator
- When expanded:
  - Shows vendor breakdown (e.g., "Vendor1 - 10")
  - Shows revenue calculation: `quantity × price = revenue`
  - Shows price per item

### 6. **Vendors Section** (Lines 750-812)

Displays expandable cards for each vendor:
- Shows vendor name, total revenue, color indicator
- When expanded:
  - Shows item breakdown: `"ItemName - quantity × price = ₹revenue"`
  - Shows total quantity for vendor
  - Shows total revenue

**Item Revenue Calculation in Vendor Card:**
```dart
for each item in vendor.items:
  quantity = vendor.items[itemCode]
  price = _getCorrectPriceForVendorAndItem(vendorName, itemCode)
  itemRevenue = (quantity * price).round()
  display: "ItemName - quantity × price = ₹itemRevenue"
```

### 7. **Expenses Section** (Lines 815-839)

Displays each expense category:
- Shows expense name and amount from `expenses` map
- Shows total expenses at bottom

---

## Key Data Transformations

### Transformation 1: Daily Reports → Aggregated Report
**Input:** List of daily report maps
**Process:** Sum all numeric fields, merge maps
**Output:** Single aggregated map with totals

### Transformation 2: Items Sales → Display Items
**Input:** `items_sales: {code: quantity}`
**Process:**
- Look up item names from config
- Calculate vendor breakdown from `vendor_sales`
- Assign colors
- Sort by quantity
**Output:** List of `_ItemData` objects

### Transformation 3: Vendor Sales → Display Vendors
**Input:** `vendor_sales: {vendor: {sale, revenue, items}}`
**Process:**
- Calculate revenue using special/normal prices
- Calculate percentages for pie chart
- Build item breakdown strings
- Sort by revenue
**Output:** Sorted vendor map with display data

### Transformation 4: Price Resolution
**Input:** Vendor name, item code
**Process:**
1. Check `config.special_prices[vendorName][itemCode]`
2. If not found, check `config.items[itemCode].price`
3. Return price
**Output:** Final price to use for calculations

---

## Important Notes

1. **Price Handling:**
   - Special prices override normal prices for specific vendor-item combinations
   - Prices are resolved at display time, not stored in aggregated report
   - This allows price changes in config to reflect in historical reports

2. **Revenue Calculation:**
   - Revenue is calculated using current config prices (special or normal)
   - This means revenue may differ from what was stored in daily reports if prices changed

3. **Data Aggregation:**
   - All daily reports in date range are summed together
   - Vendor items are merged (quantities added)
   - Expenses are summed by category

4. **Staff Support:**
   - If user is staff, data is fetched from admin's UID
   - `getReportsByDateRange` uses current user's UID (not staff admin UID)
   - This may need adjustment if staff should see aggregated reports

5. **Date Format:**
   - All dates stored as `YYYY-MM-DD` strings
   - Used as collection names in `daily_sales/{uid}/{YYYY-MM-DD}`

---

## Code Flow Summary

```
ReportsDetailScreen.initState()
  └─> _loadData()
      ├─> FirestoreService.getUserConfig()
      │   └─> Fetches configs/{uid} + items subcollection
      │
      └─> FirestoreService.getReportsByDateRange(startDate, endDate)
          ├─> For each date in range:
          │   └─> Fetch daily_sales/{uid}/{YYYY-MM-DD}/data
          │
          └─> _aggregateReports(reports)
              └─> Sum all fields, merge maps
                  └─> Return aggregated map

ReportsDetailScreen.build()
  ├─> Process items_sales → Create _ItemData list
  │   ├─> Get display names from config
  │   ├─> Get prices from config
  │   ├─> Build vendor breakdowns
  │   └─> Sort by quantity
  │
  ├─> Process vendor_sales → Create vendor display data
  │   ├─> Calculate revenue using special/normal prices
  │   ├─> Calculate pie chart percentages
  │   ├─> Build item breakdown strings
  │   └─> Sort by revenue
  │
  └─> Display:
      ├─> Summary metrics (direct from aggregated report)
      ├─> Pie charts (items by quantity %, vendors by revenue %)
      ├─> Quantity Produced (expandable item cards)
      ├─> Vendors (expandable vendor cards)
      └─> Expenses (list of expense categories)
```

---

This document provides a complete understanding of how data flows from Firebase through the aggregation process to the final display in the Reports Detail Screen.


