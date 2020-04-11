USE master;
GO

IF NOT EXISTS (SELECT databases.name FROM sys.databases WHERE databases.name LIKE 'customers') CREATE DATABASE customers;
GO

USE customers;
GO

--only create the Customer schema if it does not exist
IF EXISTS (SELECT * FROM sys.schemas WHERE schemas.name LIKE 'Customer') SET NOEXEC ON;
GO
CREATE SCHEMA Customer;
GO

--
SET NOEXEC OFF;

--delete the table with all the foreign key references in it
IF Object_Id('Customer.EmailAddress') IS NOT NULL DROP TABLE Customer.EmailAddress;
GO

IF Object_Id('Customer.Abode') IS NOT NULL DROP TABLE Customer.Abode;
GO

IF Object_Id('Customer.NotePerson') IS NOT NULL DROP TABLE Customer.NotePerson;
GO
IF Object_Id('Customer.Note') IS NOT NULL DROP TABLE Customer.Note;
GO
IF Object_Id('Customer.Phone') IS NOT NULL DROP TABLE Customer.Phone;
GO

IF Object_Id('Customer.CreditCard') IS NOT NULL DROP TABLE Customer.CreditCard;
GO

IF Object_Id('Customer.Person') IS NOT NULL DROP TABLE Customer.Person;
GO

IF Object_Id('Customer.Address') IS NOT NULL DROP TABLE Customer.Address;
GO

DROP TYPE IF EXISTS Customer.PersonalName;
DROP TYPE IF EXISTS Customer.PersonalTitle;
DROP TYPE IF EXISTS Customer.PersonalPhoneNumber;
DROP TYPE IF EXISTS Customer.PersonalAddressline;
DROP TYPE IF EXISTS Customer.PersonalLocation;
DROP TYPE IF EXISTS Customer.PersonalPostalCode;
DROP TYPE IF EXISTS Customer.PersonalSuffix;
DROP TYPE IF EXISTS Customer.PersonalNote;
DROP TYPE IF EXISTS Customer.PersonalPaymentCardNumber;
DROP TYPE IF EXISTS Customer.PersonalEmailAddress;
DROP TYPE IF EXISTS Customer.PersonalCVC

CREATE TYPE Customer.PersonalName FROM NVARCHAR(40) NOT null;
CREATE TYPE Customer.PersonalTitle FROM NVARCHAR(10) NOT null;
CREATE TYPE Customer.PersonalNote FROM NVARCHAR(Max) NOT null;
CREATE TYPE Customer.PersonalPhoneNumber FROM VARCHAR(20) NOT null;
CREATE TYPE Customer.PersonalAddressline FROM VARCHAR(60);
CREATE TYPE Customer.PersonalLocation FROM VARCHAR(20);
CREATE TYPE Customer.PersonalPostalCode FROM VARCHAR(15) NOT null;
CREATE TYPE Customer.PersonalEmailAddress FROM NVARCHAR(40) NOT null;
CREATE TYPE Customer.PersonalSuffix FROM NVARCHAR(10);
CREATE TYPE Customer.PersonalPaymentCardNumber FROM VARCHAR(20) NOT null;
CREATE TYPE Customer.PersonalCVC FROM CHAR(3) NOT NULL
GO


/* This table represents a person- can be a customer or a member of staff,
or someone in one of the outsourced support agencies*/
CREATE TABLE Customer.Person
  (
  person_ID INT NOT NULL IDENTITY CONSTRAINT PersonIDPK PRIMARY KEY,--  has to be surrogate
  Title Customer.PersonalTitle NOT null, -- the title (Mr, Mrs, Ms etc
  Nickname Customer.PersonalName null, -- the way the person is usually addressed
  FirstName Customer.PersonalName, -- the person's first name
  MiddleName Customer.PersonalName null, --any middle name 
  LastName Customer.PersonalName, -- the lastname or surname 
  Suffix Customer.PersonalSuffix NULL, --any suffix used by the person
  fullName AS --A calculated column
    (Coalesce(Title + ' ', '') + FirstName + Coalesce(' ' + MiddleName, '')
     + ' ' + LastName + Coalesce(' ' + Suffix, '')
    ),
  ModifiedDate DATETIME NOT NULL --when the record was last modified
    CONSTRAINT PersonModifiedDateD DEFAULT GetDate() --the current date by default
  );

CREATE NONCLUSTERED INDEX SearchByPersonLastname /* this is an index associated with 
Customer.Person */
ON Customer.Person (LastName ASC, FirstName ASC)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF,
     DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON,
     ALLOW_PAGE_LOCKS = ON
     );
