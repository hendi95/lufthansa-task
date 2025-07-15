USE [KESH]
GO
/****** Object:  Table [dbo].[staging_water_level_Vau_Dejes]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_water_level_Vau_Dejes](
	[time] [datetime] NOT NULL,
	[downstream_water_level] [decimal](10, 5) NOT NULL,
	[upstream_reservoir_level] [decimal](10, 5) NOT NULL
) ON [PRIMARY]
GO
/****** Object:  View [dbo].[vw_cascada]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [dbo].[vw_cascada] AS
WITH Data AS (
    SELECT 
        [time],
        upstream_reservoir_level AS [Level up Vau Deje (m)],
        downstream_water_level AS [Level down Vau Deje (m)],
        upstream_reservoir_level - downstream_water_level AS [H (m)],
        LAG(upstream_reservoir_level) OVER (ORDER BY [time]) AS prev_upstream_level,
        DATEDIFF(MINUTE, LAG([time]) OVER (ORDER BY [time]), [time]) AS time_diff
    FROM staging_water_level_Vau_Dejes
),
Computed AS (
    SELECT 
        [time],
        [Level up Vau Deje (m)],
        [Level down Vau Deje (m)],
        [H (m)],
        CASE 
            WHEN time_diff < 15 OR time_diff IS NULL THEN 0 
            ELSE ([Level up Vau Deje (m)] - prev_upstream_level) * 100 
        END AS [dif (cm)],
        0 AS [AG 1 (MW)],
        0 AS [AG 2 (MW)],
        0 AS [AG 3 (MW)],
        0 AS [AG 4 (MW)],
        0 AS [AG 5 (MW)],
        0 AS [spillway from tunele (m³/sek)],
        0 AS [Discharge total Koman (m³/sek)]
    FROM Data
),
Final AS (
    SELECT 
        c.*,
        ([AG 1 (MW)] + [AG 2 (MW)] + [AG 3 (MW)] + [AG 4 (MW)] + [AG 5 (MW)]) AS [Total generation (MW)]
    FROM Computed c
),
RealFinal AS (
    SELECT 
        f.*,
        CASE 
            WHEN [H (m)] IS NULL THEN 0 
            ELSE ([Total generation (MW)] * (0.0013 * POWER((55 - [H (m)]), 2) + 0.044 * (55 - [H (m)]) + 2.16)) 
        END AS [Turbine Flow (m³/sek)],
        CASE 
            WHEN [Level up Vau Deje (m)] IS NULL OR [H (m)] IS NULL THEN 0 
            ELSE ([dif (cm)] * ((-0.003 * POWER(([Level up Vau Deje (m)] - 59), 2)) + 1.299 * ([Level up Vau Deje (m)] - 59) + 49.7)) 
        END AS [Inflows Vau Deje (m³/sek)]
    FROM Final f
)
SELECT 
    time, 
    [Level up Vau Deje (m)], 
    [Level down Vau Deje (m)], 
    [H (m)], 
    [dif (cm)],
    [Inflows Vau Deje (m³/sek)], 
    [Inflows Vau Deje (m³/sek)] - [Discharge total Koman (m³/sek)] AS [Inflows (from tributaries) V. Deje (m³/sek)],
    [AG 1 (MW)], 
    [AG 2 (MW)], 
    [AG 3 (MW)], 
    [AG 4 (MW)], 
    [AG 5 (MW)], 
    [Total generation (MW)],
    [spillway from tunele (m³/sek)], 
    [Turbine Flow (m³/sek)],
    ([spillway from tunele (m³/sek)] + [Turbine Flow (m³/sek)]) AS [Discharge total Vau Deje (m³/sek)], 
    [Discharge total Koman (m³/sek)]
FROM RealFinal;
GO
/****** Object:  View [dbo].[vw_CHARACTERISTICS_OF_POWER_PLANT]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [dbo].[vw_CHARACTERISTICS_OF_POWER_PLANT] AS
WITH HPP_Data AS (
    SELECT 
        'Fierza' AS HPP, 'Average' AS Schedule, 103 AS H_m
    UNION ALL
    SELECT 
        'Fierza', 'Economic', 103.25 AS H_m
    UNION ALL
    SELECT 
        'Koman', 'Average', 97 AS H_m
    UNION ALL
    SELECT 
        'Koman', 'Economic', 97.16 AS H_m
    UNION ALL
    SELECT 
        'Vau Deje', 'Average', 51 AS H_m
    UNION ALL
    SELECT 
        'Vau Deje', 'Economic', 51.20 AS H_m
),
Min_H_m AS (
    SELECT 
        HPP,
        MIN(H_m) AS Min_H_m
    FROM HPP_Data
    GROUP BY HPP
),
Load_Calculations AS (
    SELECT 
        d.HPP,
        d.Schedule,
        d.H_m,
        m.Min_H_m,
        ROUND(CASE 
            WHEN d.HPP = 'Fierza' THEN -1.386 * (121 - m.Min_H_m) + 126.4
            WHEN d.HPP = 'Koman' THEN -1.85 * (98 - m.Min_H_m) + 151.8
            WHEN d.HPP = 'Vau Deje' THEN 51.5 - 1.45 * (54 - m.Min_H_m)
        END, 1) AS Max_Load_Allowed_MW,
        ROUND(CASE 
            WHEN d.HPP = 'Fierza' THEN -1.128 * (125 - m.Min_H_m) + 113.8
            WHEN d.HPP = 'Koman' THEN (-0.00132 * POWER(103 - m.Min_H_m, 3)) + (0.007 * POWER(103 - m.Min_H_m, 2)) - 1.48 * (103 - m.Min_H_m) + 136.7
            WHEN d.HPP = 'Vau Deje' THEN (-0.03 * POWER(52 - m.Min_H_m, 2)) - 1.07 * (52 - m.Min_H_m) + 43.6
        END, 1) AS Load_MW
    FROM HPP_Data d
    JOIN Min_H_m m ON d.HPP = m.HPP
),
Flow_Calculations AS (
    SELECT 
        d.HPP,
        d.Schedule,
        d.H_m,
        m.Min_H_m,
        ROUND(CASE 
            WHEN d.HPP = 'Fierza' AND d.Schedule = 'Average' THEN ((0.38E-7 * POWER(d.H_m - 69, 4)) - (1.45E-5 * POWER(d.H_m - 69, 3)) + (0.0018 * POWER(d.H_m - 69, 2)) - 0.118 * (d.H_m - 69) + 6.53) / 3.6
            WHEN d.HPP = 'Fierza' AND d.Schedule = 'Economic' THEN ((2.24E-6 * POWER(125 - d.H_m, 3)) + (6.6E-7 * POWER(125 - d.H_m, 2)) + (0.0075 * (125 - d.H_m)) + 0.9305)
            WHEN d.HPP = 'Koman' AND d.Schedule = 'Average' THEN (0.000006 * POWER(103 - d.H_m, 3)) + (0.00007 * POWER(103 - d.H_m, 2)) + (0.0106 * (103 - d.H_m)) + 1.107
            WHEN d.HPP = 'Koman' AND d.Schedule = 'Economic' THEN (0.00023 * POWER(98 - d.H_m, 2)) + (0.01115 * (98 - d.H_m)) + 1.142
            WHEN d.HPP = 'Vau Deje' AND d.Schedule = 'Average' THEN (0.0013 * POWER(55 - d.H_m, 2)) + (0.044 * (55 - d.H_m)) + 2.16
            WHEN d.HPP = 'Vau Deje' AND d.Schedule = 'Economic' THEN (0.00225 * POWER(55 - d.H_m, 2)) + (0.033 * (55 - d.H_m)) + 2.13
        END, 3) AS Flow_m3_per_sec_per_MW
    FROM HPP_Data d
    JOIN Min_H_m m ON d.HPP = m.HPP
)
SELECT 
    l.HPP,
    l.Schedule,
    l.H_m,
    l.Max_Load_Allowed_MW,
    l.Load_MW,
    f.Flow_m3_per_sec_per_MW,
    ROUND(f.Flow_m3_per_sec_per_MW * 3.6, 2) AS Flow_m3_per_kWh,
    ROUND(102 / (l.Min_H_m * f.Flow_m3_per_sec_per_MW), 3) AS Efficiency
FROM Load_Calculations l
JOIN Flow_Calculations f ON l.HPP = f.HPP AND l.Schedule = f.Schedule;
GO
/****** Object:  View [dbo].[vw_LIMITS_OF_USE]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [dbo].[vw_LIMITS_OF_USE] AS
WITH Reservoir_Data AS (
    SELECT 'Fierza' AS HPP, 296 AS Set_Up_Level
    UNION ALL
    SELECT 'Koman', 174
    UNION ALL
    SELECT 'Vau Deje', 74.20
),
Inflows_Calculations AS (
    SELECT 
        HPP,
        Set_Up_Level,
        CASE 
            WHEN HPP = 'Fierza' THEN (0.00021 * POWER(Set_Up_Level - 240, 3)) + (0.0164 * POWER(Set_Up_Level - 240, 2)) + (1.11 * (Set_Up_Level - 240)) + 54
            WHEN HPP = 'Koman' THEN (0.001 * POWER(Set_Up_Level - 160, 2)) + (0.62 * (Set_Up_Level - 160)) + 27
            WHEN HPP = 'Vau Deje' THEN (-0.003 * POWER(Set_Up_Level - 59, 2)) + (1.299 * (Set_Up_Level - 59)) + 49.7
        END AS Inflows_m3_per_sec_per_1cm_ore
    FROM Reservoir_Data
),
Volume_Calculations AS (
    SELECT 
        HPP,
        Set_Up_Level,
        CASE 
            WHEN HPP = 'Fierza' THEN (0.00009 * POWER(Set_Up_Level - 240, 3)) + (0.004 * POWER(Set_Up_Level - 240, 2)) + (0.47 * (Set_Up_Level - 240)) + 18.8
            WHEN HPP = 'Koman' THEN (0.0005 * POWER(Set_Up_Level - 149, 2)) + (0.196 * (Set_Up_Level - 149)) + 7.7
            WHEN HPP = 'Vau Deje' THEN (0.00038 * POWER(Set_Up_Level - 59, 3)) - (0.0142 * POWER(Set_Up_Level - 59, 2)) + (0.59 * (Set_Up_Level - 59)) + 17.7
        END AS Volume_mil_m3_per_1m
    FROM Reservoir_Data
),
Lake_Volume_Calculations AS (
    SELECT 
        HPP,
        Set_Up_Level,
        CASE 
            WHEN HPP = 'Fierza' THEN (0.0000215 * POWER(Set_Up_Level - 239, 4)) + (0.00139 * POWER(Set_Up_Level - 239, 3)) + (0.231 * POWER(Set_Up_Level - 239, 2)) + (18.5 * (Set_Up_Level - 239)) + 404
            WHEN HPP = 'Koman' THEN (0.1097 * POWER(Set_Up_Level - 150, 2)) + (7.79 * (Set_Up_Level - 150)) + 240
            WHEN HPP = 'Vau Deje' THEN (-0.00036 * POWER(Set_Up_Level - 39, 3)) + (0.255 * POWER(Set_Up_Level - 39, 2)) + (8.37 * (Set_Up_Level - 39)) + 40
        END AS Lake_Volume_mil_m3
    FROM Reservoir_Data
),
Usage_Volume_Calculations AS (
    SELECT 
        HPP,
        Lake_Volume_mil_m3,
        CASE 
            WHEN HPP = 'Fierza' THEN Lake_Volume_mil_m3 - 367.9
            WHEN HPP = 'Koman' THEN NULL
            WHEN HPP = 'Vau Deje' THEN NULL
        END AS Usage_Volume_mil_m3
    FROM Lake_Volume_Calculations
),
Energy_Reserve_Calculations AS (
    SELECT 
        HPP,
        Set_Up_Level,
        CASE 
            WHEN HPP = 'Fierza' THEN (0.000019 * POWER(Set_Up_Level - 239, 4)) + (0.000768 * POWER(Set_Up_Level - 239, 3)) + (0.153 * POWER(Set_Up_Level - 239, 2)) + (9.339 * (Set_Up_Level - 239)) + 18.1
            WHEN HPP = 'Koman' THEN NULL
            WHEN HPP = 'Vau Deje' THEN NULL
        END AS Energy_Reserve_GWh
    FROM Reservoir_Data
),
Free_Volume_Calculations AS (
    SELECT 
        HPP,
        Lake_Volume_mil_m3,
        CASE 
            WHEN HPP = 'Fierza' THEN 2693.4 - Lake_Volume_mil_m3
            WHEN HPP = 'Koman' THEN NULL
            WHEN HPP = 'Vau Deje' THEN NULL
        END AS Free_Volume_mil_m3
    FROM Lake_Volume_Calculations
)
SELECT 
    i.HPP,
    i.Set_Up_Level,
    i.Inflows_m3_per_sec_per_1cm_ore,
    v.Volume_mil_m3_per_1m,
    l.Lake_Volume_mil_m3,
    u.Usage_Volume_mil_m3,
    e.Energy_Reserve_GWh,
    f.Free_Volume_mil_m3
FROM Inflows_Calculations i
JOIN Volume_Calculations v ON i.HPP = v.HPP
JOIN Lake_Volume_Calculations l ON i.HPP = l.HPP
LEFT JOIN Usage_Volume_Calculations u ON i.HPP = u.HPP
LEFT JOIN Energy_Reserve_Calculations e ON i.HPP = e.HPP
LEFT JOIN Free_Volume_Calculations f ON i.HPP = f.HPP;
GO
/****** Object:  Table [dbo].[first_Scenario_Input_Hydro_Optimal]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[first_Scenario_Input_Hydro_Optimal](
	[Nr] [int] NULL,
	[DEMAND_FSHU] [int] NULL,
	[Min_Generation] [int] NULL,
	[Max_Generation] [int] NULL,
	[Day_Ahead_Price] [decimal](10, 2) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[first_Scenario_Output_Hydro_Optimal]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[first_Scenario_Output_Hydro_Optimal](
	[Nr] [int] NULL,
	[Import] [int] NULL,
	[Export] [int] NULL,
	[Qyrsaqe] [int] NULL,
	[Kravasta] [int] NULL,
	[Fierza] [int] NULL,
	[Koman] [int] NULL,
	[Vau_Dejes] [int] NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Second_Scenario_Input_Hydro_Surpluses]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Second_Scenario_Input_Hydro_Surpluses](
	[Nr] [int] IDENTITY(1,1) NOT NULL,
	[DEMAND_FSHU] [int] NULL,
	[Mandatory_Generation_For_Drin_Cascade] [int] NULL,
	[Max_Generation] [int] NULL,
	[Day_Ahead_Price] [decimal](10, 2) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Second_Scenario_Output_Hydro_Surpluses]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Second_Scenario_Output_Hydro_Surpluses](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[Import] [int] NULL,
	[Export] [int] NULL,
	[Qyrsaqe] [int] NULL,
	[Kravasta] [int] NULL,
	[Fierza] [int] NULL,
	[Koman] [int] NULL,
	[Vau_Dejes] [int] NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_FTL_kesh]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_FTL_kesh](
	[data] [date] NULL,
	[time] [time](7) NULL,
	[njesia] [varchar](50) NULL,
	[KESH_per_konsumatoret_tarifore_te_OSHEE] [decimal](18, 0) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_FTL_kesh_ashta]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_FTL_kesh_ashta](
	[data] [date] NULL,
	[time] [time](7) NULL,
	[njesia] [varchar](50) NULL,
	[KESH_per_konsumatoret_tarifore_te_OSHEE] [decimal](18, 0) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_Kesh_DB_customers]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_Kesh_DB_customers](
	[cust_id] [int] IDENTITY(1,1) NOT NULL,
	[cust_firstname] [varchar](50) NOT NULL,
	[cust_lastname] [varchar](50) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[cust_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_Kesh_DB_inventory]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_Kesh_DB_inventory](
	[inv_id] [int] IDENTITY(1,1) NOT NULL,
	[item_id] [varchar](10) NOT NULL,
	[quantity] [int] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[inv_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_Kesh_DB_staff]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_Kesh_DB_staff](
	[staff_id] [varchar](20) NOT NULL,
	[first_name] [varchar](50) NOT NULL,
	[last_name] [varchar](50) NOT NULL,
	[position] [varchar](100) NOT NULL,
	[hourly_rate] [decimal](5, 2) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[staff_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_neomesir_valbona]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_neomesir_valbona](
	[timestamp] [datetime] NOT NULL,
	[Pressure Avg (hPa)] [decimal](10, 2) NULL,
	[Temperature Smp (°C)] [decimal](10, 3) NULL,
	[Total Precipitation Tot (mm)] [decimal](10, 2) NULL,
	[Wind direction Smp (°)] [decimal](10, 1) NULL,
	[Wind speed Avg (m/s)] [decimal](10, 3) NULL,
	[Wind speed Smp (m/s)] [decimal](10, 3) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_OST]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_OST](
	[data] [date] NULL,
	[time] [time](7) NULL,
	[HEC Ashta1-T1/020] [decimal](10, 2) NULL,
	[HEC ASHTA2-T1/035] [decimal](10, 2) NULL,
	[HEC Fierze-T1/487] [decimal](10, 2) NULL,
	[HEC Fierze-T2/477] [decimal](10, 2) NULL,
	[HEC Fierze-T3/484] [decimal](10, 2) NULL,
	[HEC Fierze-T4/489] [decimal](10, 2) NULL,
	[HEC Koman-T1/475] [decimal](10, 2) NULL,
	[HEC Koman-T2/479] [decimal](10, 2) NULL,
	[HEC Koman-T3/481] [decimal](10, 2) NULL,
	[HEC Koman-T4/482] [decimal](10, 2) NULL,
	[HEC Vau Dejes-T1/486] [decimal](10, 2) NULL,
	[HEC Vau Dejes-T2/490] [decimal](10, 2) NULL,
	[HEC Vau Dejes-T3/491] [decimal](10, 2) NULL,
	[HEC Vau Dejes-T4/492] [decimal](10, 2) NULL,
	[HEC Vau Dejes-T5/495] [decimal](10, 2) NULL,
	[Karavasta Solar-T1/333] [decimal](10, 2) NULL,
	[Karavasta Solar-T2/335] [decimal](10, 2) NULL,
	[TEC VLORA-T1/459] [decimal](10, 2) NULL,
	[njesia] [varchar](50) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_polaris_fierze]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_polaris_fierze](
	[Date] [datetime] NOT NULL,
	[Fierze Meteo - 1 h radiation accumulation - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - 1 hour rain accumulation - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - 24 h ratiation accumulation - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - 24H rain accumulation - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Air temperature - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Battery voltage - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Charging current - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Discharge current (consumption) - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Relative humidity - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Snow level - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Solar radiation - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Wind direction - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Wind Speed - Raw] [decimal](10, 5) NOT NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_polaris_Koman]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_polaris_Koman](
	[Date] [datetime] NOT NULL,
	[Koman Bjefi Poshtem Hydro - Battery voltage - Raw] [decimal](10, 5) NOT NULL,
	[Koman Bjefi Poshtem Hydro - Water level - Raw] [decimal](10, 5) NOT NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_polaris_teGjitha]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_polaris_teGjitha](
	[Date] [datetime] NOT NULL,
	[Vau Dejes Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Kukes Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Okshtun Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Koman Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Dragobi Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Fierze Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Lin Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Theth Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Peshkopi Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Zogaj Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Puke Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL,
	[Shishtavec Meteo - Percipitation intencity - Raw] [decimal](10, 5) NOT NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staging_PSME]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staging_PSME](
	[time] [time](7) NULL,
	[KOMAN_AG1_023] [decimal](18, 0) NULL,
	[KOMAN_AG2_024] [decimal](18, 0) NULL,
	[KOMAN_AG3_025] [decimal](18, 0) NULL,
	[KOMAN_AG4_025] [decimal](18, 0) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Third_Scenario_Input_Hydro_Deficiency]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Third_Scenario_Input_Hydro_Deficiency](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DEMAND_FSHU] [int] NULL,
	[Min_Generation] [int] NULL,
	[Max_Generation] [int] NULL,
	[Day_Ahead_Price] [decimal](10, 2) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Third_Scenario_Output_Hydro_Deficiency]    Script Date: 6/12/2025 1:27:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Third_Scenario_Output_Hydro_Deficiency](
	[RowID] [int] NULL,
	[Import] [int] NULL,
	[Export] [int] NULL,
	[Qyrsaqe] [int] NULL,
	[Kravasta] [int] NULL,
	[Fierza] [int] NULL,
	[Koman] [int] NULL,
	[Vau_Dejes] [int] NULL
) ON [PRIMARY]
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (1, 212, 60, 1150, CAST(55.94 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (2, 145, 60, 1150, CAST(41.08 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (3, 115, 60, 1150, CAST(40.76 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (4, 107, 60, 1150, CAST(38.22 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (5, 113, 60, 1150, CAST(40.53 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (6, 153, 70, 1150, CAST(47.13 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (7, 329, 80, 1150, CAST(57.82 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (8, 568, 150, 1150, CAST(58.61 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (9, 619, 150, 1150, CAST(53.23 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (10, 618, 150, 1150, CAST(47.01 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (11, 577, 150, 1150, CAST(44.88 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (12, 562, 150, 1150, CAST(42.63 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (13, 560, 150, 1150, CAST(38.43 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (14, 597, 150, 1150, CAST(32.44 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (15, 617, 150, 1150, CAST(39.03 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (16, 618, 150, 1150, CAST(50.00 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (17, 642, 150, 1150, CAST(64.98 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (18, 719, 150, 1150, CAST(73.41 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (19, 790, 150, 1150, CAST(82.41 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (20, 774, 150, 1150, CAST(91.09 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (21, 731, 150, 1150, CAST(83.45 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (22, 639, 150, 1150, CAST(73.07 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (23, 494, 150, 1150, CAST(72.37 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Input_Hydro_Optimal] ([Nr], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (24, 338, 150, 1150, CAST(67.10 AS Decimal(10, 2)))
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (1, 152, NULL, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (2, 85, NULL, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (3, 55, NULL, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (4, 47, NULL, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (5, 53, NULL, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (6, 83, NULL, 0, 0, 0, 0, 70)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (7, 249, NULL, 0, 0, 0, 0, 80)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (8, 418, NULL, 0, 0, 0, 100, 50)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (9, 469, NULL, 5, 0, 0, 100, 45)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (10, 468, NULL, 5, 100, 0, 0, 45)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (11, 427, NULL, 5, 100, 0, 0, 45)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (12, 412, NULL, 5, 100, 0, 0, 45)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (13, 410, NULL, 5, 100, 0, 0, 45)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (14, 447, NULL, 5, 100, 0, 0, 45)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (15, 467, NULL, 5, 100, 0, 0, 45)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (16, 0, NULL, 5, 100, 200, 250, 63)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (17, 0, NULL, 0, 0, 200, 380, 62)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (18, 0, NULL, 0, 0, 200, 450, 69)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (19, 0, 360, 0, 0, 200, 520, 70)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (20, 0, 376, 0, 0, 200, 520, 54)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (21, 0, 419, 0, 0, 200, 480, 51)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (22, 0, NULL, 0, 0, 200, 380, 59)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (23, 0, NULL, 0, 0, 200, 220, 74)
GO
INSERT [dbo].[first_Scenario_Output_Hydro_Optimal] ([Nr], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (24, 0, NULL, 0, 0, 200, 138, 0)
GO
SET IDENTITY_INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ON 
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (1, 212, 800, 1150, CAST(55.94 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (2, 145, 800, 1150, CAST(41.08 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (3, 115, 800, 1150, CAST(40.76 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (4, 107, 800, 1150, CAST(38.22 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (5, 113, 800, 1150, CAST(40.53 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (6, 153, 800, 1150, CAST(47.13 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (7, 329, 800, 1150, CAST(57.82 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (8, 568, 800, 1150, CAST(58.61 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (9, 619, 800, 1150, CAST(53.23 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (10, 618, 800, 1150, CAST(47.01 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (11, 577, 800, 1150, CAST(44.88 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (12, 562, 800, 1150, CAST(42.63 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (13, 560, 800, 1150, CAST(38.43 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (14, 597, 800, 1150, CAST(32.44 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (15, 617, 800, 1150, CAST(39.03 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (16, 618, 800, 1150, CAST(50.00 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (17, 642, 800, 1150, CAST(64.98 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (18, 719, 800, 1150, CAST(73.41 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (19, 790, 800, 1150, CAST(82.41 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (20, 774, 800, 1150, CAST(91.09 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (21, 731, 800, 1150, CAST(83.45 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (22, 639, 800, 1150, CAST(73.07 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (23, 494, 800, 1150, CAST(72.37 AS Decimal(10, 2)))
GO
INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] ([Nr], [DEMAND_FSHU], [Mandatory_Generation_For_Drin_Cascade], [Max_Generation], [Day_Ahead_Price]) VALUES (24, 338, 800, 1150, CAST(67.10 AS Decimal(10, 2)))
GO
SET IDENTITY_INSERT [dbo].[Second_Scenario_Input_Hydro_Surpluses] OFF
GO
SET IDENTITY_INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ON 
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (1, 0, 588, 0, 0, 0, 152, 60)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (2, 0, 655, 0, 0, 0, 145, 0)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (3, 0, 685, 0, 0, 0, 115, 0)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (4, 0, 693, 0, 0, 0, 107, 0)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (5, 0, 687, 0, 0, 0, 113, 0)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (6, 0, 647, 0, 0, 0, 153, 0)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (7, 0, 471, 0, 0, 0, 249, 80)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (8, 0, 232, 0, 0, 0, 488, 80)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (9, 0, 186, 5, 0, 0, 550, 64)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (10, 0, 287, 5, 100, 0, 450, 63)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (11, 0, 328, 5, 100, 0, 409, 63)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (12, 0, 343, 5, 100, 0, 412, 45)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (13, 0, 345, 5, 100, 0, 410, 45)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (14, 0, 308, 5, 100, 0, 447, 45)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (15, 0, 288, 5, 100, 0, 432, 80)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (16, 0, 287, 5, 100, 200, 250, 63)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (17, 0, 158, 0, 0, 200, 380, 62)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (18, 0, 81, 0, 0, 200, 450, 69)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (19, 0, 10, 0, 0, 200, 520, 70)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (20, 0, 26, 0, 0, 200, 520, 54)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (21, 0, 69, 0, 0, 200, 480, 51)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (22, 0, 161, 0, 0, 200, 380, 59)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (23, 0, 306, 0, 0, 200, 220, 74)
GO
INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] ([ID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (24, 0, 462, 0, 0, 200, 138, 0)
GO
SET IDENTITY_INSERT [dbo].[Second_Scenario_Output_Hydro_Surpluses] OFF
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(388 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(352 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(337 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(332 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(347 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(420 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(567 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(675 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(656 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(625 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(567 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(544 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(545 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(558 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(653 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(685 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(709 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(807 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(813 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(781 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(741 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(680 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(569 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(479 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(383 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(339 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(324 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(320 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(330 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(383 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(509 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(648 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(683 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(676 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(643 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(631 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(626 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(656 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(683 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(706 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(745 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(810 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(797 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(770 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(744 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(662 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(547 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(454 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(434 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(376 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(359 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(358 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(377 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(416 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(523 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(632 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(674 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(650 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(652 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(644 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(641 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(642 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(645 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(655 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(728 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(833 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(841 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(809 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(763 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(670 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(566 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(465 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(410 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(386 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(371 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(367 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(381 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(444 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(606 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(740 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(711 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(671 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(624 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(610 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(605 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(651 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(690 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(714 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(757 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(851 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(843 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(859 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(829 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(748 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(642 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(531 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(417 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(380 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(373 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(373 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(374 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(441 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(595 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(746 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(717 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(671 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(637 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(624 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(614 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(642 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(665 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(695 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(771 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(891 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(893 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(875 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(849 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(759 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(621 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(506 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(432 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(387 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(370 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(371 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(387 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(456 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(592 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(734 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(715 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(656 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(618 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(604 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(621 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(660 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(697 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(731 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(797 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(919 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(925 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(913 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(884 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(794 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(662 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(547 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(447 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(406 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(383 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(380 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(388 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(447 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(610 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(763 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(737 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(687 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(652 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(634 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(634 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(682 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(715 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(758 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(835 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(940 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(947 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(928 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(898 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(820 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(704 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(566 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(456 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(398 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(385 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(387 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(390 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(464 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(626 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(787 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(765 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(715 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(666 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(640 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(644 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(681 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(721 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(762 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(838 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(955 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(967 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(952 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(918 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(840 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(705 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(561 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(473 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(413 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(397 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(393 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(403 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(469 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(595 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(731 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(761 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(735 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(692 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(679 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(677 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(730 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(745 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(781 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(867 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(984 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(974 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(952 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(928 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(843 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(705 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(573 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(391 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(359 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(344 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(323 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(354 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(427 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(585 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(717 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(682 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(644 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(570 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(552 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(548 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(563 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(660 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(692 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(743 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(852 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(848 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(816 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(776 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(689 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(576 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-01' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(466 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'01:00:00' AS Time), N' MWh ', CAST(388 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'02:00:00' AS Time), N' MWh ', CAST(346 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'03:00:00' AS Time), N' MWh ', CAST(327 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'04:00:00' AS Time), N' MWh ', CAST(322 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'05:00:00' AS Time), N' MWh ', CAST(332 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'06:00:00' AS Time), N' MWh ', CAST(395 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'07:00:00' AS Time), N' MWh ', CAST(525 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'08:00:00' AS Time), N' MWh ', CAST(655 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'09:00:00' AS Time), N' MWh ', CAST(690 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'10:00:00' AS Time), N' MWh ', CAST(683 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'11:00:00' AS Time), N' MWh ', CAST(653 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'12:00:00' AS Time), N' MWh ', CAST(639 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'13:00:00' AS Time), N' MWh ', CAST(634 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'14:00:00' AS Time), N' MWh ', CAST(663 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'15:00:00' AS Time), N' MWh ', CAST(690 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'16:00:00' AS Time), N' MWh ', CAST(713 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'17:00:00' AS Time), N' MWh ', CAST(767 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'18:00:00' AS Time), N' MWh ', CAST(844 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'19:00:00' AS Time), N' MWh ', CAST(831 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'20:00:00' AS Time), N' MWh ', CAST(804 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'21:00:00' AS Time), N' MWh ', CAST(763 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'22:00:00' AS Time), N' MWh ', CAST(681 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'23:00:00' AS Time), N' MWh ', CAST(571 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-02' AS Date), CAST(N'00:00:00' AS Time), N' MWh ', CAST(464 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'01:00:00' AS Time), N'MWh', CAST(441 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'02:00:00' AS Time), N'MWh', CAST(392 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'03:00:00' AS Time), N'MWh', CAST(369 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'04:00:00' AS Time), N'MWh', CAST(359 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'05:00:00' AS Time), N'MWh', CAST(378 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'06:00:00' AS Time), N'MWh', CAST(417 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'07:00:00' AS Time), N'MWh', CAST(524 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'08:00:00' AS Time), N'MWh', CAST(633 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'09:00:00' AS Time), N'MWh', CAST(675 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'10:00:00' AS Time), N'MWh', CAST(651 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'11:00:00' AS Time), N'MWh', CAST(641 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'12:00:00' AS Time), N'MWh', CAST(633 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'13:00:00' AS Time), N'MWh', CAST(642 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'14:00:00' AS Time), N'MWh', CAST(649 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'15:00:00' AS Time), N'MWh', CAST(660 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'16:00:00' AS Time), N'MWh', CAST(670 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'17:00:00' AS Time), N'MWh', CAST(743 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'18:00:00' AS Time), N'MWh', CAST(867 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'19:00:00' AS Time), N'MWh', CAST(875 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'20:00:00' AS Time), N'MWh', CAST(840 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'21:00:00' AS Time), N'MWh', CAST(785 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'22:00:00' AS Time), N'MWh', CAST(692 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'23:00:00' AS Time), N'MWh', CAST(573 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-03' AS Date), CAST(N'00:00:00' AS Time), N'MWh', CAST(466 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'01:00:00' AS Time), N'MWh', CAST(412 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'02:00:00' AS Time), N'MWh', CAST(376 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'03:00:00' AS Time), N'MWh', CAST(361 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'04:00:00' AS Time), N'MWh', CAST(357 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'05:00:00' AS Time), N'MWh', CAST(371 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'06:00:00' AS Time), N'MWh', CAST(446 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'07:00:00' AS Time), N'MWh', CAST(608 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'08:00:00' AS Time), N'MWh', CAST(742 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'09:00:00' AS Time), N'MWh', CAST(715 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'10:00:00' AS Time), N'MWh', CAST(673 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'11:00:00' AS Time), N'MWh', CAST(626 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'12:00:00' AS Time), N'MWh', CAST(612 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'13:00:00' AS Time), N'MWh', CAST(607 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'14:00:00' AS Time), N'MWh', CAST(653 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'15:00:00' AS Time), N'MWh', CAST(694 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'16:00:00' AS Time), N'MWh', CAST(721 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'17:00:00' AS Time), N'MWh', CAST(772 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'18:00:00' AS Time), N'MWh', CAST(885 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'19:00:00' AS Time), N'MWh', CAST(877 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'20:00:00' AS Time), N'MWh', CAST(840 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'21:00:00' AS Time), N'MWh', CAST(801 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'22:00:00' AS Time), N'MWh', CAST(710 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'23:00:00' AS Time), N'MWh', CAST(596 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-04' AS Date), CAST(N'00:00:00' AS Time), N'MWh', CAST(483 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'01:00:00' AS Time), N'MWh', CAST(419 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'02:00:00' AS Time), N'MWh', CAST(382 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'03:00:00' AS Time), N'MWh', CAST(365 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'04:00:00' AS Time), N'MWh', CAST(361 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'05:00:00' AS Time), N'MWh', CAST(376 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'06:00:00' AS Time), N'MWh', CAST(445 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'07:00:00' AS Time), N'MWh', CAST(605 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'08:00:00' AS Time), N'MWh', CAST(756 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'09:00:00' AS Time), N'MWh', CAST(732 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'10:00:00' AS Time), N'MWh', CAST(690 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'11:00:00' AS Time), N'MWh', CAST(644 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'12:00:00' AS Time), N'MWh', CAST(631 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'13:00:00' AS Time), N'MWh', CAST(624 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'14:00:00' AS Time), N'MWh', CAST(663 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'15:00:00' AS Time), N'MWh', CAST(696 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'16:00:00' AS Time), N'MWh', CAST(723 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'17:00:00' AS Time), N'MWh', CAST(776 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'18:00:00' AS Time), N'MWh', CAST(891 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'19:00:00' AS Time), N'MWh', CAST(879 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'20:00:00' AS Time), N'MWh', CAST(849 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'21:00:00' AS Time), N'MWh', CAST(810 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'22:00:00' AS Time), N'MWh', CAST(723 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'23:00:00' AS Time), N'MWh', CAST(615 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-05' AS Date), CAST(N'00:00:00' AS Time), N'MWh', CAST(507 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'01:00:00' AS Time), N'MWh', CAST(439 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'02:00:00' AS Time), N'MWh', CAST(394 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'03:00:00' AS Time), N'MWh', CAST(377 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'04:00:00' AS Time), N'MWh', CAST(373 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'05:00:00' AS Time), N'MWh', CAST(389 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'06:00:00' AS Time), N'MWh', CAST(458 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'07:00:00' AS Time), N'MWh', CAST(616 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'08:00:00' AS Time), N'MWh', CAST(765 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'09:00:00' AS Time), N'MWh', CAST(737 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'10:00:00' AS Time), N'MWh', CAST(674 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'11:00:00' AS Time), N'MWh', CAST(629 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'12:00:00' AS Time), N'MWh', CAST(614 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'13:00:00' AS Time), N'MWh', CAST(611 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'14:00:00' AS Time), N'MWh', CAST(644 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'15:00:00' AS Time), N'MWh', CAST(682 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'16:00:00' AS Time), N'MWh', CAST(725 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'17:00:00' AS Time), N'MWh', CAST(810 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'18:00:00' AS Time), N'MWh', CAST(929 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'19:00:00' AS Time), N'MWh', CAST(925 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'20:00:00' AS Time), N'MWh', CAST(898 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'21:00:00' AS Time), N'MWh', CAST(865 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'22:00:00' AS Time), N'MWh', CAST(775 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'23:00:00' AS Time), N'MWh', CAST(646 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-06' AS Date), CAST(N'00:00:00' AS Time), N'MWh', CAST(529 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'01:00:00' AS Time), N'MWh', CAST(450 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'02:00:00' AS Time), N'MWh', CAST(408 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'03:00:00' AS Time), N'MWh', CAST(390 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'04:00:00' AS Time), N'MWh', CAST(387 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'05:00:00' AS Time), N'MWh', CAST(398 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'06:00:00' AS Time), N'MWh', CAST(475 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'07:00:00' AS Time), N'MWh', CAST(636 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'08:00:00' AS Time), N'MWh', CAST(797 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'09:00:00' AS Time), N'MWh', CAST(765 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'10:00:00' AS Time), N'MWh', CAST(697 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'11:00:00' AS Time), N'MWh', CAST(655 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'12:00:00' AS Time), N'MWh', CAST(636 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'13:00:00' AS Time), N'MWh', CAST(636 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'14:00:00' AS Time), N'MWh', CAST(669 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'15:00:00' AS Time), N'MWh', CAST(709 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'16:00:00' AS Time), N'MWh', CAST(747 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'17:00:00' AS Time), N'MWh', CAST(819 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'18:00:00' AS Time), N'MWh', CAST(950 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'19:00:00' AS Time), N'MWh', CAST(952 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'20:00:00' AS Time), N'MWh', CAST(938 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'21:00:00' AS Time), N'MWh', CAST(898 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'22:00:00' AS Time), N'MWh', CAST(801 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'23:00:00' AS Time), N'MWh', CAST(674 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-07' AS Date), CAST(N'00:00:00' AS Time), N'MWh', CAST(548 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'01:00:00' AS Time), N'MWh', CAST(463 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'02:00:00' AS Time), N'MWh', CAST(416 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'03:00:00' AS Time), N'MWh', CAST(396 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'04:00:00' AS Time), N'MWh', CAST(391 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'05:00:00' AS Time), N'MWh', CAST(405 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'06:00:00' AS Time), N'MWh', CAST(480 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'07:00:00' AS Time), N'MWh', CAST(648 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'08:00:00' AS Time), N'MWh', CAST(820 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'09:00:00' AS Time), N'MWh', CAST(787 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'10:00:00' AS Time), N'MWh', CAST(722 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'11:00:00' AS Time), N'MWh', CAST(676 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'12:00:00' AS Time), N'MWh', CAST(655 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'13:00:00' AS Time), N'MWh', CAST(662 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'14:00:00' AS Time), N'MWh', CAST(697 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'15:00:00' AS Time), N'MWh', CAST(743 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'16:00:00' AS Time), N'MWh', CAST(788 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'17:00:00' AS Time), N'MWh', CAST(864 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'18:00:00' AS Time), N'MWh', CAST(998 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'19:00:00' AS Time), N'MWh', CAST(1008 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'20:00:00' AS Time), N'MWh', CAST(993 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'21:00:00' AS Time), N'MWh', CAST(959 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'22:00:00' AS Time), N'MWh', CAST(857 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'23:00:00' AS Time), N'MWh', CAST(717 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-08' AS Date), CAST(N'00:00:00' AS Time), N'MWh', CAST(573 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'01:00:00' AS Time), N'MWh', CAST(483 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'02:00:00' AS Time), N'MWh', CAST(435 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'03:00:00' AS Time), N'MWh', CAST(415 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'04:00:00' AS Time), N'MWh', CAST(409 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'05:00:00' AS Time), N'MWh', CAST(422 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'06:00:00' AS Time), N'MWh', CAST(487 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'07:00:00' AS Time), N'MWh', CAST(610 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'08:00:00' AS Time), N'MWh', CAST(749 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'09:00:00' AS Time), N'MWh', CAST(790 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'10:00:00' AS Time), N'MWh', CAST(766 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'11:00:00' AS Time), N'MWh', CAST(723 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'12:00:00' AS Time), N'MWh', CAST(708 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'13:00:00' AS Time), N'MWh', CAST(710 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'14:00:00' AS Time), N'MWh', CAST(740 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'15:00:00' AS Time), N'MWh', CAST(756 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'16:00:00' AS Time), N'MWh', CAST(788 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'17:00:00' AS Time), N'MWh', CAST(861 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'18:00:00' AS Time), N'MWh', CAST(987 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'19:00:00' AS Time), N'MWh', CAST(982 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'20:00:00' AS Time), N'MWh', CAST(942 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'21:00:00' AS Time), N'MWh', CAST(897 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'22:00:00' AS Time), N'MWh', CAST(810 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'23:00:00' AS Time), N'MWh', CAST(687 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_FTL_kesh_ashta] ([data], [time], [njesia], [KESH_per_konsumatoret_tarifore_te_OSHEE]) VALUES (CAST(N'2024-12-09' AS Date), CAST(N'00:00:00' AS Time), N'MWh', CAST(550 AS Decimal(18, 0)))
GO
SET IDENTITY_INSERT [dbo].[staging_Kesh_DB_customers] ON 
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (1, N'John', N'Doe')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (2, N'Jane', N'Smith')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (3, N'Michael', N'Johnson')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (4, N'Emma', N'Williams')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (5, N'Sarah', N'Johnson')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (6, N'Michael', N'Brown')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (7, N'Jennifer', N'Miller')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (8, N'William', N'Davis')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (9, N'Elizabeth', N'Garcia')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (10, N'Daniel', N'Martinez')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (11, N'Sophia', N'Lopez')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (12, N'Matthew', N'Hernandez')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (13, N'Olivia', N'Gonzalez')
GO
INSERT [dbo].[staging_Kesh_DB_customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (14, N'David', N'Perez')
GO
SET IDENTITY_INSERT [dbo].[staging_Kesh_DB_customers] OFF
GO
SET IDENTITY_INSERT [dbo].[staging_Kesh_DB_inventory] ON 
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (1, N'ITEM001', 50)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (2, N'ITEM002', 30)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (3, N'ITEM003', 55)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (4, N'ITEM004', 40)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (5, N'ITEM005', 15)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (6, N'ITEM006', 25)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (7, N'ITEM007', 15)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (8, N'ITEM008', 30)
GO
INSERT [dbo].[staging_Kesh_DB_inventory] ([inv_id], [item_id], [quantity]) VALUES (9, N'ITEM009', 60)
GO
SET IDENTITY_INSERT [dbo].[staging_Kesh_DB_inventory] OFF
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF001', N'David', N'Johnson', N'Cook', CAST(15.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF002', N'Emily', N'Smith', N'Server', CAST(12.50 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF003', N'William', N'Lee', N'Cashier', CAST(11.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF004', N'Olivia', N'Brown', N'Manager', CAST(20.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF005', N'James', N'Miller', N'Chef', CAST(18.75 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF006', N'Ava', N'Rodriguez', N'Server', CAST(11.50 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF007', N'Noah', N'Lopez', N'Cook', CAST(16.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF008', N'Emma', N'Lee', N'Cashier', CAST(10.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF009', N'Elijah', N'Gonzalez', N'Chef', CAST(17.50 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_Kesh_DB_staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF010', N'Isabella', N'Perez', N'Manager', CAST(21.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T00:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.248 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(179.7 AS Decimal(10, 1)), CAST(0.291 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T00:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.011 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(175.4 AS Decimal(10, 1)), CAST(0.065 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T00:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.458 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(297.6 AS Decimal(10, 1)), CAST(0.376 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T00:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.346 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(297.4 AS Decimal(10, 1)), CAST(0.041 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T00:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.303 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(225.3 AS Decimal(10, 1)), CAST(0.053 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T00:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.303 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(341.5 AS Decimal(10, 1)), CAST(0.215 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T01:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.332 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(222.5 AS Decimal(10, 1)), CAST(0.379 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T01:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.474 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(141.7 AS Decimal(10, 1)), CAST(0.103 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T01:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.375 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(289.7 AS Decimal(10, 1)), CAST(0.019 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T01:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.362 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(89.0 AS Decimal(10, 1)), CAST(0.087 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T01:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.431 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(184.5 AS Decimal(10, 1)), CAST(0.109 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T01:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.346 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(278.4 AS Decimal(10, 1)), CAST(0.356 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T02:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.557 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(230.4 AS Decimal(10, 1)), CAST(0.017 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T02:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.388 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(279.1 AS Decimal(10, 1)), CAST(0.286 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T02:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.530 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(213.9 AS Decimal(10, 1)), CAST(0.081 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T02:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.375 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(316.9 AS Decimal(10, 1)), CAST(0.263 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T02:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.346 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(202.8 AS Decimal(10, 1)), CAST(0.212 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T02:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.263 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(6.9 AS Decimal(10, 1)), CAST(0.206 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T03:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.151 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(256.0 AS Decimal(10, 1)), CAST(0.195 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T03:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.033 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(335.3 AS Decimal(10, 1)), CAST(0.174 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T03:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.881 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(26.1 AS Decimal(10, 1)), CAST(0.048 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T03:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.151 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(330.9 AS Decimal(10, 1)), CAST(0.052 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T03:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.964 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(178.0 AS Decimal(10, 1)), CAST(0.006 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T03:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.740 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(178.1 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T04:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.766 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(178.2 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T04:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.515 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(325.2 AS Decimal(10, 1)), CAST(0.319 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T04:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.486 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(221.4 AS Decimal(10, 1)), CAST(0.067 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T04:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.344 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(327.7 AS Decimal(10, 1)), CAST(0.180 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T04:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.374 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(260.7 AS Decimal(10, 1)), CAST(0.004 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T04:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.387 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(277.0 AS Decimal(10, 1)), CAST(0.093 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T05:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.360 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(34.8 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T05:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.416 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(222.7 AS Decimal(10, 1)), CAST(0.124 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T05:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.387 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(13.2 AS Decimal(10, 1)), CAST(0.135 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T05:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.374 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(215.7 AS Decimal(10, 1)), CAST(0.204 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T05:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.416 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(280.6 AS Decimal(10, 1)), CAST(0.418 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T05:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.416 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(25.8 AS Decimal(10, 1)), CAST(0.325 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T06:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.571 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(278.1 AS Decimal(10, 1)), CAST(0.062 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T06:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.443 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(330.0 AS Decimal(10, 1)), CAST(0.108 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T06:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.486 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(218.8 AS Decimal(10, 1)), CAST(0.029 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T06:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.499 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(217.5 AS Decimal(10, 1)), CAST(0.146 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T06:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.486 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(22.1 AS Decimal(10, 1)), CAST(0.122 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T06:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.598 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(228.1 AS Decimal(10, 1)), CAST(0.054 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T07:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.542 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(339.2 AS Decimal(10, 1)), CAST(0.157 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T07:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.486 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(236.7 AS Decimal(10, 1)), CAST(0.050 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T07:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(321.9 AS Decimal(10, 1)), CAST(0.017 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T07:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.328 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(224.7 AS Decimal(10, 1)), CAST(0.061 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T07:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.374 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(224.6 AS Decimal(10, 1)), CAST(0.122 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T07:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.272 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(224.7 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T08:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.328 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(224.7 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T08:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.230 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(224.7 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T08:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.272 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(280.5 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T08:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.387 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(344.7 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T08:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.555 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(221.8 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T08:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.809 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(291.6 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T09:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.993 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(334.7 AS Decimal(10, 1)), CAST(0.223 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T09:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.164 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(234.4 AS Decimal(10, 1)), CAST(0.091 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T09:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.220 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(197.8 AS Decimal(10, 1)), CAST(0.244 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T09:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.388 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(303.8 AS Decimal(10, 1)), CAST(0.324 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T09:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.599 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(331.7 AS Decimal(10, 1)), CAST(0.050 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T09:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.741 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(268.9 AS Decimal(10, 1)), CAST(0.320 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T10:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.912 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(173.0 AS Decimal(10, 1)), CAST(0.346 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T10:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(2.166 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(236.6 AS Decimal(10, 1)), CAST(0.113 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T10:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(2.248 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(3.1 AS Decimal(10, 1)), CAST(0.480 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T10:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(2.502 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(187.3 AS Decimal(10, 1)), CAST(0.158 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T10:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(2.627 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(319.6 AS Decimal(10, 1)), CAST(0.017 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T10:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(2.742 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(210.8 AS Decimal(10, 1)), CAST(0.272 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T11:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.814 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(221.8 AS Decimal(10, 1)), CAST(0.326 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T11:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(3.025 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(172.4 AS Decimal(10, 1)), CAST(0.184 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T11:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(3.052 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(76.5 AS Decimal(10, 1)), CAST(0.510 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T11:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.151 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(103.7 AS Decimal(10, 1)), CAST(0.765 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T11:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.276 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.2 AS Decimal(10, 1)), CAST(0.495 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T11:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.250 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.2 AS Decimal(10, 1)), CAST(1.167 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T12:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.207 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(99.3 AS Decimal(10, 1)), CAST(1.638 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T12:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.180 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(104.0 AS Decimal(10, 1)), CAST(1.547 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T12:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.180 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(120.3 AS Decimal(10, 1)), CAST(1.512 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T12:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.180 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.6 AS Decimal(10, 1)), CAST(1.817 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T12:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.236 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(112.0 AS Decimal(10, 1)), CAST(1.503 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T12:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.108 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(135.1 AS Decimal(10, 1)), CAST(1.667 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T13:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.081 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.8 AS Decimal(10, 1)), CAST(1.505 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T13:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.065 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.5 AS Decimal(10, 1)), CAST(1.561 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T13:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.009 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(145.6 AS Decimal(10, 1)), CAST(1.203 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T13:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.969 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(182.1 AS Decimal(10, 1)), CAST(1.028 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T13:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.009 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(242.6 AS Decimal(10, 1)), CAST(0.714 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T13:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.009 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(150.8 AS Decimal(10, 1)), CAST(1.092 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T14:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.052 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(68.7 AS Decimal(10, 1)), CAST(0.881 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T14:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.151 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.1 AS Decimal(10, 1)), CAST(0.180 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T14:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.108 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(107.3 AS Decimal(10, 1)), CAST(0.498 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T14:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.095 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(201.4 AS Decimal(10, 1)), CAST(0.804 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T14:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.025 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(176.0 AS Decimal(10, 1)), CAST(0.921 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T14:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(3.009 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(189.3 AS Decimal(10, 1)), CAST(0.698 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T15:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.969 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.1 AS Decimal(10, 1)), CAST(0.594 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T15:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.913 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(203.6 AS Decimal(10, 1)), CAST(0.491 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T15:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.870 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(195.0 AS Decimal(10, 1)), CAST(0.354 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T15:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.798 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(96.3 AS Decimal(10, 1)), CAST(0.274 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T15:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.828 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(52.9 AS Decimal(10, 1)), CAST(0.074 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T15:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.857 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(38.7 AS Decimal(10, 1)), CAST(0.130 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T16:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.927 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(108.3 AS Decimal(10, 1)), CAST(0.131 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T16:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.702 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(118.6 AS Decimal(10, 1)), CAST(0.451 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T16:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.798 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(161.6 AS Decimal(10, 1)), CAST(0.718 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T16:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.716 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(186.5 AS Decimal(10, 1)), CAST(0.659 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T16:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.627 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(115.5 AS Decimal(10, 1)), CAST(0.984 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T16:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.558 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(173.2 AS Decimal(10, 1)), CAST(1.156 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T17:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.571 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(203.6 AS Decimal(10, 1)), CAST(0.820 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T17:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.558 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.7 AS Decimal(10, 1)), CAST(0.807 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T17:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.558 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(157.0 AS Decimal(10, 1)), CAST(1.033 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T17:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.473 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(119.0 AS Decimal(10, 1)), CAST(1.188 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T17:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.502 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(177.2 AS Decimal(10, 1)), CAST(0.943 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T17:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.502 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(153.6 AS Decimal(10, 1)), CAST(0.953 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T18:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.446 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(129.7 AS Decimal(10, 1)), CAST(1.226 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T18:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.403 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.4 AS Decimal(10, 1)), CAST(1.073 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T18:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.433 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(150.9 AS Decimal(10, 1)), CAST(0.990 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T18:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.417 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(147.5 AS Decimal(10, 1)), CAST(0.944 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T18:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.248 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(119.5 AS Decimal(10, 1)), CAST(1.095 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T18:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.304 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.3 AS Decimal(10, 1)), CAST(1.120 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T19:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.222 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.2 AS Decimal(10, 1)), CAST(0.762 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T19:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.262 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(121.9 AS Decimal(10, 1)), CAST(0.867 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T19:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(121.4 AS Decimal(10, 1)), CAST(1.129 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T19:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(163.3 AS Decimal(10, 1)), CAST(1.080 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T19:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.136 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.5 AS Decimal(10, 1)), CAST(0.712 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T19:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.109 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.7 AS Decimal(10, 1)), CAST(1.148 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T20:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.080 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.0 AS Decimal(10, 1)), CAST(1.045 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T20:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.939 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(134.9 AS Decimal(10, 1)), CAST(0.849 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T20:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.968 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(173.8 AS Decimal(10, 1)), CAST(0.458 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T20:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.011 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.9 AS Decimal(10, 1)), CAST(0.763 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T20:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.968 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(115.9 AS Decimal(10, 1)), CAST(0.897 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T20:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.896 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.1 AS Decimal(10, 1)), CAST(0.966 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T21:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.810 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(133.4 AS Decimal(10, 1)), CAST(1.326 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T21:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.725 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.3 AS Decimal(10, 1)), CAST(1.106 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T21:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.853 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(177.1 AS Decimal(10, 1)), CAST(1.132 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T21:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.669 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(132.5 AS Decimal(10, 1)), CAST(1.513 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T21:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.642 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(146.3 AS Decimal(10, 1)), CAST(1.403 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T21:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.629 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(169.0 AS Decimal(10, 1)), CAST(1.600 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T22:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.655 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(132.1 AS Decimal(10, 1)), CAST(1.479 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T22:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.530 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(152.0 AS Decimal(10, 1)), CAST(1.674 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T22:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(116.6 AS Decimal(10, 1)), CAST(1.265 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T22:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.725 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(139.6 AS Decimal(10, 1)), CAST(0.888 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T22:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.629 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(84.1 AS Decimal(10, 1)), CAST(0.625 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T22:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.655 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.5 AS Decimal(10, 1)), CAST(0.004 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T23:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.599 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.7 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T23:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.586 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(48.5 AS Decimal(10, 1)), CAST(0.097 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T23:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.655 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(175.8 AS Decimal(10, 1)), CAST(0.066 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T23:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.629 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(158.4 AS Decimal(10, 1)), CAST(0.578 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T23:40:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(1.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(175.0 AS Decimal(10, 1)), CAST(0.502 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-14T23:50:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(1.514 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(129.7 AS Decimal(10, 1)), CAST(0.388 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T00:00:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(1.487 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(147.0 AS Decimal(10, 1)), CAST(0.802 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T00:10:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(1.543 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(143.1 AS Decimal(10, 1)), CAST(1.196 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T00:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.501 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.5 AS Decimal(10, 1)), CAST(1.315 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T00:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.418 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.3 AS Decimal(10, 1)), CAST(1.608 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T00:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.319 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(152.5 AS Decimal(10, 1)), CAST(1.421 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T00:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.177 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(151.3 AS Decimal(10, 1)), CAST(1.616 AS Decimal(10, 3)), CAST(2.450 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T01:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.121 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(162.8 AS Decimal(10, 1)), CAST(1.440 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T01:10:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(1.020 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(155.5 AS Decimal(10, 1)), CAST(1.214 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T01:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.977 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(145.9 AS Decimal(10, 1)), CAST(1.293 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T01:30:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(1.007 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(153.8 AS Decimal(10, 1)), CAST(1.189 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T01:40:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.894 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(115.3 AS Decimal(10, 1)), CAST(1.444 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T01:50:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.822 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(148.4 AS Decimal(10, 1)), CAST(1.136 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T02:00:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.852 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(118.0 AS Decimal(10, 1)), CAST(1.078 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T02:10:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.782 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(147.0 AS Decimal(10, 1)), CAST(1.202 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T02:20:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.766 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(149.1 AS Decimal(10, 1)), CAST(0.852 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T02:30:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.782 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(150.8 AS Decimal(10, 1)), CAST(0.619 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T02:40:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.908 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.0 AS Decimal(10, 1)), CAST(0.613 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T02:50:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.865 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(70.1 AS Decimal(10, 1)), CAST(1.961 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T03:00:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.796 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.4 AS Decimal(10, 1)), CAST(1.447 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T03:10:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.753 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.6 AS Decimal(10, 1)), CAST(1.960 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T03:20:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.726 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(157.9 AS Decimal(10, 1)), CAST(1.695 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T03:30:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.766 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(202.2 AS Decimal(10, 1)), CAST(1.257 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T03:40:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.697 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.2 AS Decimal(10, 1)), CAST(1.519 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T03:50:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.740 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(173.9 AS Decimal(10, 1)), CAST(1.137 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T04:00:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.782 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(120.7 AS Decimal(10, 1)), CAST(1.000 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T04:10:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.726 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(133.3 AS Decimal(10, 1)), CAST(1.468 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T04:20:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.852 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(156.0 AS Decimal(10, 1)), CAST(0.768 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T04:30:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.753 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(153.2 AS Decimal(10, 1)), CAST(0.949 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T04:40:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(0.822 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(154.8 AS Decimal(10, 1)), CAST(0.734 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T04:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.726 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.7 AS Decimal(10, 1)), CAST(0.763 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T05:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.782 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(170.8 AS Decimal(10, 1)), CAST(1.059 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T05:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.641 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(132.5 AS Decimal(10, 1)), CAST(1.139 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T05:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.697 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.5 AS Decimal(10, 1)), CAST(0.568 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T05:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.697 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(134.6 AS Decimal(10, 1)), CAST(1.410 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T05:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.654 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(148.1 AS Decimal(10, 1)), CAST(1.517 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T05:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.598 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(136.5 AS Decimal(10, 1)), CAST(1.392 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T06:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.473 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(94.5 AS Decimal(10, 1)), CAST(1.485 AS Decimal(10, 3)), CAST(2.352 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T06:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.443 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(157.9 AS Decimal(10, 1)), CAST(1.566 AS Decimal(10, 3)), CAST(2.450 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T06:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.459 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(192.5 AS Decimal(10, 1)), CAST(1.531 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T06:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.443 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(114.4 AS Decimal(10, 1)), CAST(1.246 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T06:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.486 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(131.8 AS Decimal(10, 1)), CAST(1.124 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T06:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.585 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.3 AS Decimal(10, 1)), CAST(0.759 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T07:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.542 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.3 AS Decimal(10, 1)), CAST(1.192 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T07:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.627 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.8 AS Decimal(10, 1)), CAST(0.935 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T07:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.654 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(151.2 AS Decimal(10, 1)), CAST(0.886 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T07:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.683 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(105.0 AS Decimal(10, 1)), CAST(0.923 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T07:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.753 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(230.9 AS Decimal(10, 1)), CAST(1.169 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T07:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.740 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(141.9 AS Decimal(10, 1)), CAST(1.628 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T08:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.796 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(168.8 AS Decimal(10, 1)), CAST(1.438 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T08:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.852 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(141.3 AS Decimal(10, 1)), CAST(0.882 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T08:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.908 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(163.0 AS Decimal(10, 1)), CAST(0.776 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T08:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.020 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(165.8 AS Decimal(10, 1)), CAST(0.752 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T08:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.121 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(112.8 AS Decimal(10, 1)), CAST(0.779 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T08:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.007 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.9 AS Decimal(10, 1)), CAST(0.978 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T09:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.993 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(129.0 AS Decimal(10, 1)), CAST(1.157 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T09:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.937 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.6 AS Decimal(10, 1)), CAST(1.828 AS Decimal(10, 3)), CAST(2.744 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T09:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(0.993 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.0 AS Decimal(10, 1)), CAST(1.505 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T09:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.007 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.2 AS Decimal(10, 1)), CAST(1.456 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T09:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.151 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(183.2 AS Decimal(10, 1)), CAST(1.240 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T09:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.135 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(129.0 AS Decimal(10, 1)), CAST(1.657 AS Decimal(10, 3)), CAST(2.744 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T10:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.121 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(120.4 AS Decimal(10, 1)), CAST(1.730 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T10:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.177 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(142.4 AS Decimal(10, 1)), CAST(1.060 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T10:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.177 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(142.0 AS Decimal(10, 1)), CAST(1.012 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T10:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.151 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(145.1 AS Decimal(10, 1)), CAST(1.313 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T10:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.076 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(186.4 AS Decimal(10, 1)), CAST(1.430 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T10:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.020 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(141.3 AS Decimal(10, 1)), CAST(1.933 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T11:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.020 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.4 AS Decimal(10, 1)), CAST(1.747 AS Decimal(10, 3)), CAST(3.038 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T11:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.049 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(114.8 AS Decimal(10, 1)), CAST(1.951 AS Decimal(10, 3)), CAST(3.038 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T11:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.063 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(84.6 AS Decimal(10, 1)), CAST(1.359 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T11:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.220 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(146.7 AS Decimal(10, 1)), CAST(0.780 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T11:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.247 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(138.4 AS Decimal(10, 1)), CAST(0.819 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T11:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.263 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.5 AS Decimal(10, 1)), CAST(1.205 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T12:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.332 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.1 AS Decimal(10, 1)), CAST(1.325 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T12:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.346 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(154.1 AS Decimal(10, 1)), CAST(1.676 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T12:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.501 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(113.2 AS Decimal(10, 1)), CAST(1.396 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T12:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(199.3 AS Decimal(10, 1)), CAST(1.157 AS Decimal(10, 3)), CAST(2.842 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T12:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.824 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(141.2 AS Decimal(10, 1)), CAST(1.181 AS Decimal(10, 3)), CAST(2.744 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T12:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.810 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(111.0 AS Decimal(10, 1)), CAST(1.563 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T13:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.912 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(119.9 AS Decimal(10, 1)), CAST(1.713 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T13:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.955 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(118.5 AS Decimal(10, 1)), CAST(1.783 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T13:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.968 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.6 AS Decimal(10, 1)), CAST(2.048 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T13:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.136 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(145.9 AS Decimal(10, 1)), CAST(2.289 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T13:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.109 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.7 AS Decimal(10, 1)), CAST(1.977 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T13:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.166 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(121.4 AS Decimal(10, 1)), CAST(1.500 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T14:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.222 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(98.9 AS Decimal(10, 1)), CAST(1.876 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T14:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.192 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(151.0 AS Decimal(10, 1)), CAST(1.741 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T14:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.067 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(87.2 AS Decimal(10, 1)), CAST(1.935 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T14:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(2.011 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(64.8 AS Decimal(10, 1)), CAST(1.966 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T14:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.925 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(134.6 AS Decimal(10, 1)), CAST(1.607 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T14:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.896 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(200.0 AS Decimal(10, 1)), CAST(2.064 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T15:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.810 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(133.5 AS Decimal(10, 1)), CAST(1.919 AS Decimal(10, 3)), CAST(2.842 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T15:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.629 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(154.3 AS Decimal(10, 1)), CAST(2.273 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T15:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.530 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(132.7 AS Decimal(10, 1)), CAST(1.862 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T15:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.458 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(164.8 AS Decimal(10, 1)), CAST(1.662 AS Decimal(10, 3)), CAST(2.450 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T15:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(1.319 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(47.6 AS Decimal(10, 1)), CAST(1.411 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T15:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.263 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.0 AS Decimal(10, 1)), CAST(1.242 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T16:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.951 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(94.9 AS Decimal(10, 1)), CAST(0.984 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T16:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.726 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(23.4 AS Decimal(10, 1)), CAST(1.282 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T16:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.486 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(162.8 AS Decimal(10, 1)), CAST(0.286 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T16:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(-0.020 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(319.6 AS Decimal(10, 1)), CAST(0.184 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T16:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(-0.330 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(181.2 AS Decimal(10, 1)), CAST(0.495 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T16:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(-0.488 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(184.4 AS Decimal(10, 1)), CAST(0.243 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T17:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(-0.557 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(15.8 AS Decimal(10, 1)), CAST(0.474 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T17:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(-0.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.2 AS Decimal(10, 1)), CAST(0.649 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T17:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.246 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(176.5 AS Decimal(10, 1)), CAST(1.151 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T17:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.515 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(131.6 AS Decimal(10, 1)), CAST(1.263 AS Decimal(10, 3)), CAST(2.450 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T17:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.598 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(129.1 AS Decimal(10, 1)), CAST(1.509 AS Decimal(10, 3)), CAST(3.136 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T17:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.555 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(155.0 AS Decimal(10, 1)), CAST(1.487 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T18:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.555 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(150.0 AS Decimal(10, 1)), CAST(1.294 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T18:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.216 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(56.3 AS Decimal(10, 1)), CAST(1.023 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T18:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.286 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(145.8 AS Decimal(10, 1)), CAST(0.789 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T18:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.259 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(94.3 AS Decimal(10, 1)), CAST(1.504 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T18:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.075 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(43.6 AS Decimal(10, 1)), CAST(0.944 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T18:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(-0.218 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(54.3 AS Decimal(10, 1)), CAST(0.641 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T19:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-0.304 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(333.8 AS Decimal(10, 1)), CAST(0.911 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T19:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-0.824 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(326.9 AS Decimal(10, 1)), CAST(0.583 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T19:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-0.966 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(326.6 AS Decimal(10, 1)), CAST(0.625 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T19:30:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.121 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(34.0 AS Decimal(10, 1)), CAST(0.959 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T19:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.035 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(72.8 AS Decimal(10, 1)), CAST(0.718 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T19:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(0.203 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(277.0 AS Decimal(10, 1)), CAST(1.835 AS Decimal(10, 3)), CAST(2.842 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T20:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.669 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(107.8 AS Decimal(10, 1)), CAST(2.498 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T20:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.853 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.2 AS Decimal(10, 1)), CAST(2.480 AS Decimal(10, 3)), CAST(3.822 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T20:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.613 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.5 AS Decimal(10, 1)), CAST(3.038 AS Decimal(10, 3)), CAST(4.410 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T20:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.049 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(138.0 AS Decimal(10, 1)), CAST(3.178 AS Decimal(10, 3)), CAST(3.724 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T20:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.263 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(150.1 AS Decimal(10, 1)), CAST(2.575 AS Decimal(10, 3)), CAST(2.352 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T20:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.430 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(161.4 AS Decimal(10, 1)), CAST(3.313 AS Decimal(10, 3)), CAST(3.430 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T21:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.828 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(160.6 AS Decimal(10, 1)), CAST(3.409 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T21:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.996 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(200.2 AS Decimal(10, 1)), CAST(3.791 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T21:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.180 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(265.9 AS Decimal(10, 1)), CAST(3.712 AS Decimal(10, 3)), CAST(6.272 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T21:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.250 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(235.0 AS Decimal(10, 1)), CAST(4.499 AS Decimal(10, 3)), CAST(3.724 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T21:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.180 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(180.5 AS Decimal(10, 1)), CAST(3.623 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T21:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.276 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(264.6 AS Decimal(10, 1)), CAST(4.125 AS Decimal(10, 3)), CAST(7.840 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T22:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.276 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(267.1 AS Decimal(10, 1)), CAST(3.616 AS Decimal(10, 3)), CAST(3.528 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T22:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.220 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(174.1 AS Decimal(10, 1)), CAST(3.796 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T22:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.263 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(233.4 AS Decimal(10, 1)), CAST(2.734 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T22:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.292 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(251.4 AS Decimal(10, 1)), CAST(3.247 AS Decimal(10, 3)), CAST(3.430 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T22:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.390 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.5 AS Decimal(10, 1)), CAST(3.338 AS Decimal(10, 3)), CAST(3.626 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T22:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(0.822 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.0 AS Decimal(10, 1)), CAST(2.467 AS Decimal(10, 3)), CAST(3.528 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T23:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(0.272 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(159.2 AS Decimal(10, 1)), CAST(2.477 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T23:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(0.328 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(197.7 AS Decimal(10, 1)), CAST(1.647 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T23:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(0.230 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(118.9 AS Decimal(10, 1)), CAST(1.671 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T23:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(-0.162 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(115.6 AS Decimal(10, 1)), CAST(1.586 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T23:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-0.330 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(160.3 AS Decimal(10, 1)), CAST(1.426 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-15T23:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-0.416 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(116.9 AS Decimal(10, 1)), CAST(1.485 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T00:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-0.699 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(207.5 AS Decimal(10, 1)), CAST(0.787 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T00:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-0.867 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(4.1 AS Decimal(10, 1)), CAST(0.760 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T00:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.292 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(222.8 AS Decimal(10, 1)), CAST(0.312 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T00:30:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.460 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(236.2 AS Decimal(10, 1)), CAST(0.518 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T00:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.503 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(35.6 AS Decimal(10, 1)), CAST(1.072 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T00:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.361 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(135.2 AS Decimal(10, 1)), CAST(0.663 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T01:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.671 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(340.3 AS Decimal(10, 1)), CAST(0.571 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T01:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.657 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(223.9 AS Decimal(10, 1)), CAST(0.385 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T01:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.476 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(183.1 AS Decimal(10, 1)), CAST(0.442 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T01:30:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.671 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(36.0 AS Decimal(10, 1)), CAST(0.397 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T01:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.671 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(51.4 AS Decimal(10, 1)), CAST(0.670 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T01:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.516 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(217.1 AS Decimal(10, 1)), CAST(0.842 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T02:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.601 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(239.6 AS Decimal(10, 1)), CAST(0.835 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T02:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.601 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(171.5 AS Decimal(10, 1)), CAST(0.696 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T02:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.572 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(342.6 AS Decimal(10, 1)), CAST(0.787 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T02:30:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.305 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(181.2 AS Decimal(10, 1)), CAST(0.729 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T02:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.572 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(172.7 AS Decimal(10, 1)), CAST(0.337 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T02:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.868 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(7.0 AS Decimal(10, 1)), CAST(0.296 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T03:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.967 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(309.2 AS Decimal(10, 1)), CAST(0.165 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T03:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-2.162 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(37.2 AS Decimal(10, 1)), CAST(0.367 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T03:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-2.293 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(34.5 AS Decimal(10, 1)), CAST(0.291 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T03:30:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-2.349 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(263.9 AS Decimal(10, 1)), CAST(0.119 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T03:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-2.376 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(306.9 AS Decimal(10, 1)), CAST(0.030 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T03:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-2.349 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(104.5 AS Decimal(10, 1)), CAST(0.384 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T04:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-2.122 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(354.4 AS Decimal(10, 1)), CAST(0.451 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T04:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.967 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(159.8 AS Decimal(10, 1)), CAST(0.443 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T04:20:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.938 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(230.3 AS Decimal(10, 1)), CAST(0.521 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T04:30:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.882 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(279.1 AS Decimal(10, 1)), CAST(0.267 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T04:40:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.826 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(312.4 AS Decimal(10, 1)), CAST(0.165 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T04:50:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.839 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(226.1 AS Decimal(10, 1)), CAST(0.077 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T05:00:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.783 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(305.2 AS Decimal(10, 1)), CAST(0.387 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T05:10:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.799 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(20.3 AS Decimal(10, 1)), CAST(0.367 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T05:20:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.839 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(186.3 AS Decimal(10, 1)), CAST(0.543 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T05:30:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.503 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(176.3 AS Decimal(10, 1)), CAST(0.549 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T05:40:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.783 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(149.2 AS Decimal(10, 1)), CAST(0.445 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T05:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.799 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(89.3 AS Decimal(10, 1)), CAST(0.563 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T06:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.727 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(45.8 AS Decimal(10, 1)), CAST(0.308 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T06:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(-1.545 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(184.2 AS Decimal(10, 1)), CAST(0.511 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T06:20:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-1.051 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(153.2 AS Decimal(10, 1)), CAST(0.636 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T06:30:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-0.798 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.0 AS Decimal(10, 1)), CAST(1.083 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T06:40:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-0.798 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(106.2 AS Decimal(10, 1)), CAST(1.188 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T06:50:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-0.867 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(330.4 AS Decimal(10, 1)), CAST(0.421 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T07:00:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(-0.330 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(251.3 AS Decimal(10, 1)), CAST(0.314 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T07:10:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(0.189 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(23.9 AS Decimal(10, 1)), CAST(0.704 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T07:20:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(0.710 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(53.0 AS Decimal(10, 1)), CAST(0.869 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T07:30:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(1.418 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(52.2 AS Decimal(10, 1)), CAST(0.662 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T07:40:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(1.968 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(84.8 AS Decimal(10, 1)), CAST(0.482 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T07:50:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.729 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(102.8 AS Decimal(10, 1)), CAST(0.563 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T08:00:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.037 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.2 AS Decimal(10, 1)), CAST(1.811 AS Decimal(10, 3)), CAST(2.450 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T08:10:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.136 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(114.9 AS Decimal(10, 1)), CAST(2.135 AS Decimal(10, 3)), CAST(2.940 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T08:20:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.080 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(136.8 AS Decimal(10, 1)), CAST(2.394 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T08:30:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.334 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.7 AS Decimal(10, 1)), CAST(2.272 AS Decimal(10, 3)), CAST(2.940 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T08:40:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.433 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(119.9 AS Decimal(10, 1)), CAST(2.557 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T08:50:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.729 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.1 AS Decimal(10, 1)), CAST(2.260 AS Decimal(10, 3)), CAST(2.450 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T09:00:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.870 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.4 AS Decimal(10, 1)), CAST(1.825 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T09:10:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(2.927 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.5 AS Decimal(10, 1)), CAST(1.628 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T09:20:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(3.164 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(129.5 AS Decimal(10, 1)), CAST(1.751 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T09:30:00.000' AS DateTime), CAST(946.00 AS Decimal(10, 2)), CAST(3.236 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(142.0 AS Decimal(10, 1)), CAST(2.251 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T09:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.348 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(118.2 AS Decimal(10, 1)), CAST(2.201 AS Decimal(10, 3)), CAST(2.744 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T09:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.348 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.1 AS Decimal(10, 1)), CAST(2.490 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T10:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.194 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.7 AS Decimal(10, 1)), CAST(2.567 AS Decimal(10, 3)), CAST(3.724 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T10:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.236 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(131.2 AS Decimal(10, 1)), CAST(2.483 AS Decimal(10, 3)), CAST(2.352 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T10:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.220 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.5 AS Decimal(10, 1)), CAST(2.124 AS Decimal(10, 3)), CAST(2.548 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T10:30:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.151 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(148.3 AS Decimal(10, 1)), CAST(2.323 AS Decimal(10, 3)), CAST(2.940 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T10:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.138 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(133.9 AS Decimal(10, 1)), CAST(2.168 AS Decimal(10, 3)), CAST(3.234 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T10:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.095 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(165.1 AS Decimal(10, 1)), CAST(2.306 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T11:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.124 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.3 AS Decimal(10, 1)), CAST(2.153 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T11:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.236 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(133.5 AS Decimal(10, 1)), CAST(2.084 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T11:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.276 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(136.5 AS Decimal(10, 1)), CAST(1.959 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T11:30:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.348 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(134.8 AS Decimal(10, 1)), CAST(1.712 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T11:40:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.418 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(95.0 AS Decimal(10, 1)), CAST(1.831 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T11:50:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.362 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(159.2 AS Decimal(10, 1)), CAST(1.850 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T12:00:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.431 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(136.8 AS Decimal(10, 1)), CAST(1.873 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T12:10:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.447 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(157.1 AS Decimal(10, 1)), CAST(2.217 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T12:20:00.000' AS DateTime), CAST(945.00 AS Decimal(10, 2)), CAST(3.533 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(113.8 AS Decimal(10, 1)), CAST(1.821 AS Decimal(10, 3)), CAST(3.234 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T12:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.418 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.3 AS Decimal(10, 1)), CAST(1.877 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T12:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.431 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.9 AS Decimal(10, 1)), CAST(1.740 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T12:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.348 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(158.2 AS Decimal(10, 1)), CAST(2.105 AS Decimal(10, 3)), CAST(2.548 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T13:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.391 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(153.2 AS Decimal(10, 1)), CAST(1.665 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T13:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.391 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.5 AS Decimal(10, 1)), CAST(1.308 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T13:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.447 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(139.5 AS Decimal(10, 1)), CAST(1.473 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T13:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.477 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(111.4 AS Decimal(10, 1)), CAST(1.285 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T13:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.418 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(162.0 AS Decimal(10, 1)), CAST(1.365 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T13:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.405 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.9 AS Decimal(10, 1)), CAST(1.104 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T14:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.405 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(166.7 AS Decimal(10, 1)), CAST(1.009 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T14:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.348 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(149.2 AS Decimal(10, 1)), CAST(0.879 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T14:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.405 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(103.0 AS Decimal(10, 1)), CAST(0.334 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T14:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.431 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(78.0 AS Decimal(10, 1)), CAST(0.331 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T14:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.431 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.2 AS Decimal(10, 1)), CAST(0.354 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T14:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.292 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(183.6 AS Decimal(10, 1)), CAST(0.107 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T15:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(3.180 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(216.0 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T15:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.953 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(45.2 AS Decimal(10, 1)), CAST(0.163 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T15:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.828 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(111.2 AS Decimal(10, 1)), CAST(0.031 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T15:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.884 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(151.1 AS Decimal(10, 1)), CAST(0.227 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T15:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.798 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.2 AS Decimal(10, 1)), CAST(0.301 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T15:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.742 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.3 AS Decimal(10, 1)), CAST(0.286 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T16:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.716 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(160.1 AS Decimal(10, 1)), CAST(0.587 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T16:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.670 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(175.0 AS Decimal(10, 1)), CAST(0.673 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T16:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.670 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(109.7 AS Decimal(10, 1)), CAST(0.787 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T16:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.657 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(145.7 AS Decimal(10, 1)), CAST(0.793 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T16:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.545 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(45.3 AS Decimal(10, 1)), CAST(0.293 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T16:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.403 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(51.0 AS Decimal(10, 1)), CAST(0.053 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T17:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.248 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(50.8 AS Decimal(10, 1)), CAST(0.002 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T17:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.093 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(269.4 AS Decimal(10, 1)), CAST(0.270 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T17:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.067 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(65.4 AS Decimal(10, 1)), CAST(0.053 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T17:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.3 AS Decimal(10, 1)), CAST(0.302 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T17:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(2.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(285.3 AS Decimal(10, 1)), CAST(0.598 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T17:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.866 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(317.9 AS Decimal(10, 1)), CAST(0.050 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T18:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.896 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(309.8 AS Decimal(10, 1)), CAST(0.089 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T18:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.685 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(340.8 AS Decimal(10, 1)), CAST(0.065 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T18:20:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.669 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(340.8 AS Decimal(10, 1)), CAST(0.003 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T18:30:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.613 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(308.2 AS Decimal(10, 1)), CAST(0.412 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T18:40:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.530 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(291.1 AS Decimal(10, 1)), CAST(0.436 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T18:50:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.557 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(284.2 AS Decimal(10, 1)), CAST(0.220 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T19:00:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.613 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(259.6 AS Decimal(10, 1)), CAST(0.027 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T19:10:00.000' AS DateTime), CAST(944.00 AS Decimal(10, 2)), CAST(1.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(274.3 AS Decimal(10, 1)), CAST(0.083 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T19:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.514 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(274.1 AS Decimal(10, 1)), CAST(0.025 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T19:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.586 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(274.0 AS Decimal(10, 1)), CAST(0.006 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T19:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.557 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(274.3 AS Decimal(10, 1)), CAST(0.051 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T19:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.642 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(274.2 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T20:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.543 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(274.3 AS Decimal(10, 1)), CAST(0.182 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T20:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.712 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(208.4 AS Decimal(10, 1)), CAST(0.108 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T20:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.642 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(275.2 AS Decimal(10, 1)), CAST(0.159 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T20:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.642 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(309.7 AS Decimal(10, 1)), CAST(0.643 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T20:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.768 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(310.4 AS Decimal(10, 1)), CAST(0.984 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T20:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.741 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(328.5 AS Decimal(10, 1)), CAST(0.995 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T21:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.669 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(278.1 AS Decimal(10, 1)), CAST(0.947 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T21:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.655 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(318.5 AS Decimal(10, 1)), CAST(1.222 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T21:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.543 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(344.3 AS Decimal(10, 1)), CAST(1.174 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T21:30:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.402 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(78.1 AS Decimal(10, 1)), CAST(1.357 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T21:40:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.220 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(342.6 AS Decimal(10, 1)), CAST(1.223 AS Decimal(10, 3)), CAST(2.352 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T21:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(1.007 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(298.6 AS Decimal(10, 1)), CAST(0.786 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T22:00:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.683 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(331.4 AS Decimal(10, 1)), CAST(0.530 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T22:10:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.416 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.5 AS Decimal(10, 1)), CAST(0.296 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T22:20:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(0.160 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(323.0 AS Decimal(10, 1)), CAST(0.222 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T22:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-0.205 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(337.2 AS Decimal(10, 1)), CAST(0.271 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T22:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-0.557 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(257.9 AS Decimal(10, 1)), CAST(0.020 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T22:50:00.000' AS DateTime), CAST(943.00 AS Decimal(10, 2)), CAST(-1.022 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(260.2 AS Decimal(10, 1)), CAST(0.129 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T23:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-1.107 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(260.3 AS Decimal(10, 1)), CAST(0.193 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T23:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-1.249 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(296.1 AS Decimal(10, 1)), CAST(0.182 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T23:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-1.235 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(243.7 AS Decimal(10, 1)), CAST(0.144 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T23:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-1.516 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(244.1 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T23:40:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-1.559 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(240.8 AS Decimal(10, 1)), CAST(0.238 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-16T23:50:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-1.812 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(13.6 AS Decimal(10, 1)), CAST(0.510 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T00:00:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-1.938 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(258.2 AS Decimal(10, 1)), CAST(0.133 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T00:10:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-2.122 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.361 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T00:20:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-2.162 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(334.0 AS Decimal(10, 1)), CAST(0.013 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T00:30:00.000' AS DateTime), CAST(942.00 AS Decimal(10, 2)), CAST(-2.336 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(333.7 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T00:40:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.293 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(343.5 AS Decimal(10, 1)), CAST(0.227 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T00:50:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.392 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(248.3 AS Decimal(10, 1)), CAST(0.166 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T01:00:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.392 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(37.8 AS Decimal(10, 1)), CAST(0.252 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T01:10:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.320 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(53.0 AS Decimal(10, 1)), CAST(0.204 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T01:20:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.461 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(291.5 AS Decimal(10, 1)), CAST(0.228 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T01:30:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.560 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(246.0 AS Decimal(10, 1)), CAST(0.226 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T01:40:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.728 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(294.7 AS Decimal(10, 1)), CAST(0.087 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T01:50:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.728 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(354.4 AS Decimal(10, 1)), CAST(0.329 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T02:00:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.758 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(239.8 AS Decimal(10, 1)), CAST(0.298 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T02:10:00.000' AS DateTime), CAST(941.00 AS Decimal(10, 2)), CAST(-2.982 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(17.4 AS Decimal(10, 1)), CAST(0.141 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T02:20:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.038 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(323.7 AS Decimal(10, 1)), CAST(0.061 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T02:30:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-2.969 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(310.0 AS Decimal(10, 1)), CAST(0.658 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T02:40:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-2.953 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(1.5 AS Decimal(10, 1)), CAST(0.213 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T02:50:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.107 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(295.8 AS Decimal(10, 1)), CAST(0.138 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T03:00:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.220 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(15.2 AS Decimal(10, 1)), CAST(0.359 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T03:10:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.150 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(290.6 AS Decimal(10, 1)), CAST(0.393 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T03:20:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.364 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(31.8 AS Decimal(10, 1)), CAST(0.399 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T03:30:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-2.939 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(301.7 AS Decimal(10, 1)), CAST(0.294 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T03:40:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.150 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(298.0 AS Decimal(10, 1)), CAST(0.543 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T03:50:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.350 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(333.4 AS Decimal(10, 1)), CAST(0.535 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T04:00:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.179 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(247.0 AS Decimal(10, 1)), CAST(0.454 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T04:10:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.406 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(24.9 AS Decimal(10, 1)), CAST(0.327 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T04:20:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.449 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(302.2 AS Decimal(10, 1)), CAST(0.362 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T04:30:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.687 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(343.2 AS Decimal(10, 1)), CAST(0.343 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T04:40:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.631 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(294.0 AS Decimal(10, 1)), CAST(0.256 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T04:50:00.000' AS DateTime), CAST(940.00 AS Decimal(10, 2)), CAST(-3.799 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(22.4 AS Decimal(10, 1)), CAST(0.226 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T05:00:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.812 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(250.1 AS Decimal(10, 1)), CAST(0.250 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T05:10:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.799 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(317.6 AS Decimal(10, 1)), CAST(0.403 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T05:20:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.898 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(335.3 AS Decimal(10, 1)), CAST(0.051 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T05:30:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-4.039 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(308.0 AS Decimal(10, 1)), CAST(0.318 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T05:40:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-4.010 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(323.8 AS Decimal(10, 1)), CAST(0.765 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T05:50:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.954 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(237.2 AS Decimal(10, 1)), CAST(0.258 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T06:00:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.954 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(354.4 AS Decimal(10, 1)), CAST(0.134 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T06:10:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.898 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(283.7 AS Decimal(10, 1)), CAST(0.111 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T06:20:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.842 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(269.1 AS Decimal(10, 1)), CAST(0.579 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T06:30:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.842 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.213 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T06:40:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.617 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(42.9 AS Decimal(10, 1)), CAST(0.133 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T06:50:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-3.236 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(9.6 AS Decimal(10, 1)), CAST(0.382 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T07:00:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-2.701 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(43.5 AS Decimal(10, 1)), CAST(0.227 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T07:10:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-1.588 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(43.8 AS Decimal(10, 1)), CAST(0.089 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T07:20:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-0.966 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(43.7 AS Decimal(10, 1)), CAST(0.286 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T07:30:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(-0.288 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(42.1 AS Decimal(10, 1)), CAST(0.554 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T07:40:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(0.515 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(56.1 AS Decimal(10, 1)), CAST(0.461 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T07:50:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(1.135 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(52.3 AS Decimal(10, 1)), CAST(0.671 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T08:00:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(1.402 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(67.9 AS Decimal(10, 1)), CAST(0.849 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T08:10:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(1.530 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.8 AS Decimal(10, 1)), CAST(1.254 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T08:20:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(1.698 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(135.3 AS Decimal(10, 1)), CAST(1.249 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T08:30:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(2.206 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(116.7 AS Decimal(10, 1)), CAST(0.908 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T08:40:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(2.318 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(119.0 AS Decimal(10, 1)), CAST(1.203 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T08:50:00.000' AS DateTime), CAST(939.00 AS Decimal(10, 2)), CAST(2.644 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.8 AS Decimal(10, 1)), CAST(1.261 AS Decimal(10, 3)), CAST(2.352 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T09:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.657 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(115.7 AS Decimal(10, 1)), CAST(1.846 AS Decimal(10, 3)), CAST(2.744 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T09:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.473 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(120.6 AS Decimal(10, 1)), CAST(2.349 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T09:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.684 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(109.5 AS Decimal(10, 1)), CAST(2.217 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T09:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.772 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(159.5 AS Decimal(10, 1)), CAST(2.304 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T09:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.940 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(138.3 AS Decimal(10, 1)), CAST(2.401 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T09:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(3.095 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(147.3 AS Decimal(10, 1)), CAST(2.243 AS Decimal(10, 3)), CAST(2.548 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T10:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(3.418 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.4 AS Decimal(10, 1)), CAST(1.915 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T10:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(3.431 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(151.0 AS Decimal(10, 1)), CAST(2.175 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T10:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(3.717 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.6 AS Decimal(10, 1)), CAST(1.899 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T10:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.235 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.2 AS Decimal(10, 1)), CAST(1.568 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T10:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.521 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(113.1 AS Decimal(10, 1)), CAST(1.662 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T10:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.702 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.9 AS Decimal(10, 1)), CAST(1.253 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T11:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.745 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.6 AS Decimal(10, 1)), CAST(1.616 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T11:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.758 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.1 AS Decimal(10, 1)), CAST(1.662 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T11:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.887 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(213.0 AS Decimal(10, 1)), CAST(1.313 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T11:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.294 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(134.9 AS Decimal(10, 1)), CAST(0.423 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T11:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.280 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(278.4 AS Decimal(10, 1)), CAST(0.151 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T11:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(3.533 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(240.5 AS Decimal(10, 1)), CAST(0.392 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T12:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(3.039 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(240.6 AS Decimal(10, 1)), CAST(0.839 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T12:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(2.716 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(164.7 AS Decimal(10, 1)), CAST(0.566 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T12:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(2.529 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(281.7 AS Decimal(10, 1)), CAST(0.287 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T12:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(2.291 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(290.8 AS Decimal(10, 1)), CAST(0.307 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T12:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(2.080 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(318.2 AS Decimal(10, 1)), CAST(0.652 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T12:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(2.011 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(233.7 AS Decimal(10, 1)), CAST(0.398 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T13:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(2.011 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(277.2 AS Decimal(10, 1)), CAST(0.139 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T13:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(1.655 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(251.9 AS Decimal(10, 1)), CAST(0.526 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T13:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(1.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(320.7 AS Decimal(10, 1)), CAST(0.604 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T13:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(1.458 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(306.5 AS Decimal(10, 1)), CAST(0.325 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T13:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(1.207 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(235.2 AS Decimal(10, 1)), CAST(0.392 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T13:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(1.121 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(337.9 AS Decimal(10, 1)), CAST(0.284 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T14:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.977 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(281.0 AS Decimal(10, 1)), CAST(0.587 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T14:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.951 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(226.3 AS Decimal(10, 1)), CAST(0.455 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T14:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.796 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(253.5 AS Decimal(10, 1)), CAST(0.320 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T14:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.598 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(285.8 AS Decimal(10, 1)), CAST(0.539 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T14:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.499 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(253.9 AS Decimal(10, 1)), CAST(0.690 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T14:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(277.6 AS Decimal(10, 1)), CAST(0.449 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T15:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.147 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(338.7 AS Decimal(10, 1)), CAST(0.278 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T15:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(0.019 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(332.3 AS Decimal(10, 1)), CAST(0.494 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T15:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.7 AS Decimal(10, 1)), CAST(0.529 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T15:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.317 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(284.8 AS Decimal(10, 1)), CAST(0.536 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T15:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.488 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(255.2 AS Decimal(10, 1)), CAST(0.378 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T15:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.573 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(266.8 AS Decimal(10, 1)), CAST(0.317 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T16:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.699 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(275.6 AS Decimal(10, 1)), CAST(0.498 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T16:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.854 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(273.0 AS Decimal(10, 1)), CAST(0.707 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T16:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.867 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(267.6 AS Decimal(10, 1)), CAST(0.389 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T16:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.840 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(214.5 AS Decimal(10, 1)), CAST(0.155 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T16:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.854 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(268.0 AS Decimal(10, 1)), CAST(0.560 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T16:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.910 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(260.0 AS Decimal(10, 1)), CAST(0.665 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T17:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.009 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(314.9 AS Decimal(10, 1)), CAST(0.406 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T17:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.979 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(252.4 AS Decimal(10, 1)), CAST(0.500 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T17:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.035 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(325.0 AS Decimal(10, 1)), CAST(0.427 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T17:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.035 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(286.7 AS Decimal(10, 1)), CAST(0.585 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T17:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.979 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(300.5 AS Decimal(10, 1)), CAST(0.728 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T17:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.249 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(330.5 AS Decimal(10, 1)), CAST(0.482 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T18:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.265 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(330.5 AS Decimal(10, 1)), CAST(0.052 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T18:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.321 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(222.4 AS Decimal(10, 1)), CAST(0.231 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T18:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.321 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(289.0 AS Decimal(10, 1)), CAST(0.580 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T18:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.404 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(2.6 AS Decimal(10, 1)), CAST(0.651 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T18:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.348 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(6.3 AS Decimal(10, 1)), CAST(0.544 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T18:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.235 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(331.7 AS Decimal(10, 1)), CAST(0.691 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T19:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.292 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(308.6 AS Decimal(10, 1)), CAST(0.339 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T19:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.420 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(258.2 AS Decimal(10, 1)), CAST(0.836 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T19:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.460 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(244.1 AS Decimal(10, 1)), CAST(0.336 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T19:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.420 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(279.6 AS Decimal(10, 1)), CAST(0.697 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T19:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.628 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(268.4 AS Decimal(10, 1)), CAST(0.469 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T19:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.628 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(287.7 AS Decimal(10, 1)), CAST(0.306 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T20:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.657 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(294.8 AS Decimal(10, 1)), CAST(0.281 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T20:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.799 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(284.1 AS Decimal(10, 1)), CAST(0.756 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T20:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.572 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(286.8 AS Decimal(10, 1)), CAST(0.565 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T20:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.460 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(354.4 AS Decimal(10, 1)), CAST(0.454 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T20:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.700 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(245.5 AS Decimal(10, 1)), CAST(0.116 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T20:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.839 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(268.5 AS Decimal(10, 1)), CAST(0.623 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T21:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.783 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(282.5 AS Decimal(10, 1)), CAST(0.632 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T21:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.868 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(293.0 AS Decimal(10, 1)), CAST(0.419 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T21:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.812 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(258.4 AS Decimal(10, 1)), CAST(0.181 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T21:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.066 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(281.7 AS Decimal(10, 1)), CAST(0.809 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T21:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.967 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(268.1 AS Decimal(10, 1)), CAST(0.592 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T21:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.010 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(305.1 AS Decimal(10, 1)), CAST(0.462 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T22:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.093 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(304.8 AS Decimal(10, 1)), CAST(0.174 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T22:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.093 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(287.4 AS Decimal(10, 1)), CAST(0.614 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T22:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.050 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(259.4 AS Decimal(10, 1)), CAST(0.729 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T22:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.122 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(354.4 AS Decimal(10, 1)), CAST(0.361 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T22:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.207 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(318.7 AS Decimal(10, 1)), CAST(0.195 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T22:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.392 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(299.2 AS Decimal(10, 1)), CAST(0.389 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T23:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.336 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(225.5 AS Decimal(10, 1)), CAST(0.640 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T23:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.207 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(346.1 AS Decimal(10, 1)), CAST(0.644 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T23:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(308.7 AS Decimal(10, 1)), CAST(0.473 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T23:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.237 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(331.1 AS Decimal(10, 1)), CAST(0.559 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T23:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.362 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(253.5 AS Decimal(10, 1)), CAST(0.545 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-17T23:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.336 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(264.6 AS Decimal(10, 1)), CAST(0.592 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T00:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.162 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(312.1 AS Decimal(10, 1)), CAST(0.410 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T00:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.224 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(270.2 AS Decimal(10, 1)), CAST(0.592 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T00:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.250 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(264.5 AS Decimal(10, 1)), CAST(0.519 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T00:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(6.9 AS Decimal(10, 1)), CAST(0.440 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T00:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-2.010 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(225.8 AS Decimal(10, 1)), CAST(0.472 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T00:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.839 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(274.3 AS Decimal(10, 1)), CAST(1.007 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T01:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.446 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(25.2 AS Decimal(10, 1)), CAST(1.280 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T01:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.235 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(12.9 AS Decimal(10, 1)), CAST(0.976 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T01:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.334 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(297.4 AS Decimal(10, 1)), CAST(0.781 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T01:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.377 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(211.7 AS Decimal(10, 1)), CAST(1.149 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T01:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.265 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(143.0 AS Decimal(10, 1)), CAST(0.484 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T01:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.728 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(333.8 AS Decimal(10, 1)), CAST(0.668 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T02:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.643 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(156.8 AS Decimal(10, 1)), CAST(0.615 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T02:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.386 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(301.5 AS Decimal(10, 1)), CAST(0.770 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T02:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.474 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(208.0 AS Decimal(10, 1)), CAST(0.549 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T02:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.288 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(5.2 AS Decimal(10, 1)), CAST(0.293 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T02:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.429 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(4.8 AS Decimal(10, 1)), CAST(0.645 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T02:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(-0.274 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(203.7 AS Decimal(10, 1)), CAST(0.516 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T03:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.317 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(131.2 AS Decimal(10, 1)), CAST(0.364 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T03:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.274 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(218.3 AS Decimal(10, 1)), CAST(0.438 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T03:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.119 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(224.4 AS Decimal(10, 1)), CAST(0.761 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T03:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.218 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(150.1 AS Decimal(10, 1)), CAST(0.613 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T03:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.304 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(175.9 AS Decimal(10, 1)), CAST(0.391 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T03:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.093 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(32.6 AS Decimal(10, 1)), CAST(0.745 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T04:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.474 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(353.5 AS Decimal(10, 1)), CAST(0.376 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T04:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.442 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(332.9 AS Decimal(10, 1)), CAST(0.533 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T04:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.643 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(21.3 AS Decimal(10, 1)), CAST(0.486 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T04:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.712 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(273.2 AS Decimal(10, 1)), CAST(0.426 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T04:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.712 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(234.9 AS Decimal(10, 1)), CAST(0.584 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T04:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.923 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(259.0 AS Decimal(10, 1)), CAST(0.372 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T05:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-1.035 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(284.2 AS Decimal(10, 1)), CAST(0.424 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T05:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.896 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(295.2 AS Decimal(10, 1)), CAST(0.590 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T05:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.867 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(8.6 AS Decimal(10, 1)), CAST(0.775 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T05:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.867 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(282.6 AS Decimal(10, 1)), CAST(0.422 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T05:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.880 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(282.3 AS Decimal(10, 1)), CAST(0.367 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T05:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.557 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(249.7 AS Decimal(10, 1)), CAST(0.597 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T06:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(-0.373 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(348.2 AS Decimal(10, 1)), CAST(0.550 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T06:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(0.061 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(231.0 AS Decimal(10, 1)), CAST(0.692 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T06:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(0.160 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(138.0 AS Decimal(10, 1)), CAST(0.355 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T06:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(0.486 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(95.4 AS Decimal(10, 1)), CAST(0.158 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T06:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(0.344 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(276.4 AS Decimal(10, 1)), CAST(0.503 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T06:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(0.852 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(250.0 AS Decimal(10, 1)), CAST(1.033 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T07:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(0.993 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(323.9 AS Decimal(10, 1)), CAST(0.906 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T07:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(1.362 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(27.3 AS Decimal(10, 1)), CAST(0.132 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T07:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(1.514 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(172.2 AS Decimal(10, 1)), CAST(0.622 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T07:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(2.291 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(227.9 AS Decimal(10, 1)), CAST(0.690 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T07:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(2.601 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(258.6 AS Decimal(10, 1)), CAST(0.516 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T07:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.138 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(286.3 AS Decimal(10, 1)), CAST(0.322 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T08:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.984 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(163.3 AS Decimal(10, 1)), CAST(0.123 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T08:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.024 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.127 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T08:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.689 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(247.6 AS Decimal(10, 1)), CAST(0.172 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T08:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(5.170 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(266.4 AS Decimal(10, 1)), CAST(0.022 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T08:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(6.086 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(83.7 AS Decimal(10, 1)), CAST(0.447 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T08:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(6.478 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.6 AS Decimal(10, 1)), CAST(0.631 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T09:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(6.847 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(101.8 AS Decimal(10, 1)), CAST(0.544 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T09:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(7.044 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(135.8 AS Decimal(10, 1)), CAST(0.853 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T09:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(7.568 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(189.3 AS Decimal(10, 1)), CAST(0.445 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T09:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(7.990 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.2 AS Decimal(10, 1)), CAST(0.266 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T09:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(7.861 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(92.3 AS Decimal(10, 1)), CAST(0.859 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T09:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(8.070 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(118.4 AS Decimal(10, 1)), CAST(0.736 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T10:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(8.480 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(316.8 AS Decimal(10, 1)), CAST(0.292 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T10:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(8.710 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(90.2 AS Decimal(10, 1)), CAST(0.213 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T10:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(8.850 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(109.2 AS Decimal(10, 1)), CAST(0.553 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T10:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.030 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(112.8 AS Decimal(10, 1)), CAST(0.623 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T10:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.180 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.3 AS Decimal(10, 1)), CAST(1.264 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T10:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.080 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.7 AS Decimal(10, 1)), CAST(1.820 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T11:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.120 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(248.2 AS Decimal(10, 1)), CAST(1.146 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T11:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.130 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(92.4 AS Decimal(10, 1)), CAST(1.221 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T11:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.250 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.9 AS Decimal(10, 1)), CAST(0.779 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T11:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.250 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.2 AS Decimal(10, 1)), CAST(1.420 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T11:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.220 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(113.3 AS Decimal(10, 1)), CAST(1.340 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T11:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.260 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(34.1 AS Decimal(10, 1)), CAST(0.446 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T12:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.050 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(190.1 AS Decimal(10, 1)), CAST(0.505 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T12:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(8.910 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(81.4 AS Decimal(10, 1)), CAST(0.184 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T12:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(8.640 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(93.8 AS Decimal(10, 1)), CAST(0.046 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T12:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(8.350 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(93.9 AS Decimal(10, 1)), CAST(0.003 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T12:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(7.917 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(94.2 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T12:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(7.722 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(93.9 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T13:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(7.338 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(94.2 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T13:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(6.988 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(262.4 AS Decimal(10, 1)), CAST(0.145 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T13:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(6.577 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(172.4 AS Decimal(10, 1)), CAST(0.354 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T13:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(6.310 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(172.7 AS Decimal(10, 1)), CAST(0.033 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T13:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(5.861 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(219.1 AS Decimal(10, 1)), CAST(0.196 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T13:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(5.576 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(270.4 AS Decimal(10, 1)), CAST(0.069 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T14:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(5.239 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(270.7 AS Decimal(10, 1)), CAST(0.220 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T14:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(5.098 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.269 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T14:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(4.676 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(267.8 AS Decimal(10, 1)), CAST(0.433 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T14:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(4.449 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(311.6 AS Decimal(10, 1)), CAST(0.324 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T14:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(4.123 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(311.6 AS Decimal(10, 1)), CAST(0.141 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T14:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(3.955 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(311.4 AS Decimal(10, 1)), CAST(0.194 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T15:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(3.632 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(297.8 AS Decimal(10, 1)), CAST(0.214 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T15:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(3.362 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(293.4 AS Decimal(10, 1)), CAST(0.524 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T15:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.292 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(267.6 AS Decimal(10, 1)), CAST(0.261 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T15:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.292 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(287.5 AS Decimal(10, 1)), CAST(0.219 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T15:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.306 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(270.1 AS Decimal(10, 1)), CAST(0.801 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T15:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.546 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(246.8 AS Decimal(10, 1)), CAST(0.153 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T16:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.618 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(246.7 AS Decimal(10, 1)), CAST(0.010 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T16:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.730 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(280.6 AS Decimal(10, 1)), CAST(0.563 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T16:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.829 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(298.8 AS Decimal(10, 1)), CAST(0.358 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T16:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.968 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(334.5 AS Decimal(10, 1)), CAST(0.291 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T16:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.235 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(313.6 AS Decimal(10, 1)), CAST(0.188 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T16:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.294 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(309.8 AS Decimal(10, 1)), CAST(0.926 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T17:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.435 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(269.9 AS Decimal(10, 1)), CAST(0.436 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T17:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.435 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(286.2 AS Decimal(10, 1)), CAST(0.425 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T17:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.409 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(258.6 AS Decimal(10, 1)), CAST(0.286 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T17:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.534 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(292.8 AS Decimal(10, 1)), CAST(0.825 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T17:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.491 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(295.9 AS Decimal(10, 1)), CAST(0.265 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T17:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.590 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(281.6 AS Decimal(10, 1)), CAST(0.762 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T18:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.646 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(321.0 AS Decimal(10, 1)), CAST(0.300 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T18:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.689 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(298.8 AS Decimal(10, 1)), CAST(0.112 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T18:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.620 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(298.7 AS Decimal(10, 1)), CAST(0.057 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T18:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.590 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(289.2 AS Decimal(10, 1)), CAST(0.608 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T18:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(4.110 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(315.0 AS Decimal(10, 1)), CAST(0.559 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T18:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.661 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(265.8 AS Decimal(10, 1)), CAST(0.651 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T19:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(3.194 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(257.8 AS Decimal(10, 1)), CAST(0.189 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T19:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(2.884 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(293.2 AS Decimal(10, 1)), CAST(0.551 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T19:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(2.571 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(280.2 AS Decimal(10, 1)), CAST(0.707 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T19:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.291 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(308.8 AS Decimal(10, 1)), CAST(0.357 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T19:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.318 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(82.0 AS Decimal(10, 1)), CAST(0.204 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T19:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.123 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(56.0 AS Decimal(10, 1)), CAST(0.169 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T20:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.955 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(44.3 AS Decimal(10, 1)), CAST(0.237 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T20:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.741 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(350.8 AS Decimal(10, 1)), CAST(0.284 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T20:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.629 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(313.3 AS Decimal(10, 1)), CAST(0.433 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T20:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.458 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(214.0 AS Decimal(10, 1)), CAST(0.398 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T20:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.388 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(237.4 AS Decimal(10, 1)), CAST(0.283 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T20:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.431 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(148.4 AS Decimal(10, 1)), CAST(0.363 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T21:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.629 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(271.8 AS Decimal(10, 1)), CAST(0.378 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T21:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.332 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(258.1 AS Decimal(10, 1)), CAST(0.129 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T21:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.076 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(18.9 AS Decimal(10, 1)), CAST(0.349 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T21:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.089 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(243.5 AS Decimal(10, 1)), CAST(0.257 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T21:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.838 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(266.7 AS Decimal(10, 1)), CAST(0.195 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T21:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.881 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(160.4 AS Decimal(10, 1)), CAST(0.234 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T22:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.822 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.232 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T22:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.726 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(45.8 AS Decimal(10, 1)), CAST(0.108 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T22:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.881 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(280.5 AS Decimal(10, 1)), CAST(0.379 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T22:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.670 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(273.4 AS Decimal(10, 1)), CAST(0.197 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T22:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(314.4 AS Decimal(10, 1)), CAST(0.389 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T22:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.726 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(215.7 AS Decimal(10, 1)), CAST(0.752 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T23:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.614 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(251.0 AS Decimal(10, 1)), CAST(0.338 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T23:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.164 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(7.8 AS Decimal(10, 1)), CAST(0.396 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T23:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.076 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(59.5 AS Decimal(10, 1)), CAST(0.141 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T23:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.993 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(267.9 AS Decimal(10, 1)), CAST(0.051 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T23:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.753 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(292.4 AS Decimal(10, 1)), CAST(0.171 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-18T23:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.670 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(278.6 AS Decimal(10, 1)), CAST(0.278 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T00:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.627 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(239.6 AS Decimal(10, 1)), CAST(0.294 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T00:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.753 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(235.2 AS Decimal(10, 1)), CAST(0.172 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T00:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.822 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(306.0 AS Decimal(10, 1)), CAST(0.505 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T00:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.881 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(25.8 AS Decimal(10, 1)), CAST(0.388 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T00:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.207 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.7 AS Decimal(10, 1)), CAST(0.416 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T00:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.089 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(270.3 AS Decimal(10, 1)), CAST(0.075 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T01:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.740 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(260.1 AS Decimal(10, 1)), CAST(0.529 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T01:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.710 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(268.0 AS Decimal(10, 1)), CAST(0.133 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T01:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.697 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(234.8 AS Decimal(10, 1)), CAST(0.184 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T01:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.766 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(185.3 AS Decimal(10, 1)), CAST(0.411 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T01:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.838 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(256.5 AS Decimal(10, 1)), CAST(0.230 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T01:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.740 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(260.4 AS Decimal(10, 1)), CAST(0.463 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T02:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.598 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(319.9 AS Decimal(10, 1)), CAST(0.376 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T02:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.542 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(323.3 AS Decimal(10, 1)), CAST(0.771 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T02:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.515 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(339.9 AS Decimal(10, 1)), CAST(0.140 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T02:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.173 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.8 AS Decimal(10, 1)), CAST(0.394 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T02:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.598 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.7 AS Decimal(10, 1)), CAST(0.269 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T02:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.529 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(280.9 AS Decimal(10, 1)), CAST(0.283 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T03:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.387 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(286.8 AS Decimal(10, 1)), CAST(0.666 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T03:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.286 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(311.6 AS Decimal(10, 1)), CAST(0.329 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T03:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.061 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(287.9 AS Decimal(10, 1)), CAST(0.646 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T03:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.191 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(264.7 AS Decimal(10, 1)), CAST(0.487 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T03:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.261 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(281.3 AS Decimal(10, 1)), CAST(0.325 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T03:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(325.8 AS Decimal(10, 1)), CAST(0.863 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T04:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.501 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(289.9 AS Decimal(10, 1)), CAST(0.563 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T04:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.231 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(300.3 AS Decimal(10, 1)), CAST(0.516 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T04:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.330 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(257.4 AS Decimal(10, 1)), CAST(0.593 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T04:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.330 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(12.5 AS Decimal(10, 1)), CAST(0.231 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T04:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.344 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(278.2 AS Decimal(10, 1)), CAST(0.375 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T04:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.531 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(305.2 AS Decimal(10, 1)), CAST(0.294 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T05:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.613 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(6.7 AS Decimal(10, 1)), CAST(0.369 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T05:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.613 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(248.2 AS Decimal(10, 1)), CAST(0.313 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T05:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.474 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(338.5 AS Decimal(10, 1)), CAST(0.201 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T05:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.429 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(291.1 AS Decimal(10, 1)), CAST(0.415 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T05:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.416 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(282.0 AS Decimal(10, 1)), CAST(0.644 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T05:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.205 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(321.5 AS Decimal(10, 1)), CAST(0.399 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T06:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.501 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(304.2 AS Decimal(10, 1)), CAST(0.481 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T06:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(287.7 AS Decimal(10, 1)), CAST(0.528 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T06:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(-0.106 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(278.5 AS Decimal(10, 1)), CAST(0.464 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T06:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.147 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(297.9 AS Decimal(10, 1)), CAST(0.563 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T06:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(336.8 AS Decimal(10, 1)), CAST(0.122 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T06:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.387 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(286.9 AS Decimal(10, 1)), CAST(0.571 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T07:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(0.641 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(251.1 AS Decimal(10, 1)), CAST(0.587 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T07:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.164 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(347.8 AS Decimal(10, 1)), CAST(0.668 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T07:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(1.642 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(12.3 AS Decimal(10, 1)), CAST(0.573 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T07:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(2.473 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(245.6 AS Decimal(10, 1)), CAST(0.207 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T07:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(3.039 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(341.8 AS Decimal(10, 1)), CAST(0.007 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T07:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(3.688 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(342.0 AS Decimal(10, 1)), CAST(0.000 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T08:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(4.222 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(121.1 AS Decimal(10, 1)), CAST(0.291 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T08:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(5.648 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(132.2 AS Decimal(10, 1)), CAST(1.254 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T08:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(6.155 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.1 AS Decimal(10, 1)), CAST(0.984 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T08:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(6.465 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(142.4 AS Decimal(10, 1)), CAST(0.790 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T08:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(6.903 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(196.2 AS Decimal(10, 1)), CAST(0.824 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T08:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(7.186 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(160.4 AS Decimal(10, 1)), CAST(0.153 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T09:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(7.399 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(92.4 AS Decimal(10, 1)), CAST(0.612 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T09:10:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(7.439 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.5 AS Decimal(10, 1)), CAST(0.546 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T09:20:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(7.779 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(353.6 AS Decimal(10, 1)), CAST(0.069 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T09:30:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(8.120 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(131.9 AS Decimal(10, 1)), CAST(0.121 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T09:40:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(8.600 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.1 AS Decimal(10, 1)), CAST(0.332 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T09:50:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(9.050 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(256.3 AS Decimal(10, 1)), CAST(0.321 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T10:00:00.000' AS DateTime), CAST(938.00 AS Decimal(10, 2)), CAST(9.840 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(120.5 AS Decimal(10, 1)), CAST(0.181 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T10:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(9.870 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.3 AS Decimal(10, 1)), CAST(0.487 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T10:20:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(9.310 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.5 AS Decimal(10, 1)), CAST(1.762 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T10:30:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(9.440 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(103.1 AS Decimal(10, 1)), CAST(1.818 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T10:40:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(9.250 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(149.9 AS Decimal(10, 1)), CAST(2.019 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T10:50:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(9.340 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.3 AS Decimal(10, 1)), CAST(2.114 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T11:00:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(9.760 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.6 AS Decimal(10, 1)), CAST(1.597 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T11:10:00.000' AS DateTime), CAST(937.00 AS Decimal(10, 2)), CAST(9.670 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.5 AS Decimal(10, 1)), CAST(2.157 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T11:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.710 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.6 AS Decimal(10, 1)), CAST(2.051 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T11:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(121.3 AS Decimal(10, 1)), CAST(1.834 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T11:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.470 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(114.9 AS Decimal(10, 1)), CAST(2.175 AS Decimal(10, 3)), CAST(3.430 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T11:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.130 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(107.5 AS Decimal(10, 1)), CAST(2.428 AS Decimal(10, 3)), CAST(2.744 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T12:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.080 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.2 AS Decimal(10, 1)), CAST(2.015 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T12:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(8.740 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(89.9 AS Decimal(10, 1)), CAST(1.724 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T12:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(8.810 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.8 AS Decimal(10, 1)), CAST(1.411 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T12:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.020 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(115.8 AS Decimal(10, 1)), CAST(1.153 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T12:40:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.300 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(86.1 AS Decimal(10, 1)), CAST(0.832 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T12:50:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.390 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(141.0 AS Decimal(10, 1)), CAST(0.954 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T13:00:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(64.5 AS Decimal(10, 1)), CAST(0.894 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T13:10:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.460 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.7 AS Decimal(10, 1)), CAST(1.481 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T13:20:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.540 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(187.7 AS Decimal(10, 1)), CAST(1.447 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T13:30:00.000' AS DateTime), CAST(936.00 AS Decimal(10, 2)), CAST(9.520 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(97.1 AS Decimal(10, 1)), CAST(1.138 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T13:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.370 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.0 AS Decimal(10, 1)), CAST(1.561 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T13:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.310 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(111.6 AS Decimal(10, 1)), CAST(1.691 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T14:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.190 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.7 AS Decimal(10, 1)), CAST(1.601 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T14:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.120 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(93.9 AS Decimal(10, 1)), CAST(1.484 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T14:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.080 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(181.2 AS Decimal(10, 1)), CAST(1.032 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T14:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.190 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(121.3 AS Decimal(10, 1)), CAST(1.171 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T14:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.010 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(80.3 AS Decimal(10, 1)), CAST(0.503 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T14:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(8.990 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(71.0 AS Decimal(10, 1)), CAST(0.923 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T15:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.010 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.1 AS Decimal(10, 1)), CAST(1.180 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T15:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(9.160 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(70.9 AS Decimal(10, 1)), CAST(1.711 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T15:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(8.790 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(71.5 AS Decimal(10, 1)), CAST(0.670 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T15:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(7.973 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(268.0 AS Decimal(10, 1)), CAST(1.128 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T15:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(7.792 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(344.1 AS Decimal(10, 1)), CAST(1.029 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T15:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(8.000 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(87.6 AS Decimal(10, 1)), CAST(0.774 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T16:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(7.186 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.4 AS Decimal(10, 1)), CAST(0.912 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T16:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(6.622 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.1 AS Decimal(10, 1)), CAST(0.418 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T16:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(6.240 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(49.6 AS Decimal(10, 1)), CAST(0.586 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T16:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(6.029 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(156.9 AS Decimal(10, 1)), CAST(0.493 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T16:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.562 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(41.1 AS Decimal(10, 1)), CAST(0.576 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T16:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.450 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(35.6 AS Decimal(10, 1)), CAST(0.711 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T17:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.381 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(137.5 AS Decimal(10, 1)), CAST(0.501 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T17:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.239 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(322.7 AS Decimal(10, 1)), CAST(0.470 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T17:20:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.282 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(275.9 AS Decimal(10, 1)), CAST(0.266 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T17:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.367 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(266.1 AS Decimal(10, 1)), CAST(0.541 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T17:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.592 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(36.5 AS Decimal(10, 1)), CAST(0.555 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T17:50:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.535 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(305.8 AS Decimal(10, 1)), CAST(0.159 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T18:00:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.549 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(272.8 AS Decimal(10, 1)), CAST(0.567 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T18:10:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.648 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(184.8 AS Decimal(10, 1)), CAST(0.112 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T18:20:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(5.931 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(105.1 AS Decimal(10, 1)), CAST(0.280 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T18:30:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(5.845 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(286.9 AS Decimal(10, 1)), CAST(0.754 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T18:40:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(5.973 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(138.7 AS Decimal(10, 1)), CAST(0.315 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T18:50:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.184 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(306.1 AS Decimal(10, 1)), CAST(0.660 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T19:00:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.198 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(1.6 AS Decimal(10, 1)), CAST(0.795 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T19:10:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.254 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(310.8 AS Decimal(10, 1)), CAST(0.423 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T19:20:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.128 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(287.7 AS Decimal(10, 1)), CAST(0.751 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T19:30:00.000' AS DateTime), CAST(935.00 AS Decimal(10, 2)), CAST(6.171 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(256.8 AS Decimal(10, 1)), CAST(0.368 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T19:40:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.240 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(42.7 AS Decimal(10, 1)), CAST(0.520 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T19:50:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.198 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(271.6 AS Decimal(10, 1)), CAST(0.706 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T20:00:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.254 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(48.0 AS Decimal(10, 1)), CAST(0.680 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T20:10:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.310 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(41.7 AS Decimal(10, 1)), CAST(0.510 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T20:20:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.254 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(21.2 AS Decimal(10, 1)), CAST(0.584 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T20:30:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.310 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(233.0 AS Decimal(10, 1)), CAST(0.696 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T20:40:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.310 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(218.7 AS Decimal(10, 1)), CAST(0.553 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T20:50:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.395 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(56.3 AS Decimal(10, 1)), CAST(1.206 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T21:00:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.438 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(319.7 AS Decimal(10, 1)), CAST(0.762 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T21:10:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.507 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(304.6 AS Decimal(10, 1)), CAST(0.388 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T21:20:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.438 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(239.2 AS Decimal(10, 1)), CAST(0.479 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T21:30:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.564 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(347.3 AS Decimal(10, 1)), CAST(0.511 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T21:40:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.609 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(17.7 AS Decimal(10, 1)), CAST(0.860 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T21:50:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.622 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(224.8 AS Decimal(10, 1)), CAST(0.578 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T22:00:00.000' AS DateTime), CAST(934.00 AS Decimal(10, 2)), CAST(6.577 AS Decimal(10, 3)), CAST(1.30 AS Decimal(10, 2)), CAST(35.9 AS Decimal(10, 1)), CAST(0.351 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T22:10:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(6.590 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(257.1 AS Decimal(10, 1)), CAST(0.381 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T22:20:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(6.876 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(265.7 AS Decimal(10, 1)), CAST(0.574 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T22:30:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(6.863 AS Decimal(10, 3)), CAST(1.30 AS Decimal(10, 2)), CAST(170.0 AS Decimal(10, 1)), CAST(0.348 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T22:40:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(6.791 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(217.6 AS Decimal(10, 1)), CAST(0.274 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T22:50:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(6.734 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(117.1 AS Decimal(10, 1)), CAST(0.590 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T23:00:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(6.847 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(55.7 AS Decimal(10, 1)), CAST(1.270 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T23:10:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(6.863 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(236.5 AS Decimal(10, 1)), CAST(0.457 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T23:20:00.000' AS DateTime), CAST(933.00 AS Decimal(10, 2)), CAST(7.031 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(259.0 AS Decimal(10, 1)), CAST(0.739 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T23:30:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(6.833 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(273.1 AS Decimal(10, 1)), CAST(0.315 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T23:40:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(6.959 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(40.3 AS Decimal(10, 1)), CAST(0.951 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-19T23:50:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(7.058 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(24.4 AS Decimal(10, 1)), CAST(0.671 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T00:00:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(6.945 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(256.7 AS Decimal(10, 1)), CAST(0.461 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T00:10:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(6.959 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.834 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T00:20:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(6.959 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(23.7 AS Decimal(10, 1)), CAST(0.276 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T00:30:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(6.791 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(46.4 AS Decimal(10, 1)), CAST(0.750 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T00:40:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.777 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(48.1 AS Decimal(10, 1)), CAST(0.601 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T00:50:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.564 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.608 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T01:00:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.577 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(278.1 AS Decimal(10, 1)), CAST(0.696 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T01:10:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.353 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(25.2 AS Decimal(10, 1)), CAST(0.699 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T01:20:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.227 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(324.5 AS Decimal(10, 1)), CAST(1.080 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T01:30:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.267 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(0.1 AS Decimal(10, 1)), CAST(0.696 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T01:40:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.267 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(44.0 AS Decimal(10, 1)), CAST(0.964 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T01:50:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.777 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(43.2 AS Decimal(10, 1)), CAST(0.884 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T02:00:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(6.494 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(245.2 AS Decimal(10, 1)), CAST(0.549 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T02:10:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.297 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(45.6 AS Decimal(10, 1)), CAST(0.373 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T02:20:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.409 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(286.5 AS Decimal(10, 1)), CAST(0.915 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T02:30:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.494 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(21.6 AS Decimal(10, 1)), CAST(0.246 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T02:40:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.721 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(127.0 AS Decimal(10, 1)), CAST(0.842 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T02:50:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.590 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(244.0 AS Decimal(10, 1)), CAST(0.793 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T03:00:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.833 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(40.6 AS Decimal(10, 1)), CAST(1.154 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T03:10:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.777 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(289.7 AS Decimal(10, 1)), CAST(0.722 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T03:20:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(6.734 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(250.3 AS Decimal(10, 1)), CAST(0.797 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T03:30:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(6.932 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(183.8 AS Decimal(10, 1)), CAST(0.912 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T03:40:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(6.876 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(5.3 AS Decimal(10, 1)), CAST(0.575 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T03:50:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(6.889 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(332.4 AS Decimal(10, 1)), CAST(1.308 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T04:00:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(7.015 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.4 AS Decimal(10, 1)), CAST(0.800 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T04:10:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(6.919 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(82.3 AS Decimal(10, 1)), CAST(0.663 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T04:20:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(7.100 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(33.7 AS Decimal(10, 1)), CAST(0.650 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T04:30:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(6.932 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(296.1 AS Decimal(10, 1)), CAST(0.597 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T04:40:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(6.820 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(343.4 AS Decimal(10, 1)), CAST(0.570 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T04:50:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(6.945 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(5.6 AS Decimal(10, 1)), CAST(0.659 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T05:00:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(7.212 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(342.2 AS Decimal(10, 1)), CAST(1.390 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T05:10:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.469 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(136.9 AS Decimal(10, 1)), CAST(0.864 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T05:20:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.455 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(72.5 AS Decimal(10, 1)), CAST(0.964 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T05:30:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.512 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(116.7 AS Decimal(10, 1)), CAST(1.016 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T05:40:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.835 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(58.9 AS Decimal(10, 1)), CAST(1.117 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T05:50:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.947 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(346.7 AS Decimal(10, 1)), CAST(1.211 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T06:00:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.960 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(240.4 AS Decimal(10, 1)), CAST(0.870 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T06:10:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.877 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(52.1 AS Decimal(10, 1)), CAST(0.897 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T06:20:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.819 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(128.1 AS Decimal(10, 1)), CAST(0.422 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T06:30:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.917 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(183.0 AS Decimal(10, 1)), CAST(0.831 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T06:40:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.877 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(142.9 AS Decimal(10, 1)), CAST(0.905 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T06:50:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(7.933 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(161.9 AS Decimal(10, 1)), CAST(1.204 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T07:00:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(8.120 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(237.3 AS Decimal(10, 1)), CAST(0.759 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T07:10:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(8.230 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(172.0 AS Decimal(10, 1)), CAST(1.193 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T07:20:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(8.350 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(147.6 AS Decimal(10, 1)), CAST(1.864 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T07:30:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(8.440 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(105.2 AS Decimal(10, 1)), CAST(2.234 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T07:40:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(8.790 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(96.4 AS Decimal(10, 1)), CAST(2.191 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T07:50:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(8.820 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(105.6 AS Decimal(10, 1)), CAST(0.573 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T08:00:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(8.760 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(120.2 AS Decimal(10, 1)), CAST(1.279 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T08:10:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(8.910 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(79.6 AS Decimal(10, 1)), CAST(1.272 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T08:20:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(9.080 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(89.4 AS Decimal(10, 1)), CAST(1.244 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T08:30:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(9.160 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(67.7 AS Decimal(10, 1)), CAST(0.929 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T08:40:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(9.400 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(269.8 AS Decimal(10, 1)), CAST(0.732 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T08:50:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(9.620 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(58.7 AS Decimal(10, 1)), CAST(0.582 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T09:00:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(9.520 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(92.9 AS Decimal(10, 1)), CAST(0.834 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T09:10:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.650 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(60.1 AS Decimal(10, 1)), CAST(1.101 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T09:20:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.770 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(91.3 AS Decimal(10, 1)), CAST(1.202 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T09:30:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.780 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.3 AS Decimal(10, 1)), CAST(2.467 AS Decimal(10, 3)), CAST(3.332 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T09:40:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.710 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.7 AS Decimal(10, 1)), CAST(3.163 AS Decimal(10, 3)), CAST(3.822 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T09:50:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.800 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(143.9 AS Decimal(10, 1)), CAST(1.715 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T10:00:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.730 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(133.7 AS Decimal(10, 1)), CAST(1.948 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T10:10:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.850 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(98.8 AS Decimal(10, 1)), CAST(1.753 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T10:20:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(9.950 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(101.7 AS Decimal(10, 1)), CAST(1.391 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T10:30:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(9.990 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(151.6 AS Decimal(10, 1)), CAST(1.227 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T10:40:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(10.090 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(317.3 AS Decimal(10, 1)), CAST(0.673 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T10:50:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(10.040 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(120.8 AS Decimal(10, 1)), CAST(1.007 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T11:00:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(10.120 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(47.0 AS Decimal(10, 1)), CAST(1.517 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T11:10:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.320 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(23.1 AS Decimal(10, 1)), CAST(1.027 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T11:20:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.400 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(48.0 AS Decimal(10, 1)), CAST(0.849 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T11:30:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.390 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(277.8 AS Decimal(10, 1)), CAST(0.456 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T11:40:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.430 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(187.9 AS Decimal(10, 1)), CAST(0.625 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T11:50:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.530 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(173.3 AS Decimal(10, 1)), CAST(0.615 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T12:00:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.560 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(182.7 AS Decimal(10, 1)), CAST(0.803 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T12:10:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(10.680 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(121.3 AS Decimal(10, 1)), CAST(1.334 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T12:20:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.600 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(15.7 AS Decimal(10, 1)), CAST(0.952 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T12:30:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(10.520 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(315.4 AS Decimal(10, 1)), CAST(0.678 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T12:40:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(10.530 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(126.1 AS Decimal(10, 1)), CAST(0.482 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T12:50:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(10.490 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(30.4 AS Decimal(10, 1)), CAST(0.567 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T13:00:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(10.500 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(336.6 AS Decimal(10, 1)), CAST(0.291 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T13:10:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(10.420 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(34.1 AS Decimal(10, 1)), CAST(0.571 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T13:20:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(10.390 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(11.2 AS Decimal(10, 1)), CAST(0.104 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T13:30:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(10.360 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(109.8 AS Decimal(10, 1)), CAST(0.521 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T13:40:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(10.200 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(280.3 AS Decimal(10, 1)), CAST(0.358 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T13:50:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(10.260 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(56.7 AS Decimal(10, 1)), CAST(0.484 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T14:00:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(10.160 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(42.1 AS Decimal(10, 1)), CAST(0.432 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T14:10:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(10.160 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(341.1 AS Decimal(10, 1)), CAST(0.556 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T14:20:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(10.080 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(181.9 AS Decimal(10, 1)), CAST(0.620 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T14:30:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(10.090 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(25.9 AS Decimal(10, 1)), CAST(0.623 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T14:40:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.970 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(116.5 AS Decimal(10, 1)), CAST(0.367 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T14:50:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.890 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(91.6 AS Decimal(10, 1)), CAST(0.617 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T15:00:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.910 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(312.3 AS Decimal(10, 1)), CAST(0.470 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T15:10:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.780 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(244.8 AS Decimal(10, 1)), CAST(0.431 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T15:20:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.710 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(156.8 AS Decimal(10, 1)), CAST(0.410 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T15:30:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.680 AS Decimal(10, 3)), CAST(0.80 AS Decimal(10, 2)), CAST(169.0 AS Decimal(10, 1)), CAST(0.075 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T15:40:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.780 AS Decimal(10, 3)), CAST(0.80 AS Decimal(10, 2)), CAST(225.1 AS Decimal(10, 1)), CAST(0.686 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T15:50:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.700 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(37.9 AS Decimal(10, 1)), CAST(0.382 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T16:00:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.640 AS Decimal(10, 3)), CAST(1.20 AS Decimal(10, 2)), CAST(352.7 AS Decimal(10, 1)), CAST(0.395 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T16:10:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.670 AS Decimal(10, 3)), CAST(1.00 AS Decimal(10, 2)), CAST(287.7 AS Decimal(10, 1)), CAST(1.012 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T16:20:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.620 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(188.3 AS Decimal(10, 1)), CAST(0.572 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T16:30:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.480 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(81.5 AS Decimal(10, 1)), CAST(0.325 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T16:40:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(9.600 AS Decimal(10, 3)), CAST(0.80 AS Decimal(10, 2)), CAST(303.7 AS Decimal(10, 1)), CAST(0.629 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T16:50:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(9.460 AS Decimal(10, 3)), CAST(1.00 AS Decimal(10, 2)), CAST(102.1 AS Decimal(10, 1)), CAST(0.522 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T17:00:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(9.470 AS Decimal(10, 3)), CAST(1.20 AS Decimal(10, 2)), CAST(237.3 AS Decimal(10, 1)), CAST(0.778 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T17:10:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(9.410 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(137.4 AS Decimal(10, 1)), CAST(0.571 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T17:20:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(9.370 AS Decimal(10, 3)), CAST(1.30 AS Decimal(10, 2)), CAST(210.7 AS Decimal(10, 1)), CAST(0.158 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T17:30:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(9.330 AS Decimal(10, 3)), CAST(1.20 AS Decimal(10, 2)), CAST(265.1 AS Decimal(10, 1)), CAST(0.560 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T17:40:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(9.340 AS Decimal(10, 3)), CAST(0.80 AS Decimal(10, 2)), CAST(167.7 AS Decimal(10, 1)), CAST(0.665 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T17:50:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.300 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(41.2 AS Decimal(10, 1)), CAST(0.610 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T18:00:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.370 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(234.3 AS Decimal(10, 1)), CAST(0.784 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T18:10:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.330 AS Decimal(10, 3)), CAST(1.70 AS Decimal(10, 2)), CAST(354.4 AS Decimal(10, 1)), CAST(0.876 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T18:20:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.360 AS Decimal(10, 3)), CAST(1.20 AS Decimal(10, 2)), CAST(46.8 AS Decimal(10, 1)), CAST(0.845 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T18:30:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.310 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(92.6 AS Decimal(10, 1)), CAST(0.409 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T18:40:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.130 AS Decimal(10, 3)), CAST(1.20 AS Decimal(10, 2)), CAST(28.2 AS Decimal(10, 1)), CAST(0.641 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T18:50:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.120 AS Decimal(10, 3)), CAST(1.00 AS Decimal(10, 2)), CAST(165.2 AS Decimal(10, 1)), CAST(0.751 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T19:00:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.120 AS Decimal(10, 3)), CAST(1.00 AS Decimal(10, 2)), CAST(329.0 AS Decimal(10, 1)), CAST(0.859 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T19:10:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(9.100 AS Decimal(10, 3)), CAST(1.20 AS Decimal(10, 2)), CAST(186.2 AS Decimal(10, 1)), CAST(1.092 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T19:20:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(9.190 AS Decimal(10, 3)), CAST(1.10 AS Decimal(10, 2)), CAST(317.7 AS Decimal(10, 1)), CAST(0.666 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T19:30:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(9.100 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(55.0 AS Decimal(10, 1)), CAST(0.406 AS Decimal(10, 3)), CAST(0.196 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T19:40:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(9.160 AS Decimal(10, 3)), CAST(1.00 AS Decimal(10, 2)), CAST(270.6 AS Decimal(10, 1)), CAST(1.063 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T19:50:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(9.130 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(50.4 AS Decimal(10, 1)), CAST(1.106 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T20:00:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(9.100 AS Decimal(10, 3)), CAST(0.90 AS Decimal(10, 2)), CAST(179.2 AS Decimal(10, 1)), CAST(0.724 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T20:10:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(9.100 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(58.7 AS Decimal(10, 1)), CAST(0.994 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T20:20:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(9.080 AS Decimal(10, 3)), CAST(0.80 AS Decimal(10, 2)), CAST(345.6 AS Decimal(10, 1)), CAST(0.947 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T20:30:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(8.960 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(151.6 AS Decimal(10, 1)), CAST(0.681 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T20:40:00.000' AS DateTime), CAST(917.00 AS Decimal(10, 2)), CAST(8.910 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(24.7 AS Decimal(10, 1)), CAST(0.667 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T20:50:00.000' AS DateTime), CAST(917.00 AS Decimal(10, 2)), CAST(8.960 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(298.2 AS Decimal(10, 1)), CAST(1.046 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T21:00:00.000' AS DateTime), CAST(917.00 AS Decimal(10, 2)), CAST(9.010 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(199.6 AS Decimal(10, 1)), CAST(0.840 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T21:10:00.000' AS DateTime), CAST(917.00 AS Decimal(10, 2)), CAST(8.920 AS Decimal(10, 3)), CAST(0.50 AS Decimal(10, 2)), CAST(165.6 AS Decimal(10, 1)), CAST(0.765 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T21:20:00.000' AS DateTime), CAST(917.00 AS Decimal(10, 2)), CAST(8.820 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(335.7 AS Decimal(10, 1)), CAST(0.448 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T21:30:00.000' AS DateTime), CAST(917.00 AS Decimal(10, 2)), CAST(8.920 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(129.9 AS Decimal(10, 1)), CAST(0.934 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T21:40:00.000' AS DateTime), CAST(916.00 AS Decimal(10, 2)), CAST(8.950 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(24.0 AS Decimal(10, 1)), CAST(1.241 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T21:50:00.000' AS DateTime), CAST(916.00 AS Decimal(10, 2)), CAST(8.890 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(255.3 AS Decimal(10, 1)), CAST(0.609 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T22:00:00.000' AS DateTime), CAST(916.00 AS Decimal(10, 2)), CAST(8.880 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(235.9 AS Decimal(10, 1)), CAST(1.233 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T22:10:00.000' AS DateTime), CAST(916.00 AS Decimal(10, 2)), CAST(8.980 AS Decimal(10, 3)), CAST(1.10 AS Decimal(10, 2)), CAST(165.5 AS Decimal(10, 1)), CAST(0.959 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T22:20:00.000' AS DateTime), CAST(916.00 AS Decimal(10, 2)), CAST(8.910 AS Decimal(10, 3)), CAST(0.40 AS Decimal(10, 2)), CAST(347.9 AS Decimal(10, 1)), CAST(1.698 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T22:30:00.000' AS DateTime), CAST(916.00 AS Decimal(10, 2)), CAST(8.740 AS Decimal(10, 3)), CAST(1.30 AS Decimal(10, 2)), CAST(331.4 AS Decimal(10, 1)), CAST(3.905 AS Decimal(10, 3)), CAST(5.586 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T22:40:00.000' AS DateTime), CAST(917.00 AS Decimal(10, 2)), CAST(8.160 AS Decimal(10, 3)), CAST(1.90 AS Decimal(10, 2)), CAST(4.8 AS Decimal(10, 1)), CAST(7.101 AS Decimal(10, 3)), CAST(9.800 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T22:50:00.000' AS DateTime), CAST(918.00 AS Decimal(10, 2)), CAST(7.693 AS Decimal(10, 3)), CAST(1.20 AS Decimal(10, 2)), CAST(70.7 AS Decimal(10, 1)), CAST(7.979 AS Decimal(10, 3)), CAST(7.154 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T23:00:00.000' AS DateTime), CAST(919.00 AS Decimal(10, 2)), CAST(5.931 AS Decimal(10, 3)), CAST(1.60 AS Decimal(10, 2)), CAST(129.4 AS Decimal(10, 1)), CAST(8.160 AS Decimal(10, 3)), CAST(2.548 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T23:10:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(4.379 AS Decimal(10, 3)), CAST(2.40 AS Decimal(10, 2)), CAST(3.9 AS Decimal(10, 1)), CAST(3.692 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T23:20:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(3.842 AS Decimal(10, 3)), CAST(0.70 AS Decimal(10, 2)), CAST(267.5 AS Decimal(10, 1)), CAST(3.850 AS Decimal(10, 3)), CAST(4.116 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T23:30:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(3.757 AS Decimal(10, 3)), CAST(0.30 AS Decimal(10, 2)), CAST(126.8 AS Decimal(10, 1)), CAST(5.841 AS Decimal(10, 3)), CAST(4.998 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T23:40:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(3.506 AS Decimal(10, 3)), CAST(0.60 AS Decimal(10, 2)), CAST(352.4 AS Decimal(10, 1)), CAST(2.812 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-20T23:50:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(4.633 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(277.7 AS Decimal(10, 1)), CAST(5.119 AS Decimal(10, 3)), CAST(10.390 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T00:00:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(4.547 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(281.2 AS Decimal(10, 1)), CAST(6.997 AS Decimal(10, 3)), CAST(9.410 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T00:10:00.000' AS DateTime), CAST(920.00 AS Decimal(10, 2)), CAST(4.336 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(328.2 AS Decimal(10, 1)), CAST(7.217 AS Decimal(10, 3)), CAST(5.586 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T00:20:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(4.139 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(305.0 AS Decimal(10, 1)), CAST(5.223 AS Decimal(10, 3)), CAST(6.272 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T00:30:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(4.577 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(293.7 AS Decimal(10, 1)), CAST(4.278 AS Decimal(10, 3)), CAST(4.312 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T00:40:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(4.040 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(296.7 AS Decimal(10, 1)), CAST(3.613 AS Decimal(10, 3)), CAST(2.842 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T00:50:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(3.813 AS Decimal(10, 3)), CAST(0.20 AS Decimal(10, 2)), CAST(328.2 AS Decimal(10, 1)), CAST(1.641 AS Decimal(10, 3)), CAST(3.234 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T01:00:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(4.096 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(159.7 AS Decimal(10, 1)), CAST(1.856 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T01:10:00.000' AS DateTime), CAST(921.00 AS Decimal(10, 2)), CAST(4.053 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(229.7 AS Decimal(10, 1)), CAST(1.148 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T01:20:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(3.872 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(331.0 AS Decimal(10, 1)), CAST(1.056 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T01:30:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(3.899 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(219.5 AS Decimal(10, 1)), CAST(1.266 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T01:40:00.000' AS DateTime), CAST(922.00 AS Decimal(10, 2)), CAST(3.955 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(145.3 AS Decimal(10, 1)), CAST(2.318 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T01:50:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(3.575 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(67.1 AS Decimal(10, 1)), CAST(2.220 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T02:00:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(3.632 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(93.9 AS Decimal(10, 1)), CAST(2.352 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T02:10:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(3.418 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(68.6 AS Decimal(10, 1)), CAST(2.010 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T02:20:00.000' AS DateTime), CAST(923.00 AS Decimal(10, 2)), CAST(3.348 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(168.0 AS Decimal(10, 1)), CAST(1.924 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T02:30:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(3.124 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(121.4 AS Decimal(10, 1)), CAST(2.295 AS Decimal(10, 3)), CAST(2.842 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T02:40:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(3.124 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(99.7 AS Decimal(10, 1)), CAST(1.897 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T02:50:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(3.009 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(106.4 AS Decimal(10, 1)), CAST(1.737 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T03:00:00.000' AS DateTime), CAST(924.00 AS Decimal(10, 2)), CAST(2.927 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(145.9 AS Decimal(10, 1)), CAST(1.671 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T03:10:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(2.601 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.2 AS Decimal(10, 1)), CAST(2.105 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T03:20:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(2.318 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(188.2 AS Decimal(10, 1)), CAST(2.055 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T03:30:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(2.179 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(176.3 AS Decimal(10, 1)), CAST(1.703 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T03:40:00.000' AS DateTime), CAST(925.00 AS Decimal(10, 2)), CAST(1.981 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(131.2 AS Decimal(10, 1)), CAST(1.833 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T03:50:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(2.080 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(114.9 AS Decimal(10, 1)), CAST(1.836 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T04:00:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(1.797 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(110.3 AS Decimal(10, 1)), CAST(2.109 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T04:10:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(1.570 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(95.2 AS Decimal(10, 1)), CAST(1.474 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T04:20:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(1.362 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(92.3 AS Decimal(10, 1)), CAST(1.804 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T04:30:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(1.121 AS Decimal(10, 3)), CAST(0.10 AS Decimal(10, 2)), CAST(181.4 AS Decimal(10, 1)), CAST(1.009 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T04:40:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(0.838 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.4 AS Decimal(10, 1)), CAST(1.613 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T04:50:00.000' AS DateTime), CAST(926.00 AS Decimal(10, 2)), CAST(0.654 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(122.1 AS Decimal(10, 1)), CAST(1.212 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T05:00:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(0.697 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.1 AS Decimal(10, 1)), CAST(0.902 AS Decimal(10, 3)), CAST(0.980 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T05:10:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(0.726 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.2 AS Decimal(10, 1)), CAST(1.218 AS Decimal(10, 3)), CAST(3.332 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T05:20:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(0.654 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(140.6 AS Decimal(10, 1)), CAST(1.572 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T05:30:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(0.796 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(157.0 AS Decimal(10, 1)), CAST(0.570 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T05:40:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(0.710 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(57.6 AS Decimal(10, 1)), CAST(0.538 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T05:50:00.000' AS DateTime), CAST(927.00 AS Decimal(10, 2)), CAST(0.753 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.2 AS Decimal(10, 1)), CAST(0.510 AS Decimal(10, 3)), CAST(0.882 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T06:00:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(0.921 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(185.6 AS Decimal(10, 1)), CAST(0.382 AS Decimal(10, 3)), CAST(0.098 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T06:10:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(0.894 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(65.2 AS Decimal(10, 1)), CAST(0.438 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T06:20:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(0.908 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(152.9 AS Decimal(10, 1)), CAST(0.273 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T06:30:00.000' AS DateTime), CAST(928.00 AS Decimal(10, 2)), CAST(1.007 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(191.0 AS Decimal(10, 1)), CAST(1.009 AS Decimal(10, 3)), CAST(0.588 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T06:40:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(0.977 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(151.9 AS Decimal(10, 1)), CAST(1.585 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T06:50:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(0.881 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(172.7 AS Decimal(10, 1)), CAST(1.541 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T07:00:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(0.865 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(130.9 AS Decimal(10, 1)), CAST(1.952 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T07:10:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(0.740 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(120.3 AS Decimal(10, 1)), CAST(2.066 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T07:20:00.000' AS DateTime), CAST(929.00 AS Decimal(10, 2)), CAST(0.710 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(167.9 AS Decimal(10, 1)), CAST(1.809 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T07:30:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(0.782 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(112.7 AS Decimal(10, 1)), CAST(1.384 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T07:40:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(0.740 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.1 AS Decimal(10, 1)), CAST(1.451 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T07:50:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(0.809 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(110.0 AS Decimal(10, 1)), CAST(1.209 AS Decimal(10, 3)), CAST(1.568 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T08:00:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(0.921 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(117.7 AS Decimal(10, 1)), CAST(1.520 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T08:10:00.000' AS DateTime), CAST(930.00 AS Decimal(10, 2)), CAST(0.838 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.4 AS Decimal(10, 1)), CAST(1.548 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T08:20:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(0.921 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(119.4 AS Decimal(10, 1)), CAST(1.600 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T08:30:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(0.964 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(113.1 AS Decimal(10, 1)), CAST(1.596 AS Decimal(10, 3)), CAST(1.372 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T08:40:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.033 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(93.4 AS Decimal(10, 1)), CAST(1.681 AS Decimal(10, 3)), CAST(1.862 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T08:50:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.033 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(126.8 AS Decimal(10, 1)), CAST(1.862 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T09:00:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.247 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(135.8 AS Decimal(10, 1)), CAST(1.867 AS Decimal(10, 3)), CAST(1.666 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T09:10:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.191 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(150.1 AS Decimal(10, 1)), CAST(1.862 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T09:20:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.276 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(162.0 AS Decimal(10, 1)), CAST(1.693 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T09:30:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.514 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(149.8 AS Decimal(10, 1)), CAST(1.840 AS Decimal(10, 3)), CAST(1.960 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T09:40:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.514 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(171.3 AS Decimal(10, 1)), CAST(2.126 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T09:50:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.712 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(106.0 AS Decimal(10, 1)), CAST(2.025 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T10:00:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(1.840 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(116.6 AS Decimal(10, 1)), CAST(1.735 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T10:10:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.051 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.5 AS Decimal(10, 1)), CAST(2.009 AS Decimal(10, 3)), CAST(3.332 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T10:20:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.067 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(128.1 AS Decimal(10, 1)), CAST(2.810 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T10:30:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.011 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(124.8 AS Decimal(10, 1)), CAST(2.322 AS Decimal(10, 3)), CAST(2.842 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T10:40:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.051 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(176.5 AS Decimal(10, 1)), CAST(2.154 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T10:50:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.093 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(125.9 AS Decimal(10, 1)), CAST(2.304 AS Decimal(10, 3)), CAST(2.156 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T11:00:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.222 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(133.6 AS Decimal(10, 1)), CAST(1.978 AS Decimal(10, 3)), CAST(4.410 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T11:10:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.149 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(119.9 AS Decimal(10, 1)), CAST(2.392 AS Decimal(10, 3)), CAST(1.274 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T11:20:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.067 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(116.0 AS Decimal(10, 1)), CAST(2.172 AS Decimal(10, 3)), CAST(2.646 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T11:30:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.192 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(98.9 AS Decimal(10, 1)), CAST(1.960 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T11:40:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.179 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(116.7 AS Decimal(10, 1)), CAST(1.736 AS Decimal(10, 3)), CAST(2.352 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T11:50:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.179 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(167.9 AS Decimal(10, 1)), CAST(2.150 AS Decimal(10, 3)), CAST(3.430 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T12:00:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.206 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(135.6 AS Decimal(10, 1)), CAST(1.890 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T12:10:00.000' AS DateTime), CAST(931.00 AS Decimal(10, 2)), CAST(2.248 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(199.2 AS Decimal(10, 1)), CAST(1.752 AS Decimal(10, 3)), CAST(1.764 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T12:20:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.206 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(123.3 AS Decimal(10, 1)), CAST(1.778 AS Decimal(10, 3)), CAST(2.058 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T12:30:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.262 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(157.8 AS Decimal(10, 1)), CAST(1.805 AS Decimal(10, 3)), CAST(2.254 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T12:40:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.291 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(106.2 AS Decimal(10, 1)), CAST(1.796 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T12:50:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.347 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(173.1 AS Decimal(10, 1)), CAST(1.344 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T13:00:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.318 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(144.7 AS Decimal(10, 1)), CAST(1.337 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T13:10:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.360 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(143.7 AS Decimal(10, 1)), CAST(1.247 AS Decimal(10, 3)), CAST(1.176 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T13:20:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.235 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(171.6 AS Decimal(10, 1)), CAST(1.334 AS Decimal(10, 3)), CAST(1.078 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T13:30:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.278 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(111.0 AS Decimal(10, 1)), CAST(1.332 AS Decimal(10, 3)), CAST(1.470 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T13:40:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.262 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(112.1 AS Decimal(10, 1)), CAST(1.666 AS Decimal(10, 3)), CAST(0.686 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T13:50:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.206 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(174.4 AS Decimal(10, 1)), CAST(0.734 AS Decimal(10, 3)), CAST(0.392 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T14:00:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(2.051 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(101.8 AS Decimal(10, 1)), CAST(0.535 AS Decimal(10, 3)), CAST(0.784 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T14:10:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(1.955 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(48.0 AS Decimal(10, 1)), CAST(0.629 AS Decimal(10, 3)), CAST(0.000 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T14:20:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(1.853 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(127.8 AS Decimal(10, 1)), CAST(0.297 AS Decimal(10, 3)), CAST(0.294 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_neomesir_valbona] ([timestamp], [Pressure Avg (hPa)], [Temperature Smp (°C)], [Total Precipitation Tot (mm)], [Wind direction Smp (°)], [Wind speed Avg (m/s)], [Wind speed Smp (m/s)]) VALUES (CAST(N'2024-11-21T14:30:00.000' AS DateTime), CAST(932.00 AS Decimal(10, 2)), CAST(1.754 AS Decimal(10, 3)), CAST(0.00 AS Decimal(10, 2)), CAST(135.0 AS Decimal(10, 1)), CAST(0.223 AS Decimal(10, 3)), CAST(0.490 AS Decimal(10, 3)))
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'01:00:00' AS Time), CAST(14.93 AS Decimal(10, 2)), CAST(23.13 AS Decimal(10, 2)), CAST(1.35 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(1.68 AS Decimal(10, 2)), CAST(50.08 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(97.56 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(39.13 AS Decimal(10, 2)), CAST(39.56 AS Decimal(10, 2)), CAST(39.88 AS Decimal(10, 2)), CAST(40.04 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'02:00:00' AS Time), CAST(12.65 AS Decimal(10, 2)), CAST(20.89 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(89.55 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(43.76 AS Decimal(10, 2)), CAST(39.47 AS Decimal(10, 2)), CAST(41.91 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'03:00:00' AS Time), CAST(4.61 AS Decimal(10, 2)), CAST(9.09 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(89.34 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(30.10 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'04:00:00' AS Time), CAST(1.14 AS Decimal(10, 2)), CAST(2.90 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(89.34 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.07 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'05:00:00' AS Time), CAST(0.92 AS Decimal(10, 2)), CAST(1.94 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(90.79 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.20 AS Decimal(10, 2)), CAST(0.25 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'06:00:00' AS Time), CAST(4.03 AS Decimal(10, 2)), CAST(4.50 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.39 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(92.28 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(30.10 AS Decimal(10, 2)), CAST(34.68 AS Decimal(10, 2)), CAST(1.30 AS Decimal(10, 2)), CAST(0.81 AS Decimal(10, 2)), CAST(1.58 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'07:00:00' AS Time), CAST(16.42 AS Decimal(10, 2)), CAST(26.09 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.06 AS Decimal(10, 2)), CAST(68.76 AS Decimal(10, 2)), CAST(1.20 AS Decimal(10, 2)), CAST(100.58 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.86 AS Decimal(10, 2)), CAST(44.69 AS Decimal(10, 2)), CAST(44.86 AS Decimal(10, 2)), CAST(44.54 AS Decimal(10, 2)), CAST(45.08 AS Decimal(10, 2)), CAST(44.92 AS Decimal(10, 2)), CAST(0.63 AS Decimal(10, 2)), CAST(0.63 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'08:00:00' AS Time), CAST(22.20 AS Decimal(10, 2)), CAST(34.44 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(62.36 AS Decimal(10, 2)), CAST(63.48 AS Decimal(10, 2)), CAST(92.68 AS Decimal(10, 2)), CAST(97.37 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(93.26 AS Decimal(10, 2)), CAST(44.70 AS Decimal(10, 2)), CAST(44.85 AS Decimal(10, 2)), CAST(44.57 AS Decimal(10, 2)), CAST(45.11 AS Decimal(10, 2)), CAST(44.94 AS Decimal(10, 2)), CAST(9.56 AS Decimal(10, 2)), CAST(9.62 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'09:00:00' AS Time), CAST(21.95 AS Decimal(10, 2)), CAST(33.78 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(53.61 AS Decimal(10, 2)), CAST(69.25 AS Decimal(10, 2)), CAST(93.57 AS Decimal(10, 2)), CAST(89.34 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(99.93 AS Decimal(10, 2)), CAST(44.70 AS Decimal(10, 2)), CAST(44.85 AS Decimal(10, 2)), CAST(44.57 AS Decimal(10, 2)), CAST(45.12 AS Decimal(10, 2)), CAST(44.94 AS Decimal(10, 2)), CAST(32.27 AS Decimal(10, 2)), CAST(32.12 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'10:00:00' AS Time), CAST(21.91 AS Decimal(10, 2)), CAST(33.42 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(12.07 AS Decimal(10, 2)), CAST(89.60 AS Decimal(10, 2)), CAST(129.14 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(89.74 AS Decimal(10, 2)), CAST(44.70 AS Decimal(10, 2)), CAST(44.85 AS Decimal(10, 2)), CAST(44.56 AS Decimal(10, 2)), CAST(45.11 AS Decimal(10, 2)), CAST(44.91 AS Decimal(10, 2)), CAST(34.74 AS Decimal(10, 2)), CAST(34.47 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'11:00:00' AS Time), CAST(21.88 AS Decimal(10, 2)), CAST(33.35 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(103.96 AS Decimal(10, 2)), CAST(114.97 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(109.04 AS Decimal(10, 2)), CAST(44.70 AS Decimal(10, 2)), CAST(44.86 AS Decimal(10, 2)), CAST(44.57 AS Decimal(10, 2)), CAST(45.11 AS Decimal(10, 2)), CAST(44.93 AS Decimal(10, 2)), CAST(26.04 AS Decimal(10, 2)), CAST(25.98 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'12:00:00' AS Time), CAST(21.74 AS Decimal(10, 2)), CAST(33.40 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(89.15 AS Decimal(10, 2)), CAST(115.47 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(113.83 AS Decimal(10, 2)), CAST(44.70 AS Decimal(10, 2)), CAST(44.86 AS Decimal(10, 2)), CAST(44.57 AS Decimal(10, 2)), CAST(45.11 AS Decimal(10, 2)), CAST(44.95 AS Decimal(10, 2)), CAST(28.71 AS Decimal(10, 2)), CAST(28.49 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'13:00:00' AS Time), CAST(21.57 AS Decimal(10, 2)), CAST(33.91 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(110.91 AS Decimal(10, 2)), CAST(125.86 AS Decimal(10, 2)), CAST(0.29 AS Decimal(10, 2)), CAST(118.85 AS Decimal(10, 2)), CAST(44.70 AS Decimal(10, 2)), CAST(44.85 AS Decimal(10, 2)), CAST(44.57 AS Decimal(10, 2)), CAST(45.10 AS Decimal(10, 2)), CAST(44.95 AS Decimal(10, 2)), CAST(21.11 AS Decimal(10, 2)), CAST(21.02 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'14:00:00' AS Time), CAST(21.67 AS Decimal(10, 2)), CAST(33.92 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(2.21 AS Decimal(10, 2)), CAST(118.90 AS Decimal(10, 2)), CAST(112.99 AS Decimal(10, 2)), CAST(94.01 AS Decimal(10, 2)), CAST(101.12 AS Decimal(10, 2)), CAST(44.70 AS Decimal(10, 2)), CAST(44.85 AS Decimal(10, 2)), CAST(44.56 AS Decimal(10, 2)), CAST(45.10 AS Decimal(10, 2)), CAST(44.97 AS Decimal(10, 2)), CAST(10.23 AS Decimal(10, 2)), CAST(10.34 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'15:00:00' AS Time), CAST(21.77 AS Decimal(10, 2)), CAST(33.77 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.30 AS Decimal(10, 2)), CAST(99.50 AS Decimal(10, 2)), CAST(110.09 AS Decimal(10, 2)), CAST(99.37 AS Decimal(10, 2)), CAST(99.40 AS Decimal(10, 2)), CAST(44.68 AS Decimal(10, 2)), CAST(44.83 AS Decimal(10, 2)), CAST(44.56 AS Decimal(10, 2)), CAST(45.09 AS Decimal(10, 2)), CAST(44.98 AS Decimal(10, 2)), CAST(12.32 AS Decimal(10, 2)), CAST(12.62 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'16:00:00' AS Time), CAST(20.59 AS Decimal(10, 2)), CAST(32.67 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.35 AS Decimal(10, 2)), CAST(118.81 AS Decimal(10, 2)), CAST(115.75 AS Decimal(10, 2)), CAST(109.18 AS Decimal(10, 2)), CAST(103.86 AS Decimal(10, 2)), CAST(39.84 AS Decimal(10, 2)), CAST(39.94 AS Decimal(10, 2)), CAST(39.72 AS Decimal(10, 2)), CAST(40.14 AS Decimal(10, 2)), CAST(40.09 AS Decimal(10, 2)), CAST(1.51 AS Decimal(10, 2)), CAST(1.56 AS Decimal(10, 2)), CAST(20.95 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'17:00:00' AS Time), CAST(20.62 AS Decimal(10, 2)), CAST(32.66 AS Decimal(10, 2)), CAST(2.04 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(67.51 AS Decimal(10, 2)), CAST(69.33 AS Decimal(10, 2)), CAST(99.14 AS Decimal(10, 2)), CAST(116.41 AS Decimal(10, 2)), CAST(109.20 AS Decimal(10, 2)), CAST(106.01 AS Decimal(10, 2)), CAST(44.71 AS Decimal(10, 2)), CAST(44.83 AS Decimal(10, 2)), CAST(44.54 AS Decimal(10, 2)), CAST(45.06 AS Decimal(10, 2)), CAST(44.91 AS Decimal(10, 2)), CAST(0.02 AS Decimal(10, 2)), CAST(0.02 AS Decimal(10, 2)), CAST(43.18 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'18:00:00' AS Time), CAST(21.39 AS Decimal(10, 2)), CAST(33.66 AS Decimal(10, 2)), CAST(69.75 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.46 AS Decimal(10, 2)), CAST(69.29 AS Decimal(10, 2)), CAST(94.73 AS Decimal(10, 2)), CAST(89.58 AS Decimal(10, 2)), CAST(110.95 AS Decimal(10, 2)), CAST(110.95 AS Decimal(10, 2)), CAST(44.71 AS Decimal(10, 2)), CAST(44.85 AS Decimal(10, 2)), CAST(44.58 AS Decimal(10, 2)), CAST(45.09 AS Decimal(10, 2)), CAST(44.95 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(43.17 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'19:00:00' AS Time), CAST(21.74 AS Decimal(10, 2)), CAST(33.81 AS Decimal(10, 2)), CAST(69.74 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.44 AS Decimal(10, 2)), CAST(69.31 AS Decimal(10, 2)), CAST(89.14 AS Decimal(10, 2)), CAST(105.94 AS Decimal(10, 2)), CAST(46.05 AS Decimal(10, 2)), CAST(89.37 AS Decimal(10, 2)), CAST(44.71 AS Decimal(10, 2)), CAST(44.84 AS Decimal(10, 2)), CAST(44.58 AS Decimal(10, 2)), CAST(45.09 AS Decimal(10, 2)), CAST(44.95 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(43.18 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'20:00:00' AS Time), CAST(21.94 AS Decimal(10, 2)), CAST(33.99 AS Decimal(10, 2)), CAST(69.74 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.41 AS Decimal(10, 2)), CAST(69.29 AS Decimal(10, 2)), CAST(90.28 AS Decimal(10, 2)), CAST(89.67 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(113.77 AS Decimal(10, 2)), CAST(44.71 AS Decimal(10, 2)), CAST(44.83 AS Decimal(10, 2)), CAST(44.58 AS Decimal(10, 2)), CAST(45.09 AS Decimal(10, 2)), CAST(44.95 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(41.52 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'21:00:00' AS Time), CAST(21.91 AS Decimal(10, 2)), CAST(34.03 AS Decimal(10, 2)), CAST(69.78 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.18 AS Decimal(10, 2)), CAST(69.33 AS Decimal(10, 2)), CAST(105.35 AS Decimal(10, 2)), CAST(89.22 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(109.73 AS Decimal(10, 2)), CAST(44.71 AS Decimal(10, 2)), CAST(44.82 AS Decimal(10, 2)), CAST(44.58 AS Decimal(10, 2)), CAST(45.09 AS Decimal(10, 2)), CAST(44.95 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(5.55 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'22:00:00' AS Time), CAST(21.99 AS Decimal(10, 2)), CAST(33.97 AS Decimal(10, 2)), CAST(69.55 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.30 AS Decimal(10, 2)), CAST(69.33 AS Decimal(10, 2)), CAST(2.79 AS Decimal(10, 2)), CAST(100.33 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(90.21 AS Decimal(10, 2)), CAST(44.71 AS Decimal(10, 2)), CAST(44.84 AS Decimal(10, 2)), CAST(44.56 AS Decimal(10, 2)), CAST(45.09 AS Decimal(10, 2)), CAST(44.95 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'23:00:00' AS Time), CAST(19.49 AS Decimal(10, 2)), CAST(32.02 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(1.80 AS Decimal(10, 2)), CAST(0.80 AS Decimal(10, 2)), CAST(98.38 AS Decimal(10, 2)), CAST(96.33 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(108.88 AS Decimal(10, 2)), CAST(0.68 AS Decimal(10, 2)), CAST(44.84 AS Decimal(10, 2)), CAST(44.58 AS Decimal(10, 2)), CAST(30.83 AS Decimal(10, 2)), CAST(34.57 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_OST] ([data], [time], [HEC Ashta1-T1/020], [HEC ASHTA2-T1/035], [HEC Fierze-T1/487], [HEC Fierze-T2/477], [HEC Fierze-T3/484], [HEC Fierze-T4/489], [HEC Koman-T1/475], [HEC Koman-T2/479], [HEC Koman-T3/481], [HEC Koman-T4/482], [HEC Vau Dejes-T1/486], [HEC Vau Dejes-T2/490], [HEC Vau Dejes-T3/491], [HEC Vau Dejes-T4/492], [HEC Vau Dejes-T5/495], [Karavasta Solar-T1/333], [Karavasta Solar-T2/335], [TEC VLORA-T1/459], [njesia]) VALUES (CAST(N'2024-11-20' AS Date), CAST(N'00:00:00' AS Time), CAST(15.38 AS Decimal(10, 2)), CAST(24.14 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.01 AS Decimal(10, 2)), CAST(89.26 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(69.88 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(30.15 AS Decimal(10, 2)), CAST(30.06 AS Decimal(10, 2)), CAST(30.19 AS Decimal(10, 2)), CAST(30.22 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), CAST(0.00 AS Decimal(10, 2)), N'MWH')
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T00:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(2.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(52.00000 AS Decimal(10, 5)), CAST(16.50000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(70.00000 AS Decimal(10, 5)), CAST(2.00000 AS Decimal(10, 5)), CAST(71.00000 AS Decimal(10, 5)), CAST(16.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(101.00000 AS Decimal(10, 5)), CAST(3.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T00:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(5.20000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(55.20000 AS Decimal(10, 5)), CAST(15.00000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(3.20000 AS Decimal(10, 5)), CAST(81.00000 AS Decimal(10, 5)), CAST(16.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(126.00000 AS Decimal(10, 5)), CAST(2.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T00:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(5.60000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(55.20000 AS Decimal(10, 5)), CAST(14.80000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(70.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(82.00000 AS Decimal(10, 5)), CAST(11.90000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(2.70000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T01:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(5.80000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(54.80000 AS Decimal(10, 5)), CAST(15.60000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(73.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(76.00000 AS Decimal(10, 5)), CAST(14.90000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(205.00000 AS Decimal(10, 5)), CAST(1.90000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T01:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(4.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(54.20000 AS Decimal(10, 5)), CAST(13.10000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(67.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(75.00000 AS Decimal(10, 5)), CAST(14.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(78.00000 AS Decimal(10, 5)), CAST(2.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T01:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(54.00000 AS Decimal(10, 5)), CAST(10.50000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(54.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(14.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(50.00000 AS Decimal(10, 5)), CAST(3.70000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T01:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(54.00000 AS Decimal(10, 5)), CAST(10.10000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(75.00000 AS Decimal(10, 5)), CAST(16.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(39.00000 AS Decimal(10, 5)), CAST(2.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T02:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.80000 AS Decimal(10, 5)), CAST(9.60000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(68.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(78.00000 AS Decimal(10, 5)), CAST(16.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(29.00000 AS Decimal(10, 5)), CAST(1.90000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T02:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.80000 AS Decimal(10, 5)), CAST(9.20000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(63.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(80.00000 AS Decimal(10, 5)), CAST(15.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(121.00000 AS Decimal(10, 5)), CAST(1.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T02:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.80000 AS Decimal(10, 5)), CAST(7.90000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(80.00000 AS Decimal(10, 5)), CAST(16.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(104.00000 AS Decimal(10, 5)), CAST(2.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T02:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.80000 AS Decimal(10, 5)), CAST(7.20000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(75.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(83.00000 AS Decimal(10, 5)), CAST(19.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(120.00000 AS Decimal(10, 5)), CAST(1.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T03:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(54.00000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(68.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(84.00000 AS Decimal(10, 5)), CAST(21.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(88.00000 AS Decimal(10, 5)), CAST(1.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T03:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.80000 AS Decimal(10, 5)), CAST(6.80000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(90.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(83.00000 AS Decimal(10, 5)), CAST(31.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(77.00000 AS Decimal(10, 5)), CAST(1.30000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T03:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.80000 AS Decimal(10, 5)), CAST(6.60000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(82.00000 AS Decimal(10, 5)), CAST(20.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(156.00000 AS Decimal(10, 5)), CAST(2.30000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T03:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.80000 AS Decimal(10, 5)), CAST(6.30000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(69.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(81.00000 AS Decimal(10, 5)), CAST(22.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(170.00000 AS Decimal(10, 5)), CAST(3.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T04:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.60000 AS Decimal(10, 5)), CAST(6.10000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(78.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(80.00000 AS Decimal(10, 5)), CAST(21.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(165.00000 AS Decimal(10, 5)), CAST(3.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T04:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.60000 AS Decimal(10, 5)), CAST(5.90000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(69.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(80.00000 AS Decimal(10, 5)), CAST(22.90000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(163.00000 AS Decimal(10, 5)), CAST(3.30000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T04:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.40000 AS Decimal(10, 5)), CAST(5.70000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(77.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(80.00000 AS Decimal(10, 5)), CAST(22.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(184.00000 AS Decimal(10, 5)), CAST(2.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T04:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.40000 AS Decimal(10, 5)), CAST(5.40000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(80.00000 AS Decimal(10, 5)), CAST(24.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(174.00000 AS Decimal(10, 5)), CAST(2.70000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T05:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.40000 AS Decimal(10, 5)), CAST(4.90000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(65.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(83.00000 AS Decimal(10, 5)), CAST(24.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(162.00000 AS Decimal(10, 5)), CAST(3.70000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T05:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.40000 AS Decimal(10, 5)), CAST(4.60000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(68.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(85.00000 AS Decimal(10, 5)), CAST(28.70000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(163.00000 AS Decimal(10, 5)), CAST(3.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T05:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(53.20000 AS Decimal(10, 5)), CAST(4.40000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(81.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(86.00000 AS Decimal(10, 5)), CAST(26.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(170.00000 AS Decimal(10, 5)), CAST(1.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T05:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(52.20000 AS Decimal(10, 5)), CAST(4.50000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(59.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(86.00000 AS Decimal(10, 5)), CAST(24.70000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(163.00000 AS Decimal(10, 5)), CAST(1.30000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T06:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(52.00000 AS Decimal(10, 5)), CAST(4.30000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(82.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(88.00000 AS Decimal(10, 5)), CAST(27.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(48.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T06:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(51.00000 AS Decimal(10, 5)), CAST(4.30000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(65.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(39.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(31.00000 AS Decimal(10, 5)), CAST(0.90000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T06:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(50.00000 AS Decimal(10, 5)), CAST(4.30000 AS Decimal(10, 5)), CAST(12.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(64.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(36.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(348.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T06:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(49.40000 AS Decimal(10, 5)), CAST(4.40000 AS Decimal(10, 5)), CAST(12.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(67.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(89.00000 AS Decimal(10, 5)), CAST(28.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(263.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T07:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(48.40000 AS Decimal(10, 5)), CAST(4.50000 AS Decimal(10, 5)), CAST(12.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(82.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(26.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(254.00000 AS Decimal(10, 5)), CAST(1.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T07:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1488.80000 AS Decimal(10, 5)), CAST(48.20000 AS Decimal(10, 5)), CAST(4.50000 AS Decimal(10, 5)), CAST(12.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(79.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(85.00000 AS Decimal(10, 5)), CAST(20.70000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(56.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T07:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1474.70000 AS Decimal(10, 5)), CAST(47.40000 AS Decimal(10, 5)), CAST(4.50000 AS Decimal(10, 5)), CAST(12.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(65.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(86.00000 AS Decimal(10, 5)), CAST(23.30000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(150.00000 AS Decimal(10, 5)), CAST(1.70000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T07:45:00.000' AS DateTime), CAST(8.70000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1476.20000 AS Decimal(10, 5)), CAST(46.80000 AS Decimal(10, 5)), CAST(4.30000 AS Decimal(10, 5)), CAST(12.50000 AS Decimal(10, 5)), CAST(3.00000 AS Decimal(10, 5)), CAST(68.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(86.00000 AS Decimal(10, 5)), CAST(36.60000 AS Decimal(10, 5)), CAST(8.70000 AS Decimal(10, 5)), CAST(126.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T08:00:00.000' AS DateTime), CAST(32.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1497.80000 AS Decimal(10, 5)), CAST(46.00000 AS Decimal(10, 5)), CAST(4.10000 AS Decimal(10, 5)), CAST(12.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(29.80000 AS Decimal(10, 5)), CAST(23.50000 AS Decimal(10, 5)), CAST(35.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T08:15:00.000' AS DateTime), CAST(59.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1487.00000 AS Decimal(10, 5)), CAST(46.00000 AS Decimal(10, 5)), CAST(4.10000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(87.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(88.00000 AS Decimal(10, 5)), CAST(25.90000 AS Decimal(10, 5)), CAST(27.60000 AS Decimal(10, 5)), CAST(23.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T08:30:00.000' AS DateTime), CAST(89.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1498.20000 AS Decimal(10, 5)), CAST(45.00000 AS Decimal(10, 5)), CAST(4.10000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(62.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(89.00000 AS Decimal(10, 5)), CAST(32.20000 AS Decimal(10, 5)), CAST(30.00000 AS Decimal(10, 5)), CAST(25.00000 AS Decimal(10, 5)), CAST(1.10000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T08:45:00.000' AS DateTime), CAST(112.70000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1517.20000 AS Decimal(10, 5)), CAST(43.60000 AS Decimal(10, 5)), CAST(4.40000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(69.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(88.00000 AS Decimal(10, 5)), CAST(28.60000 AS Decimal(10, 5)), CAST(31.60000 AS Decimal(10, 5)), CAST(38.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T09:00:00.000' AS DateTime), CAST(134.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1534.30000 AS Decimal(10, 5)), CAST(42.80000 AS Decimal(10, 5)), CAST(4.60000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(60.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(86.00000 AS Decimal(10, 5)), CAST(33.30000 AS Decimal(10, 5)), CAST(44.80000 AS Decimal(10, 5)), CAST(124.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T09:15:00.000' AS DateTime), CAST(147.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1543.90000 AS Decimal(10, 5)), CAST(41.40000 AS Decimal(10, 5)), CAST(4.60000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(59.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(85.00000 AS Decimal(10, 5)), CAST(34.50000 AS Decimal(10, 5)), CAST(41.00000 AS Decimal(10, 5)), CAST(102.00000 AS Decimal(10, 5)), CAST(0.30000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T09:30:00.000' AS DateTime), CAST(154.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1514.70000 AS Decimal(10, 5)), CAST(40.80000 AS Decimal(10, 5)), CAST(4.70000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(73.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(85.00000 AS Decimal(10, 5)), CAST(44.20000 AS Decimal(10, 5)), CAST(37.20000 AS Decimal(10, 5)), CAST(52.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T09:45:00.000' AS DateTime), CAST(170.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1505.90000 AS Decimal(10, 5)), CAST(39.80000 AS Decimal(10, 5)), CAST(4.70000 AS Decimal(10, 5)), CAST(12.60000 AS Decimal(10, 5)), CAST(6.00000 AS Decimal(10, 5)), CAST(34.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(85.00000 AS Decimal(10, 5)), CAST(36.80000 AS Decimal(10, 5)), CAST(47.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T10:00:00.000' AS DateTime), CAST(185.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1511.80000 AS Decimal(10, 5)), CAST(39.00000 AS Decimal(10, 5)), CAST(5.00000 AS Decimal(10, 5)), CAST(12.80000 AS Decimal(10, 5)), CAST(29.00000 AS Decimal(10, 5)), CAST(33.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(85.00000 AS Decimal(10, 5)), CAST(39.20000 AS Decimal(10, 5)), CAST(60.50000 AS Decimal(10, 5)), CAST(286.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T10:15:00.000' AS DateTime), CAST(190.30000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1467.70000 AS Decimal(10, 5)), CAST(38.60000 AS Decimal(10, 5)), CAST(4.80000 AS Decimal(10, 5)), CAST(12.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(32.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(84.00000 AS Decimal(10, 5)), CAST(28.30000 AS Decimal(10, 5)), CAST(45.50000 AS Decimal(10, 5)), CAST(26.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T10:30:00.000' AS DateTime), CAST(220.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1477.00000 AS Decimal(10, 5)), CAST(37.40000 AS Decimal(10, 5)), CAST(4.90000 AS Decimal(10, 5)), CAST(12.90000 AS Decimal(10, 5)), CAST(53.00000 AS Decimal(10, 5)), CAST(35.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(84.00000 AS Decimal(10, 5)), CAST(26.50000 AS Decimal(10, 5)), CAST(66.90000 AS Decimal(10, 5)), CAST(32.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T10:45:00.000' AS DateTime), CAST(258.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1503.00000 AS Decimal(10, 5)), CAST(35.80000 AS Decimal(10, 5)), CAST(5.10000 AS Decimal(10, 5)), CAST(13.00000 AS Decimal(10, 5)), CAST(92.00000 AS Decimal(10, 5)), CAST(34.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(85.00000 AS Decimal(10, 5)), CAST(46.40000 AS Decimal(10, 5)), CAST(85.20000 AS Decimal(10, 5)), CAST(8.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T11:00:00.000' AS DateTime), CAST(288.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1536.30000 AS Decimal(10, 5)), CAST(34.40000 AS Decimal(10, 5)), CAST(5.40000 AS Decimal(10, 5)), CAST(13.10000 AS Decimal(10, 5)), CAST(107.00000 AS Decimal(10, 5)), CAST(35.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(83.00000 AS Decimal(10, 5)), CAST(43.70000 AS Decimal(10, 5)), CAST(90.60000 AS Decimal(10, 5)), CAST(19.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T11:15:00.000' AS DateTime), CAST(372.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1611.80000 AS Decimal(10, 5)), CAST(33.40000 AS Decimal(10, 5)), CAST(5.60000 AS Decimal(10, 5)), CAST(13.40000 AS Decimal(10, 5)), CAST(219.00000 AS Decimal(10, 5)), CAST(35.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(82.00000 AS Decimal(10, 5)), CAST(39.70000 AS Decimal(10, 5)), CAST(129.30000 AS Decimal(10, 5)), CAST(34.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T11:30:00.000' AS DateTime), CAST(422.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1663.50000 AS Decimal(10, 5)), CAST(31.80000 AS Decimal(10, 5)), CAST(5.80000 AS Decimal(10, 5)), CAST(13.50000 AS Decimal(10, 5)), CAST(210.00000 AS Decimal(10, 5)), CAST(32.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(81.00000 AS Decimal(10, 5)), CAST(40.20000 AS Decimal(10, 5)), CAST(117.50000 AS Decimal(10, 5)), CAST(71.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T11:45:00.000' AS DateTime), CAST(485.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1737.60000 AS Decimal(10, 5)), CAST(30.60000 AS Decimal(10, 5)), CAST(6.10000 AS Decimal(10, 5)), CAST(13.50000 AS Decimal(10, 5)), CAST(262.00000 AS Decimal(10, 5)), CAST(31.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(80.00000 AS Decimal(10, 5)), CAST(44.30000 AS Decimal(10, 5)), CAST(147.80000 AS Decimal(10, 5)), CAST(112.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T12:00:00.000' AS DateTime), CAST(563.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1811.60000 AS Decimal(10, 5)), CAST(30.40000 AS Decimal(10, 5)), CAST(6.40000 AS Decimal(10, 5)), CAST(13.60000 AS Decimal(10, 5)), CAST(316.00000 AS Decimal(10, 5)), CAST(31.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(79.00000 AS Decimal(10, 5)), CAST(36.40000 AS Decimal(10, 5)), CAST(168.50000 AS Decimal(10, 5)), CAST(29.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T12:15:00.000' AS DateTime), CAST(551.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1821.60000 AS Decimal(10, 5)), CAST(29.80000 AS Decimal(10, 5)), CAST(6.40000 AS Decimal(10, 5)), CAST(13.50000 AS Decimal(10, 5)), CAST(198.00000 AS Decimal(10, 5)), CAST(33.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(78.00000 AS Decimal(10, 5)), CAST(34.40000 AS Decimal(10, 5)), CAST(117.80000 AS Decimal(10, 5)), CAST(358.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T12:30:00.000' AS DateTime), CAST(544.90000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1836.40000 AS Decimal(10, 5)), CAST(29.20000 AS Decimal(10, 5)), CAST(6.40000 AS Decimal(10, 5)), CAST(13.40000 AS Decimal(10, 5)), CAST(191.00000 AS Decimal(10, 5)), CAST(33.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(77.00000 AS Decimal(10, 5)), CAST(34.20000 AS Decimal(10, 5)), CAST(110.80000 AS Decimal(10, 5)), CAST(344.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T12:45:00.000' AS DateTime), CAST(545.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1888.40000 AS Decimal(10, 5)), CAST(28.80000 AS Decimal(10, 5)), CAST(6.80000 AS Decimal(10, 5)), CAST(13.50000 AS Decimal(10, 5)), CAST(288.00000 AS Decimal(10, 5)), CAST(32.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(77.00000 AS Decimal(10, 5)), CAST(32.10000 AS Decimal(10, 5)), CAST(147.90000 AS Decimal(10, 5)), CAST(346.00000 AS Decimal(10, 5)), CAST(0.30000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T13:00:00.000' AS DateTime), CAST(511.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1942.60000 AS Decimal(10, 5)), CAST(28.60000 AS Decimal(10, 5)), CAST(6.90000 AS Decimal(10, 5)), CAST(13.50000 AS Decimal(10, 5)), CAST(262.00000 AS Decimal(10, 5)), CAST(34.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(76.00000 AS Decimal(10, 5)), CAST(29.90000 AS Decimal(10, 5)), CAST(134.70000 AS Decimal(10, 5)), CAST(242.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T13:15:00.000' AS DateTime), CAST(516.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2006.80000 AS Decimal(10, 5)), CAST(27.40000 AS Decimal(10, 5)), CAST(6.80000 AS Decimal(10, 5)), CAST(13.40000 AS Decimal(10, 5)), CAST(217.00000 AS Decimal(10, 5)), CAST(31.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(31.40000 AS Decimal(10, 5)), CAST(122.60000 AS Decimal(10, 5)), CAST(94.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T13:30:00.000' AS DateTime), CAST(514.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2053.10000 AS Decimal(10, 5)), CAST(27.00000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(13.40000 AS Decimal(10, 5)), CAST(180.00000 AS Decimal(10, 5)), CAST(35.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(75.00000 AS Decimal(10, 5)), CAST(23.00000 AS Decimal(10, 5)), CAST(108.90000 AS Decimal(10, 5)), CAST(128.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T13:45:00.000' AS DateTime), CAST(458.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2088.40000 AS Decimal(10, 5)), CAST(26.60000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(13.40000 AS Decimal(10, 5)), CAST(133.00000 AS Decimal(10, 5)), CAST(34.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(36.90000 AS Decimal(10, 5)), CAST(92.00000 AS Decimal(10, 5)), CAST(288.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T14:00:00.000' AS DateTime), CAST(391.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2112.80000 AS Decimal(10, 5)), CAST(26.40000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(13.30000 AS Decimal(10, 5)), CAST(61.00000 AS Decimal(10, 5)), CAST(32.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(43.40000 AS Decimal(10, 5)), CAST(67.50000 AS Decimal(10, 5)), CAST(355.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T14:15:00.000' AS DateTime), CAST(320.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2164.80000 AS Decimal(10, 5)), CAST(26.40000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(13.20000 AS Decimal(10, 5)), CAST(17.00000 AS Decimal(10, 5)), CAST(36.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(74.00000 AS Decimal(10, 5)), CAST(39.50000 AS Decimal(10, 5)), CAST(52.00000 AS Decimal(10, 5)), CAST(184.00000 AS Decimal(10, 5)), CAST(0.50000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T14:30:00.000' AS DateTime), CAST(275.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2228.50000 AS Decimal(10, 5)), CAST(26.40000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(13.20000 AS Decimal(10, 5)), CAST(48.00000 AS Decimal(10, 5)), CAST(33.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(72.00000 AS Decimal(10, 5)), CAST(37.20000 AS Decimal(10, 5)), CAST(63.70000 AS Decimal(10, 5)), CAST(94.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T14:45:00.000' AS DateTime), CAST(241.90000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2287.20000 AS Decimal(10, 5)), CAST(26.40000 AS Decimal(10, 5)), CAST(7.10000 AS Decimal(10, 5)), CAST(13.20000 AS Decimal(10, 5)), CAST(37.00000 AS Decimal(10, 5)), CAST(32.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(72.00000 AS Decimal(10, 5)), CAST(26.10000 AS Decimal(10, 5)), CAST(58.70000 AS Decimal(10, 5)), CAST(116.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_fierze] ([Date], [Fierze Meteo - 1 h radiation accumulation - Raw], [Fierze Meteo - 1 hour rain accumulation - Raw], [Fierze Meteo - 24 h ratiation accumulation - Raw], [Fierze Meteo - 24H rain accumulation - Raw], [Fierze Meteo - Air temperature - Raw], [Fierze Meteo - Battery voltage - Raw], [Fierze Meteo - Charging current - Raw], [Fierze Meteo - Discharge current (consumption) - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Fierze Meteo - Relative humidity - Raw], [Fierze Meteo - Snow level - Raw], [Fierze Meteo - Solar radiation - Raw], [Fierze Meteo - Wind direction - Raw], [Fierze Meteo - Wind Speed - Raw]) VALUES (CAST(N'2024-11-21T15:00:00.000' AS DateTime), CAST(219.50000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2332.30000 AS Decimal(10, 5)), CAST(26.40000 AS Decimal(10, 5)), CAST(7.00000 AS Decimal(10, 5)), CAST(13.10000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(34.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(72.00000 AS Decimal(10, 5)), CAST(25.50000 AS Decimal(10, 5)), CAST(45.10000 AS Decimal(10, 5)), CAST(102.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T00:15:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.94400 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T00:30:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.76200 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T00:45:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.70700 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T01:00:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.73100 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T01:15:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.74100 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T01:30:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.77500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T01:45:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.83400 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T02:00:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.85400 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T02:15:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.79200 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T02:30:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.71000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T02:45:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.71600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T03:00:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.75600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T03:15:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.76300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T03:30:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.79600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T03:45:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.81400 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T04:00:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.77800 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T04:15:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.73300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T04:30:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.71600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T04:45:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.74500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T05:00:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.75600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T05:15:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(72.79900 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T05:30:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(73.05000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T05:45:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(73.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T06:00:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(73.40300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T06:15:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(73.49600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T06:30:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(73.78100 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T06:45:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(74.03300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T07:00:00.000' AS DateTime), CAST(12.90000 AS Decimal(10, 5)), CAST(74.01500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T07:15:00.000' AS DateTime), CAST(13.00000 AS Decimal(10, 5)), CAST(73.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T07:30:00.000' AS DateTime), CAST(13.10000 AS Decimal(10, 5)), CAST(73.81800 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T07:45:00.000' AS DateTime), CAST(13.70000 AS Decimal(10, 5)), CAST(73.84600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T08:00:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.76900 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T08:15:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.73700 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T08:30:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.80400 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T08:45:00.000' AS DateTime), CAST(13.80000 AS Decimal(10, 5)), CAST(74.00100 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T09:00:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.08200 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T09:15:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.10300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T09:30:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.03400 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T09:45:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.95700 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T10:00:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.92800 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T10:15:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.93900 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T10:30:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.96300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T10:45:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.98700 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T11:00:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.98200 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T11:15:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.93700 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T11:30:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.91800 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T11:45:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.89900 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T12:00:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.90800 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T12:15:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.91400 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T12:30:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.98600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T12:45:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.01000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T13:00:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.00500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T13:15:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.00700 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T13:30:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.02200 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T13:45:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.92300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T14:00:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.90300 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T14:15:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(73.92600 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_Koman] ([Date], [Koman Bjefi Poshtem Hydro - Battery voltage - Raw], [Koman Bjefi Poshtem Hydro - Water level - Raw]) VALUES (CAST(N'2024-11-21T14:30:00.000' AS DateTime), CAST(13.90000 AS Decimal(10, 5)), CAST(74.09700 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T00:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(1.80000 AS Decimal(10, 5)), CAST(2.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T00:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(1.60000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(3.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(2.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T00:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2.80000 AS Decimal(10, 5)), CAST(3.20000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(4.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T01:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(2.40000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(1.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T01:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(2.20000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T01:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(2.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T01:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1.20000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T02:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(1.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T02:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T02:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T02:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T03:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T03:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T03:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T03:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T04:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T04:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T04:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T04:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T05:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T05:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T05:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T05:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.40000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T06:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T06:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.60000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T06:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.80000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T06:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T07:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T07:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T07:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T07:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T08:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T08:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T08:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T08:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T09:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T09:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T09:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T09:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T10:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T10:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T10:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T10:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T11:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T11:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.20000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T11:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T11:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T12:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T12:15:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T12:30:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T12:45:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_polaris_teGjitha] ([Date], [Vau Dejes Meteo - Percipitation intencity - Raw], [Kukes Meteo - Percipitation intencity - Raw], [Okshtun Meteo - Percipitation intencity - Raw], [Koman Meteo - Percipitation intencity - Raw], [Dragobi Meteo - Percipitation intencity - Raw], [Fierze Meteo - Percipitation intencity - Raw], [Lin Meteo - Percipitation intencity - Raw], [Theth Meteo - Percipitation intencity - Raw], [Peshkopi Meteo - Percipitation intencity - Raw], [Zogaj Meteo - Percipitation intencity - Raw], [Puke Meteo - Percipitation intencity - Raw], [Shishtavec Meteo - Percipitation intencity - Raw]) VALUES (CAST(N'2024-11-21T13:00:00.000' AS DateTime), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)), CAST(0.00000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'06:30:00' AS Time), CAST(23735 AS Decimal(18, 0)), CAST(75 AS Decimal(18, 0)), CAST(1945 AS Decimal(18, 0)), CAST(22482 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'06:45:00' AS Time), CAST(23736 AS Decimal(18, 0)), CAST(77 AS Decimal(18, 0)), CAST(21955 AS Decimal(18, 0)), CAST(22633 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'07:00:00' AS Time), CAST(23724 AS Decimal(18, 0)), CAST(2834 AS Decimal(18, 0)), CAST(22533 AS Decimal(18, 0)), CAST(22476 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'07:15:00' AS Time), CAST(32350 AS Decimal(18, 0)), CAST(29992 AS Decimal(18, 0)), CAST(33560 AS Decimal(18, 0)), CAST(22622 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'07:30:00' AS Time), CAST(32497 AS Decimal(18, 0)), CAST(29990 AS Decimal(18, 0)), CAST(33791 AS Decimal(18, 0)), CAST(22861 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'07:45:00' AS Time), CAST(25960 AS Decimal(18, 0)), CAST(25141 AS Decimal(18, 0)), CAST(26648 AS Decimal(18, 0)), CAST(22500 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'08:00:00' AS Time), CAST(22496 AS Decimal(18, 0)), CAST(22496 AS Decimal(18, 0)), CAST(22538 AS Decimal(18, 0)), CAST(22490 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'08:15:00' AS Time), CAST(32314 AS Decimal(18, 0)), CAST(23341 AS Decimal(18, 0)), CAST(23898 AS Decimal(18, 0)), CAST(22477 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'08:30:00' AS Time), CAST(27858 AS Decimal(18, 0)), CAST(22498 AS Decimal(18, 0)), CAST(22537 AS Decimal(18, 0)), CAST(22491 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'08:45:00' AS Time), CAST(22498 AS Decimal(18, 0)), CAST(22498 AS Decimal(18, 0)), CAST(22539 AS Decimal(18, 0)), CAST(22478 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'09:00:00' AS Time), CAST(22499 AS Decimal(18, 0)), CAST(22495 AS Decimal(18, 0)), CAST(22533 AS Decimal(18, 0)), CAST(22488 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'09:15:00' AS Time), CAST(23015 AS Decimal(18, 0)), CAST(22976 AS Decimal(18, 0)), CAST(26627 AS Decimal(18, 0)), CAST(33852 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'09:30:00' AS Time), CAST(25004 AS Decimal(18, 0)), CAST(25003 AS Decimal(18, 0)), CAST(32516 AS Decimal(18, 0)), CAST(34275 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'09:45:00' AS Time), CAST(25008 AS Decimal(18, 0)), CAST(25010 AS Decimal(18, 0)), CAST(32521 AS Decimal(18, 0)), CAST(36209 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'10:00:00' AS Time), CAST(25004 AS Decimal(18, 0)), CAST(25007 AS Decimal(18, 0)), CAST(32523 AS Decimal(18, 0)), CAST(33887 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'10:15:00' AS Time), CAST(25007 AS Decimal(18, 0)), CAST(22523 AS Decimal(18, 0)), CAST(22727 AS Decimal(18, 0)), CAST(34474 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'10:30:00' AS Time), CAST(32388 AS Decimal(18, 0)), CAST(22494 AS Decimal(18, 0)), CAST(22536 AS Decimal(18, 0)), CAST(25839 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'10:45:00' AS Time), CAST(32497 AS Decimal(18, 0)), CAST(22499 AS Decimal(18, 0)), CAST(22542 AS Decimal(18, 0)), CAST(24509 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'11:00:00' AS Time), CAST(32492 AS Decimal(18, 0)), CAST(22497 AS Decimal(18, 0)), CAST(22535 AS Decimal(18, 0)), CAST(28842 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'11:15:00' AS Time), CAST(32492 AS Decimal(18, 0)), CAST(22495 AS Decimal(18, 0)), CAST(22532 AS Decimal(18, 0)), CAST(29522 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'11:30:00' AS Time), CAST(32496 AS Decimal(18, 0)), CAST(22498 AS Decimal(18, 0)), CAST(22539 AS Decimal(18, 0)), CAST(30466 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'11:45:00' AS Time), CAST(32493 AS Decimal(18, 0)), CAST(22498 AS Decimal(18, 0)), CAST(22542 AS Decimal(18, 0)), CAST(24558 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'12:00:00' AS Time), CAST(32494 AS Decimal(18, 0)), CAST(22494 AS Decimal(18, 0)), CAST(22536 AS Decimal(18, 0)), CAST(22490 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'12:15:00' AS Time), CAST(30023 AS Decimal(18, 0)), CAST(22499 AS Decimal(18, 0)), CAST(22537 AS Decimal(18, 0)), CAST(22492 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'12:30:00' AS Time), CAST(30002 AS Decimal(18, 0)), CAST(22498 AS Decimal(18, 0)), CAST(22540 AS Decimal(18, 0)), CAST(22484 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'12:45:00' AS Time), CAST(30000 AS Decimal(18, 0)), CAST(22497 AS Decimal(18, 0)), CAST(22537 AS Decimal(18, 0)), CAST(22486 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'13:00:00' AS Time), CAST(29997 AS Decimal(18, 0)), CAST(22500 AS Decimal(18, 0)), CAST(22536 AS Decimal(18, 0)), CAST(22481 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'13:15:00' AS Time), CAST(34935 AS Decimal(18, 0)), CAST(26152 AS Decimal(18, 0)), CAST(25342 AS Decimal(18, 0)), CAST(22477 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'13:30:00' AS Time), CAST(34992 AS Decimal(18, 0)), CAST(22498 AS Decimal(18, 0)), CAST(22535 AS Decimal(18, 0)), CAST(22484 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'13:45:00' AS Time), CAST(34993 AS Decimal(18, 0)), CAST(22499 AS Decimal(18, 0)), CAST(22540 AS Decimal(18, 0)), CAST(22490 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'14:00:00' AS Time), CAST(34992 AS Decimal(18, 0)), CAST(22497 AS Decimal(18, 0)), CAST(22533 AS Decimal(18, 0)), CAST(22480 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'14:15:00' AS Time), CAST(25011 AS Decimal(18, 0)), CAST(24892 AS Decimal(18, 0)), CAST(26039 AS Decimal(18, 0)), CAST(22492 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'14:30:00' AS Time), CAST(22497 AS Decimal(18, 0)), CAST(22500 AS Decimal(18, 0)), CAST(22540 AS Decimal(18, 0)), CAST(22480 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'14:45:00' AS Time), CAST(22497 AS Decimal(18, 0)), CAST(22500 AS Decimal(18, 0)), CAST(22537 AS Decimal(18, 0)), CAST(23499 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_PSME] ([time], [KOMAN_AG1_023], [KOMAN_AG2_024], [KOMAN_AG3_025], [KOMAN_AG4_025]) VALUES (CAST(N'15:00:00' AS Time), CAST(22496 AS Decimal(18, 0)), CAST(22495 AS Decimal(18, 0)), CAST(22531 AS Decimal(18, 0)), CAST(25941 AS Decimal(18, 0)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T10:00:00.000' AS DateTime), CAST(23.33499 AS Decimal(10, 5)), CAST(73.11312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T10:15:00.000' AS DateTime), CAST(23.31437 AS Decimal(10, 5)), CAST(73.11312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T10:30:00.000' AS DateTime), CAST(23.33874 AS Decimal(10, 5)), CAST(73.11312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T10:45:00.000' AS DateTime), CAST(23.32937 AS Decimal(10, 5)), CAST(73.11312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T11:00:00.000' AS DateTime), CAST(23.32749 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T11:15:00.000' AS DateTime), CAST(23.32375 AS Decimal(10, 5)), CAST(73.09375 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T11:30:00.000' AS DateTime), CAST(23.33124 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T11:45:00.000' AS DateTime), CAST(23.33124 AS Decimal(10, 5)), CAST(73.07921 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T12:00:00.000' AS DateTime), CAST(23.32375 AS Decimal(10, 5)), CAST(73.07437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T12:15:00.000' AS DateTime), CAST(23.32375 AS Decimal(10, 5)), CAST(73.07437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T12:30:00.000' AS DateTime), CAST(23.32749 AS Decimal(10, 5)), CAST(73.06469 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T12:45:00.000' AS DateTime), CAST(23.31812 AS Decimal(10, 5)), CAST(73.05015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T13:00:00.000' AS DateTime), CAST(23.33687 AS Decimal(10, 5)), CAST(73.05015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T13:15:00.000' AS DateTime), CAST(23.34625 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T13:30:00.000' AS DateTime), CAST(23.32562 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T13:45:00.000' AS DateTime), CAST(23.34437 AS Decimal(10, 5)), CAST(73.05015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T14:00:00.000' AS DateTime), CAST(23.32749 AS Decimal(10, 5)), CAST(73.05015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T14:15:00.000' AS DateTime), CAST(23.33124 AS Decimal(10, 5)), CAST(73.03562 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T14:30:00.000' AS DateTime), CAST(23.32000 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T14:45:00.000' AS DateTime), CAST(23.33124 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T15:00:00.000' AS DateTime), CAST(23.28437 AS Decimal(10, 5)), CAST(73.04531 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T15:15:00.000' AS DateTime), CAST(23.14562 AS Decimal(10, 5)), CAST(73.03077 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T15:30:00.000' AS DateTime), CAST(23.13437 AS Decimal(10, 5)), CAST(73.04531 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T15:45:00.000' AS DateTime), CAST(23.11937 AS Decimal(10, 5)), CAST(73.03562 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T16:00:00.000' AS DateTime), CAST(23.15500 AS Decimal(10, 5)), CAST(73.05015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T16:15:00.000' AS DateTime), CAST(23.29000 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T16:30:00.000' AS DateTime), CAST(23.29187 AS Decimal(10, 5)), CAST(73.05984 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T16:45:00.000' AS DateTime), CAST(23.30312 AS Decimal(10, 5)), CAST(73.05984 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T17:00:00.000' AS DateTime), CAST(23.30125 AS Decimal(10, 5)), CAST(73.06469 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T17:15:00.000' AS DateTime), CAST(23.30125 AS Decimal(10, 5)), CAST(73.06469 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T17:30:00.000' AS DateTime), CAST(23.31250 AS Decimal(10, 5)), CAST(73.07921 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T17:45:00.000' AS DateTime), CAST(23.31812 AS Decimal(10, 5)), CAST(73.07921 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T18:00:00.000' AS DateTime), CAST(23.30875 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T18:15:00.000' AS DateTime), CAST(23.32375 AS Decimal(10, 5)), CAST(73.09375 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T18:30:00.000' AS DateTime), CAST(23.31250 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T18:45:00.000' AS DateTime), CAST(23.32937 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T19:00:00.000' AS DateTime), CAST(23.32749 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T19:15:00.000' AS DateTime), CAST(23.35000 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T19:30:00.000' AS DateTime), CAST(23.34625 AS Decimal(10, 5)), CAST(73.08406 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T19:45:00.000' AS DateTime), CAST(23.33687 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T20:00:00.000' AS DateTime), CAST(23.34437 AS Decimal(10, 5)), CAST(73.08406 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T20:15:00.000' AS DateTime), CAST(23.35562 AS Decimal(10, 5)), CAST(73.08406 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T20:30:00.000' AS DateTime), CAST(23.36687 AS Decimal(10, 5)), CAST(73.07437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T20:45:00.000' AS DateTime), CAST(23.34625 AS Decimal(10, 5)), CAST(73.07921 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T21:00:00.000' AS DateTime), CAST(23.35562 AS Decimal(10, 5)), CAST(73.07437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T21:15:00.000' AS DateTime), CAST(23.35937 AS Decimal(10, 5)), CAST(73.07437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T21:30:00.000' AS DateTime), CAST(23.37437 AS Decimal(10, 5)), CAST(73.06953 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T21:45:00.000' AS DateTime), CAST(23.38375 AS Decimal(10, 5)), CAST(73.06953 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T22:00:00.000' AS DateTime), CAST(23.39125 AS Decimal(10, 5)), CAST(73.05015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T22:15:00.000' AS DateTime), CAST(23.15312 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T22:30:00.000' AS DateTime), CAST(23.11187 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T22:45:00.000' AS DateTime), CAST(23.09875 AS Decimal(10, 5)), CAST(73.05015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T23:00:00.000' AS DateTime), CAST(23.08187 AS Decimal(10, 5)), CAST(73.06469 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T23:15:00.000' AS DateTime), CAST(22.99000 AS Decimal(10, 5)), CAST(73.10343 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T23:30:00.000' AS DateTime), CAST(22.97687 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-20T23:45:00.000' AS DateTime), CAST(22.97312 AS Decimal(10, 5)), CAST(73.09859 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T00:00:00.000' AS DateTime), CAST(22.99187 AS Decimal(10, 5)), CAST(73.10343 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T00:15:00.000' AS DateTime), CAST(23.07812 AS Decimal(10, 5)), CAST(73.10343 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T00:30:00.000' AS DateTime), CAST(23.08562 AS Decimal(10, 5)), CAST(73.11796 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T00:45:00.000' AS DateTime), CAST(23.08750 AS Decimal(10, 5)), CAST(73.09859 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T01:00:00.000' AS DateTime), CAST(23.03500 AS Decimal(10, 5)), CAST(73.09859 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T01:15:00.000' AS DateTime), CAST(23.00875 AS Decimal(10, 5)), CAST(73.10828 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T01:30:00.000' AS DateTime), CAST(23.02375 AS Decimal(10, 5)), CAST(73.09859 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T01:45:00.000' AS DateTime), CAST(23.01250 AS Decimal(10, 5)), CAST(73.11312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T02:00:00.000' AS DateTime), CAST(23.00312 AS Decimal(10, 5)), CAST(73.08406 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T02:15:00.000' AS DateTime), CAST(22.80625 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T02:30:00.000' AS DateTime), CAST(22.86999 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T02:45:00.000' AS DateTime), CAST(22.84187 AS Decimal(10, 5)), CAST(73.06953 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T03:00:00.000' AS DateTime), CAST(22.82125 AS Decimal(10, 5)), CAST(73.10828 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T03:15:00.000' AS DateTime), CAST(22.81937 AS Decimal(10, 5)), CAST(73.10343 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T03:30:00.000' AS DateTime), CAST(22.81937 AS Decimal(10, 5)), CAST(73.10343 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T03:45:00.000' AS DateTime), CAST(22.81750 AS Decimal(10, 5)), CAST(73.09859 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T04:00:00.000' AS DateTime), CAST(22.80625 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T04:15:00.000' AS DateTime), CAST(22.80437 AS Decimal(10, 5)), CAST(73.10828 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T04:30:00.000' AS DateTime), CAST(22.80999 AS Decimal(10, 5)), CAST(73.09859 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T04:45:00.000' AS DateTime), CAST(22.80812 AS Decimal(10, 5)), CAST(73.09375 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T05:00:00.000' AS DateTime), CAST(22.91125 AS Decimal(10, 5)), CAST(73.10828 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T05:15:00.000' AS DateTime), CAST(22.87562 AS Decimal(10, 5)), CAST(73.09375 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T05:30:00.000' AS DateTime), CAST(22.88125 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T05:45:00.000' AS DateTime), CAST(22.87562 AS Decimal(10, 5)), CAST(73.06953 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T06:00:00.000' AS DateTime), CAST(22.90374 AS Decimal(10, 5)), CAST(73.07437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T06:15:00.000' AS DateTime), CAST(23.16625 AS Decimal(10, 5)), CAST(73.05984 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T06:30:00.000' AS DateTime), CAST(23.12125 AS Decimal(10, 5)), CAST(73.04531 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T06:45:00.000' AS DateTime), CAST(23.14749 AS Decimal(10, 5)), CAST(73.03562 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T07:00:00.000' AS DateTime), CAST(23.15687 AS Decimal(10, 5)), CAST(73.05984 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T07:15:00.000' AS DateTime), CAST(23.14937 AS Decimal(10, 5)), CAST(73.05500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T07:30:00.000' AS DateTime), CAST(23.15124 AS Decimal(10, 5)), CAST(73.04046 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T07:45:00.000' AS DateTime), CAST(23.15687 AS Decimal(10, 5)), CAST(73.06469 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T08:00:00.000' AS DateTime), CAST(23.15687 AS Decimal(10, 5)), CAST(73.07921 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T08:15:00.000' AS DateTime), CAST(23.16437 AS Decimal(10, 5)), CAST(73.07921 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T08:30:00.000' AS DateTime), CAST(23.15124 AS Decimal(10, 5)), CAST(73.07437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T08:45:00.000' AS DateTime), CAST(23.14749 AS Decimal(10, 5)), CAST(73.07921 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T09:00:00.000' AS DateTime), CAST(22.95999 AS Decimal(10, 5)), CAST(73.08890 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T09:15:00.000' AS DateTime), CAST(22.75562 AS Decimal(10, 5)), CAST(73.11312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T09:30:00.000' AS DateTime), CAST(22.89250 AS Decimal(10, 5)), CAST(73.11796 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T09:45:00.000' AS DateTime), CAST(22.86249 AS Decimal(10, 5)), CAST(73.14703 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T10:00:00.000' AS DateTime), CAST(22.90187 AS Decimal(10, 5)), CAST(73.16156 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T10:15:00.000' AS DateTime), CAST(22.90187 AS Decimal(10, 5)), CAST(73.19062 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T10:30:00.000' AS DateTime), CAST(22.90937 AS Decimal(10, 5)), CAST(73.20999 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T10:45:00.000' AS DateTime), CAST(22.90374 AS Decimal(10, 5)), CAST(73.21484 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T11:00:00.000' AS DateTime), CAST(22.89437 AS Decimal(10, 5)), CAST(73.25359 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T11:15:00.000' AS DateTime), CAST(22.91312 AS Decimal(10, 5)), CAST(73.24390 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T11:30:00.000' AS DateTime), CAST(22.89625 AS Decimal(10, 5)), CAST(73.26812 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T11:45:00.000' AS DateTime), CAST(22.88500 AS Decimal(10, 5)), CAST(73.29234 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T12:00:00.000' AS DateTime), CAST(22.82500 AS Decimal(10, 5)), CAST(73.30687 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T12:15:00.000' AS DateTime), CAST(22.76312 AS Decimal(10, 5)), CAST(73.33109 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T12:30:00.000' AS DateTime), CAST(22.80999 AS Decimal(10, 5)), CAST(73.34078 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T12:45:00.000' AS DateTime), CAST(22.80437 AS Decimal(10, 5)), CAST(73.35047 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T13:00:00.000' AS DateTime), CAST(22.79687 AS Decimal(10, 5)), CAST(73.38437 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T13:15:00.000' AS DateTime), CAST(22.81562 AS Decimal(10, 5)), CAST(73.38922 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T13:30:00.000' AS DateTime), CAST(22.83062 AS Decimal(10, 5)), CAST(73.40859 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T13:45:00.000' AS DateTime), CAST(22.83625 AS Decimal(10, 5)), CAST(73.42312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T14:00:00.000' AS DateTime), CAST(22.84375 AS Decimal(10, 5)), CAST(73.45703 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T14:15:00.000' AS DateTime), CAST(22.83437 AS Decimal(10, 5)), CAST(73.48124 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T14:30:00.000' AS DateTime), CAST(22.82500 AS Decimal(10, 5)), CAST(73.50062 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T14:45:00.000' AS DateTime), CAST(22.83250 AS Decimal(10, 5)), CAST(73.52000 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T15:00:00.000' AS DateTime), CAST(22.78562 AS Decimal(10, 5)), CAST(73.52968 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T15:15:00.000' AS DateTime), CAST(22.80062 AS Decimal(10, 5)), CAST(73.53453 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T15:30:00.000' AS DateTime), CAST(22.79312 AS Decimal(10, 5)), CAST(73.55874 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T15:45:00.000' AS DateTime), CAST(22.78375 AS Decimal(10, 5)), CAST(73.58297 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T16:00:00.000' AS DateTime), CAST(22.77062 AS Decimal(10, 5)), CAST(73.61203 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T16:15:00.000' AS DateTime), CAST(22.77249 AS Decimal(10, 5)), CAST(73.62171 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T16:30:00.000' AS DateTime), CAST(22.78000 AS Decimal(10, 5)), CAST(73.64593 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T16:45:00.000' AS DateTime), CAST(22.79125 AS Decimal(10, 5)), CAST(73.67500 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T17:00:00.000' AS DateTime), CAST(22.94312 AS Decimal(10, 5)), CAST(73.67015 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T17:15:00.000' AS DateTime), CAST(22.87187 AS Decimal(10, 5)), CAST(73.70406 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T17:30:00.000' AS DateTime), CAST(22.86999 AS Decimal(10, 5)), CAST(73.73312 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T17:45:00.000' AS DateTime), CAST(22.88125 AS Decimal(10, 5)), CAST(73.74765 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T18:00:00.000' AS DateTime), CAST(22.86062 AS Decimal(10, 5)), CAST(73.77671 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T18:15:00.000' AS DateTime), CAST(22.86062 AS Decimal(10, 5)), CAST(73.80093 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T18:30:00.000' AS DateTime), CAST(22.87937 AS Decimal(10, 5)), CAST(73.81546 AS Decimal(10, 5)))
GO
INSERT [dbo].[staging_water_level_Vau_Dejes] ([time], [downstream_water_level], [upstream_reservoir_level]) VALUES (CAST(N'2024-11-21T18:45:00.000' AS DateTime), CAST(22.86437 AS Decimal(10, 5)), CAST(73.83969 AS Decimal(10, 5)))
GO
SET IDENTITY_INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ON 
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (1, 212, 60, 150, CAST(82.67 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (2, 145, 60, 150, CAST(81.61 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (3, 115, 60, 150, CAST(80.16 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (4, 107, 60, 150, CAST(78.30 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (5, 113, 60, 150, CAST(77.49 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (6, 153, 70, 150, CAST(83.15 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (7, 329, 80, 150, CAST(107.53 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (8, 568, 80, 300, CAST(124.84 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (9, 619, 100, 300, CAST(144.11 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (10, 618, 100, 300, CAST(138.60 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (11, 577, 100, 300, CAST(122.00 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (12, 562, 80, 300, CAST(110.00 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (13, 560, 100, 300, CAST(103.18 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (14, 597, 100, 300, CAST(110.06 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (15, 617, 100, 300, CAST(118.23 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (16, 618, 100, 300, CAST(130.97 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (17, 642, 100, 300, CAST(140.28 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (18, 719, 100, 300, CAST(143.57 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (19, 790, 100, 300, CAST(135.36 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (20, 774, 100, 300, CAST(128.58 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (21, 731, 100, 300, CAST(121.26 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (22, 639, 100, 300, CAST(106.66 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (23, 494, 80, 300, CAST(99.57 AS Decimal(10, 2)))
GO
INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] ([ID], [DEMAND_FSHU], [Min_Generation], [Max_Generation], [Day_Ahead_Price]) VALUES (24, 338, 80, 300, CAST(89.21 AS Decimal(10, 2)))
GO
SET IDENTITY_INSERT [dbo].[Third_Scenario_Input_Hydro_Deficiency] OFF
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (1, 152, 0, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (2, 85, 0, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (3, 55, 0, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (4, 47, 0, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (5, 53, 0, 0, 0, 0, 0, 60)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (6, 83, 0, 0, 0, 0, 0, 70)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (7, 249, 0, 0, 0, 0, 0, 80)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (8, 488, 0, 0, 0, 0, 0, 80)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (9, 0, 0, 5, 100, 200, 200, 114)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (10, 0, 0, 5, 100, 200, 200, 113)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (11, 477, 0, 5, 95, 0, 0, 0)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (12, 482, 0, 5, 75, 0, 0, 0)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (13, 460, 0, 5, 95, 0, 0, 0)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (14, 497, 0, 5, 95, 0, 0, 0)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (15, 517, 0, 5, 95, 0, 0, 0)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (16, 0, 0, 5, 100, 200, 200, 113)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (17, 0, 0, 0, 0, 200, 340, 102)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (18, 0, 0, 0, 0, 200, 400, 119)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (19, 0, 0, 0, 0, 200, 500, 90)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (20, 0, 0, 0, 0, 200, 500, 74)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (21, 631, 0, 0, 0, 0, 0, 100)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (22, 539, 0, 0, 0, 0, 0, 100)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (23, 414, 0, 0, 0, 0, 0, 80)
GO
INSERT [dbo].[Third_Scenario_Output_Hydro_Deficiency] ([RowID], [Import], [Export], [Qyrsaqe], [Kravasta], [Fierza], [Koman], [Vau_Dejes]) VALUES (24, 258, 0, 0, 0, 0, 0, 80)
GO
