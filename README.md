# ETL Pipelines and Cloud Solution Projects

This repository contains two projects showcasing my skills in building end-to-end ETL pipelines and implementing cloud-based data solutions:

## 📁 Projects

### 1. Cloud Solution – Lufthansa Task

**Objective:**  
Design and implement a cloud-based data pipeline solution on Microsoft Azure, based on the Medallion Architecture (Bronze, Silver, Gold layers), including storage, transformation, and validation steps.

**Overview of the Process:**
- **Storage Setup:** Created Azure Storage Account and organized data into Bronze, Silver, and Gold layers.
- **Data Ingestion:** Used Azure Data Factory to fetch and load raw data into Bronze.
- **Data Transformation:** Set up Azure Databricks workspace to perform:
  - Data cleaning (dropping and replacing missing values)
  - Creating calculated columns (e.g., Total Price, Delivery Time, Payment Count, Profit Margin)
  - Applying window functions for advanced metrics
- **Data Structuring:**  
  - Moved processed data into Silver layer.
  - Split data into Fact and Dimension tables for the Gold layer.
- **Validation and Reporting:**  
  - Loaded the Gold layer data into Azure SQL Database.
  - Created SQL queries to validate and report KPIs like Total Sales per Product Category, Average Delivery Time per Seller, and Orders per State.

**Technologies Used:**
- Azure Storage Account
- Azure Data Factory
- Azure Databricks
- Azure SQL Database
- Python (PySpark)

---

### 2. On-Premise Solution – Lufthansa Task

**Objective:**  
Build a complete ETL pipeline on a local environment using Python and Microsoft SQL Server, based on the Brazilian E-commerce (Olist) dataset.

**Overview of the Process:**
- **Data Source:** Downloaded Olist dataset from Kaggle (multiple CSV files).
- **Data Cleaning:**
  - Handled missing values appropriately.
  - Removed duplicate records.
- **Feature Engineering:**
  - Created calculated fields (Total Price, Delivery Time, Payment Count, Profit Margin).
- **Window Functions:**  
  - Calculated Total Sales per Customer and Average Delivery Time per Product Category using pandas' `groupby()` and `rolling()` functionalities.
- **Data Warehousing:**
  - Designed Fact and Dimension tables.
  - Loaded cleaned datasets into SQL Server using SQLAlchemy or pyodbc.
- **Validation and Reporting:**
  - Wrote SQL scripts to query and validate KPIs such as total sales, average delivery time, and orders by customer state.

**Technologies Used:**
- Python (pandas, pyodbc, SQLAlchemy)
- Microsoft SQL Server 2022
- SQL Server Management Studio (SSMS)
- Jupyter Notebook

---

## 🛠️ How to Run

1. Clone this repository.
2. Install required Python libraries:
   ```bash
   pip install pandas pyodbc SQLAlchemy

