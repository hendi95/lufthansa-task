USE [PizzaShop]
GO
/****** Object:  Table [dbo].[customers]    Script Date: 6/12/2025 1:25:47 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[customers](
	[cust_id] [int] IDENTITY(1,1) NOT NULL,
	[cust_firstname] [varchar](50) NOT NULL,
	[cust_lastname] [varchar](50) NOT NULL,
 CONSTRAINT [pk_customers_cust_id] PRIMARY KEY CLUSTERED 
(
	[cust_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[inventory]    Script Date: 6/12/2025 1:25:47 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[inventory](
	[inv_id] [int] IDENTITY(1,1) NOT NULL,
	[item_id] [varchar](10) NOT NULL,
	[quantity] [int] NOT NULL,
 CONSTRAINT [pk_inventory_inv_id] PRIMARY KEY CLUSTERED 
(
	[inv_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[staff]    Script Date: 6/12/2025 1:25:47 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[staff](
	[staff_id] [varchar](20) NOT NULL,
	[first_name] [varchar](50) NOT NULL,
	[last_name] [varchar](50) NOT NULL,
	[position] [varchar](100) NOT NULL,
	[hourly_rate] [decimal](5, 2) NOT NULL,
 CONSTRAINT [pk_staff_staff_id] PRIMARY KEY CLUSTERED 
(
	[staff_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
SET IDENTITY_INSERT [dbo].[customers] ON 
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (1, N'John', N'Doe')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (2, N'Jane', N'Smith')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (3, N'Michael', N'Johnson')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (4, N'Emma', N'Williams')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (5, N'Sarah', N'Johnson')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (6, N'Michael', N'Brown')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (7, N'Jennifer', N'Miller')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (8, N'William', N'Davis')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (9, N'Elizabeth', N'Garcia')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (10, N'Daniel', N'Martinez')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (11, N'Sophia', N'Lopez')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (12, N'Matthew', N'Hernandez')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (13, N'Olivia', N'Gonzalez')
GO
INSERT [dbo].[customers] ([cust_id], [cust_firstname], [cust_lastname]) VALUES (14, N'David', N'Perez')
GO
SET IDENTITY_INSERT [dbo].[customers] OFF
GO
SET IDENTITY_INSERT [dbo].[inventory] ON 
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (1, N'ITEM001', 50)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (2, N'ITEM002', 30)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (3, N'ITEM003', 55)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (4, N'ITEM004', 40)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (5, N'ITEM005', 15)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (6, N'ITEM006', 25)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (7, N'ITEM007', 15)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (8, N'ITEM008', 30)
GO
INSERT [dbo].[inventory] ([inv_id], [item_id], [quantity]) VALUES (9, N'ITEM009', 60)
GO
SET IDENTITY_INSERT [dbo].[inventory] OFF
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF001', N'David', N'Johnson', N'Cook', CAST(15.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF002', N'Emily', N'Smith', N'Server', CAST(12.50 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF003', N'William', N'Lee', N'Cashier', CAST(11.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF004', N'Olivia', N'Brown', N'Manager', CAST(20.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF005', N'James', N'Miller', N'Chef', CAST(18.75 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF006', N'Ava', N'Rodriguez', N'Server', CAST(11.50 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF007', N'Noah', N'Lopez', N'Cook', CAST(16.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF008', N'Emma', N'Lee', N'Cashier', CAST(10.00 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF009', N'Elijah', N'Gonzalez', N'Chef', CAST(17.50 AS Decimal(5, 2)))
GO
INSERT [dbo].[staff] ([staff_id], [first_name], [last_name], [position], [hourly_rate]) VALUES (N'STAFF010', N'Isabella', N'Perez', N'Manager', CAST(21.00 AS Decimal(5, 2)))
GO
ALTER TABLE [dbo].[inventory]  WITH CHECK ADD  CONSTRAINT [fk_inventory_item_id] FOREIGN KEY([item_id])
REFERENCES [dbo].[items] ([item_id])
GO
ALTER TABLE [dbo].[inventory] CHECK CONSTRAINT [fk_inventory_item_id]
GO
