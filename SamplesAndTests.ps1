# you need to have all your other files in the same directory to execute this, though
# you can always move them around later when you get more familiar with it
cd 's:/Work/github/CompileTableComments' # where the directory is.
.\ParseTable.ps1 #execute the function
$VerbosePreference = "continue"
# now make sure the parser is functioning properly by giving it a couple of sample tables
# I've switched on verbose mode so you can see how the state machine works
Parse-TableDDLScript @"
/* the customer's credit card details. This is here just because this database is used as 
a nursery slope to check for personal information */
CREATE TABLE Customer.CreditCard
  (
  CreditCardID INT IDENTITY NOT NULL CONSTRAINT CreditCardPK PRIMARY KEY,
  Person_id INT NOT NULL CONSTRAINT CreditCard_PersonFK FOREIGN KEY REFERENCES Customer.Person,
  CardNumber Customer.PersonalPaymentCardNumber NOT NULL CONSTRAINT CreditCardWasntUnique UNIQUE, 
  ValidFrom DATE NOT NULL,--from when the credit card was valid
  ValidTo DATE NOT NULL,--to when the credit card was valid
  CVC Customer.PersonalCVC NOT null,--the CVC
  ModifiedDate DATETIME NOT NULL--when was this last modified
    CONSTRAINT CreditCardModifiedDateD DEFAULT (GetDate()),-- if not specified, it was now
  CONSTRAINT DuplicateCreditCardUK UNIQUE (Person_id, CardNumber) --prevend duplicate card numbers
  );
/* the email address for the person. a person can have more than one*/
CREATE TABLE Customer.EmailAddress
  (
  EmailID INT IDENTITY(1, 1) NOT NULL CONSTRAINT EmailPK PRIMARY KEY,--surrogate primary key 
  Person_id INT NOT NULL CONSTRAINT EmailAddress_PersonFK FOREIGN KEY REFERENCES Customer.Person, /*
  make the connectiopn between the person and the email address */
  EmailAddress Customer.PersonalEmailAddress  NOT NULL, --the actual email address
  StartDate DATE NOT NULL,--when we first knew about this email address
  EndDate DATE NULL,--when the customer stopped using this address
  ModifiedDate DATETIME NOT NULL
    CONSTRAINT EmailAddressModifiedDateD DEFAULT (GetDate()),
  ) ON [PRIMARY];
"@|convertto-json -depth 5
$VerbosePreference = "SilentlyContinue"

# test it out on the build script and produce a formatted list of all the tables
$content = [System.IO.File]::ReadAllText("$pwd\Customers Database Documented.sql")
(Parse-TableDDLScript $content).GetEnumerator()|
  Select @{label="Table";expression={$_.TableName}},
         @{label="Description";expression={$_.Documentation}}|
     Format-Table

#Now test it out agaiin produce a formatted list of all the components too
(Parse-TableDDLScript $content).GetEnumerator()|
  Select @{label="column";expression={$_.columns}},
        @{label="Table";expression={$_.TableName}} -PipelineVariable table|
    Foreach{$_.column} |# foreach {$table}|convertTo-json
     Select  @{label="Table";expression={$table.Table}},
             @{label="Column";expression={$_.Name}},
             @{label="DataType";expression={$_.Type}},
             @{label="Description";expression={$_.Documentation}}|Format-Table

# we test it out on a singlew table to make sure it picks up all the comments
$VerbosePreference = "Continue"
$object=Parse-TableDDLScript @"
CREATE TABLE dbo.PurchaseOrderDetail /* this provides the details of the Individual products and is used together
with General purchase order information associated with dbo.PurchaseOrderHeaderthat provides specific purchase order. */
(
    PurchaseOrderID int NOT NULL--the purchase order ID--Primary key.
        REFERENCES Purchasing.PurchaseOrderHeader(PurchaseOrderID),-- Foreign key to PurchaseOrderHeader.PurchaseOrderID.
    LineNumber smallint NOT NULL,--the line number
    ProductID int NULL --Product identification number. Foreign key to Product.ProductID.
        REFERENCES Production.Product(ProductID), --another foreign key
    UnitPrice money NULL, --Vendor's selling price of a single product.
    OrderQty smallint NULL,--Quantity ordered
    ReceivedQty float NULL,--Quantity actually received from the vendor.
    RejectedQty float NULL, -- Quantity rejected during inspection.
    DueDate datetime NOT NULL --Date the product is expected to be received.
        default (getdate()), --default duedate to today's date
    rowguid uniqueidentifier ROWGUIDCOL NOT NULL --the rowguid
        CONSTRAINT DF_PurchaseOrderDetail_rowguid DEFAULT (NEWID()),--the named constraibt
    ModifiedDate datetime NOT NULL --Date and time the record was last updated.
        CONSTRAINT DF_PurchaseOrderDetail_ModifiedDate DEFAULT (GETDATE()),--Default constraint value of GETDATE()
    LineTotal AS ((UnitPrice*OrderQty)), --Per product subtotal. Computed as OrderQty * UnitPrice.
    StockedQty AS ((ReceivedQty-RejectedQty)), --Quantity accepted into inventory. Computed as ReceivedQty - RejectedQty.
    CONSTRAINT PK_PurchaseOrderDetail_PurchaseOrderID_LineNumber --the primary key
               PRIMARY KEY CLUSTERED (PurchaseOrderID, LineNumber) --combining PurchaseOrderID and LineNumber
               WITH (IGNORE_DUP_KEY = OFF) --with options
)
ON PRIMARY;
go
"@
$object|ConvertTo-Json -Depth 5
$VerbosePreference = "SilentlyContinue"