GO



CREATE TABLE Customer.Address /*This contains the details of an addresss,
any address, it can be a home, office, factory or whatever */
  (
  Address_ID INT IDENTITY /*surrogate key */ CONSTRAINT AddressPK PRIMARY KEY,--the unique key 
  AddressLine1 Customer.PersonalAddressline NULL, --first line address
  AddressLine2 Customer.PersonalAddressline NULL,/* second line address */
  City Customer.PersonalLocation NULL,/* the city */
  County Customer.PersonalLocation NOT NULL, /* county or state */
  PostCode Customer.PersonalPostalCode NOT NULL, ---the zip code or post code
  Full_Address AS --A calculated column
    (Stuff(
            Coalesce(', ' + AddressLine1, '')
            + Coalesce(', ' + AddressLine2, '') + Coalesce(', ' + City, '')
            + Coalesce(', ' + County, '') + Coalesce(', ' + PostCode, ''),
            1,
            2,
            ''
          )
    ),
  ModifiedDate DATETIME NOT NULL --when the record was last modified
    CONSTRAINT AddressModifiedDateD DEFAULT GetDate(), --if necessary, now.
  CONSTRAINT Address_Not_Complete CHECK (Coalesce(
AddressLine1, AddressLine2, City, PostCode
) IS NOT NULL
)
  );--check to ensure that the address was valid
GO

IF Object_Id('Customer.AddressType') IS NOT NULL DROP TABLE Customer.AddressType;
GO

CREATE TABLE Customer.AddressType /* the  way that a particular customer is using
the address (e.g. Home, Office, hotel etc */
  (
  TypeOfAddress NVARCHAR(40) NOT NULL --description of the type of address
    CONSTRAINT TypeOfAddressPK PRIMARY KEY, --ensure that there are no duplicates
  ModifiedDate DATETIME NOT NULL --when was this record LAST modified
    CONSTRAINT AddressTypeModifiedDateD DEFAULT GetDate()-- in case nobody fills it in
  );
GO

IF Object_Id('Customer.Abode') IS NOT NULL DROP TABLE Customer.Abode;
GO

CREATE TABLE Customer.Abode /* an abode describes the association has with an
address and  the period of time when the person had that association*/
  (
  Abode_ID INT IDENTITY --the surrogate key
     CONSTRAINT AbodePK PRIMARY KEY, --because it is the only unique column
  Person_id INT NOT NULL --the id of the person
     CONSTRAINT Abode_PersonFK FOREIGN KEY REFERENCES Customer.Person,
  Address_id INT NOT NULL --the id of the address
     CONSTRAINT Abode_AddressFK FOREIGN KEY REFERENCES Customer.Address,
  TypeOfAddress NVARCHAR(40) NOT NULL --the type of address
     CONSTRAINT Abode_AddressTypeFK FOREIGN KEY REFERENCES Customer.AddressType,
  Start_date DATETIME NOT NULL, --when this relationship started 
  End_date DATETIME NULL, --when this relationship ended
  ModifiedDate DATETIME NOT NULL --when this record was last modified
     CONSTRAINT AbodeModifiedD DEFAULT GetDate()--when the abode record was created/modified
  );

IF Object_Id('Customer.PhoneType') IS NOT NULL DROP TABLE Customer.PhoneType;
GO
/* the description of the type of the phone (e.g. Mobile, Home, work) */
CREATE TABLE Customer.PhoneType
  (
  TypeOfPhone NVARCHAR(40) NOT NULL
  --a description of the type of phone
    CONSTRAINT PhoneTypePK PRIMARY KEY,-- assures unique and indexed
  ModifiedDate DATETIME NOT NULL --when this record was last modified
    CONSTRAINT PhoneTypeModifiedDateD DEFAULT GetDate()
	--when the abode record was created/modified
  );


CREATE TABLE Customer.Phone 
/* the actual phone number, and relates it to the person and the type of phone */
  (
  Phone_ID INT IDENTITY --the surrogate key
    CONSTRAINT PhonePK PRIMARY KEY, --defunes the phone_id as being the primry key
  Person_id INT NOT NULL --the person who has the phone number
    CONSTRAINT Phone_PersonFK FOREIGN KEY REFERENCES Customer.Person,
  TypeOfPhone NVARCHAR(40) NOT NULL /*the type of phone*/ FOREIGN KEY REFERENCES Customer.PhoneType,
  DiallingNumber  Customer.PersonalPhoneNumber NOT null,--the actual dialling number 
  Start_date  DATETIME NOT NULL, -- when we first knew thet the person was using the number
  End_date DATETIME NULL, -- if not null, when the person stopped using the number
  ModifiedDate DATETIME NULL --when the record was last modified
    CONSTRAINT PhoneModifiedDateD DEFAULT GetDate()-- to make data entry easier!
  );

CREATE TABLE Customer.Note /* a note relating to a customer */
  (
  Note_id INT IDENTITY CONSTRAINT NotePK PRIMARY KEY, --the surrogate primary key
  Note Customer.PersonalNote NOT null,
  NoteStart AS
    Coalesce(Left(Note, 850), 'Blank' + Convert(NvARCHAR(20), Rand() * 20))
	/*making it easier to search ...*/,
  --CONSTRAINT NoteStartUQ UNIQUE,
  InsertionDate DATETIME NOT NULL --when the note was inserted
    CONSTRAINT NoteInsertionDateDL DEFAULT GetDate(),
  InsertedBy sysname NOT NULL CONSTRAINT GetUserName DEFAULT CURRENT_USER, ---who inserted it
  /* we add a ModifiedDate as usual */
  ModifiedDate DATETIME NOT NULL CONSTRAINT NoteModifiedDateD DEFAULT GetDate()
  );

CREATE TABLE Customer.NotePerson /* relates a note to a person */
  (
  NotePerson_id INT IDENTITY CONSTRAINT NotePersonPK PRIMARY KEY,
  Person_id INT NOT NULL CONSTRAINT NotePerson_PersonFK FOREIGN KEY REFERENCES Customer.Person,
  --the person to whom the note applies
  Note_id INT NOT NULL CONSTRAINT NotePerson_NoteFK FOREIGN KEY REFERENCES Customer.Note,
  /* the note that applies to the person */
  InsertionDate DATETIME NOT NULL /* whan the note was inserted */
    CONSTRAINT NotePersonInsertionDateD DEFAULT GetDate(),
  ModifiedDate DATETIME NOT NULL /* whan the note was last modified */
    CONSTRAINT NotePersonModifiedDateD DEFAULT GetDate(),
  CONSTRAINT DuplicateUK UNIQUE (Person_id, Note_id, InsertionDate) 
  /* constraint to prevent duplicates*/
  );

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
/* the email address for the person. a person can have more than one */
CREATE TABLE Customer.EmailAddress
  (
  EmailID INT IDENTITY(1, 1) NOT NULL CONSTRAINT EmailPK PRIMARY KEY,--surrogate primary key 
  Person_id INT NOT NULL CONSTRAINT EmailAddress_PersonFK FOREIGN KEY REFERENCES Customer.Person, /*
  make the connectiopn between the person and the email address */
  EmailAddress Customer.PersonalEmailAddress  NOT NULL, --the actual email address
  StartDate DATE NOT NULL DEFAULT (GetDate()),--when we first knew about this email address
  EndDate DATE NULL,--when the customer stopped using this address
  ModifiedDate DATETIME NOT NULL
    CONSTRAINT EmailAddressModifiedDateD DEFAULT (GetDate()),
  ) ON [PRIMARY];
GO

