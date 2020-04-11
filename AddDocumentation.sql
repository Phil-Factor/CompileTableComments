CREATE OR alter PROCEDURE #AddDocumentation 
@JSON NVARCHAR(MAX), @changed INT output
/**
Summary: >
  This procedure takes a JSON document created by 
  the PowerShell SQL Table Parser and either updates
  or creates the documentation in Extended properties
  in the database.
  It checks that all the columns and constraints
  are there as specified in the JSON file to ensure
  that you are sending documentation to the right
  version of the database
Author: Phil Factor
Date: 03/04/2020
Examples:
   - DECLARE @numberChanged int
     EXECUTE #AddDocumentation @json, @numberChanged OUTPUT
     SELECT @NumberChanged

Returns: >
  The number of updates or insertions of documention done
**/
AS
BEGIN
/* this table contains the parameters required for the Extended properties
 stored procedures, and some columns used merely for expanding the JSON */
CREATE TABLE #EPParentObjects
  (
  TheOneToDo INT IDENTITY(1, 1),
  level0_type VARCHAR(128) NULL,
  level0_Name sysname NULL,
  level1_type VARCHAR(128) NULL,
  level1_Name sysname NULL,
  level2_type VARCHAR(128) NULL,
  level2_Name sysname NULL,
  [Description] NVARCHAR(3750) NULL,
  [columns] NVARCHAR(MAX) NULL,
  [indexes] NVARCHAR(MAX) NULL,
  constraints NVARCHAR(MAX) NULL
  );
-- insert the tables into the #EPParentObjects table with their details
--the details are saved as JSON documents, lists of columns, indexes or constraints.
  INSERT INTO #EPParentObjects
  (level0_type, level0_Name, level1_type, level1_Name, level2_type,
  level2_Name, [Description], [columns], [indexes], constraints)
SELECT 'schema' AS level0_type, Coalesce(ParseName(Name, 2),'DBO') AS level0_Name,
      'Table' AS level1_type , ParseName(Name, 1)  AS level1_Name, 
	  NULL AS Level2_type,NULL AS Level2_name,
	  [Description],[columns],[indexes],constraints
	  FROM OpenJson(@JSON)
   WITH
      (
      Name SYSNAME '$.TableName', 
      Description NVARCHAR(3876) '$.Documentation',
      [columns] NVARCHAR(MAX) '$.Columns' AS JSON,
      [indexes] NVARCHAR(MAX) '$.Indexes' AS JSON,
      [constraints] NVARCHAR(MAX) '$.Constraints' AS JSON
      ) AS BaseObjects;

-- Now we simply cross-apply the contents of the table with the OpenJSON function
-- for every list (columns,indexes and constraints). By using a UNION, we can do
-- it all in one statement
INSERT INTO #EPParentObjects
 (level0_type, level0_Name, level1_type, level1_Name, level2_type,
    level2_Name, Description)
SELECT level0_type, level0_Name, level1_type, level1_Name, 
	  'Column' AS level2_type, name AS level2_Name, documentation
FROM #EPParentObjects 
CROSS APPLY OpenJson([Columns])
 WITH
      (
      Name SYSNAME '$.Name', 
      documentation NVARCHAR(3876) '$.Documentation'
      ) WHERE documentation IS NOT null
UNION ALL
SELECT level0_type, level0_Name, level1_type, level1_Name,
	 'Constraint' AS level2_type, name AS level2_Name, documentation
FROM #EPParentObjects 
CROSS APPLY OpenJson([Constraints])
 WITH
      (
      Name SYSNAME '$.Name', 
      documentation NVARCHAR(3876) '$.Documentation'
      ) WHERE (documentation IS NOT NULL)  AND (level2_name NOT LIKE '*#')
UNION ALL
SELECT level0_type, level0_Name, level1_type, level1_Name,
    'Index' AS level2_type, name AS level2_Name, documentation
FROM #EPParentObjects 
CROSS APPLY OpenJson([Indexes])
 WITH
      (
      Name SYSNAME '$.Name', 
      documentation NVARCHAR(3876) '$.Documentation'
      ) WHERE documentation IS NOT null

/* the next thing to do is to check that all the objects have corresponding objects in
the database. If not, then I raise an error as something is wrong. You could, of course
do something milder such as removing failed lines from the result but I wouldn't advise
it unless you were excpoecting it! */
--first we check the tables
IF EXISTS (SELECT * FROM #EPParentObjects e
	LEFT OUTER JOIN sys.tables
	ON e.level1_Name=tables.name
	AND e.level0_Name=Object_Schema_Name(tables.object_id)
	WHERE tables.object_id IS NULL)
	  RAISERROR('Sorry, but there are one or more tables that aren''t in the DATABASE',16,1)
--now we check the constrints
IF EXISTS (SELECT * FROM #EPParentObjects e
	LEFT OUTER JOIN sys.objects o
	ON  e.level0_Name=Object_Schema_Name(o.parent_object_id)
	AND e.level1_Name=Object_Name(o.parent_object_id)
	AND e.level2_Name=o.name AND level2_type ='constraint'
	WHERE level2_type ='constraint' AND e.level2_Name NOT LIKE '*%' -- not an anonymous constraint
	AND o.object_id IS null
) RAISERROR('Sorry, but there are one or more constraints that aren''t in the DATABASE',16,1)
--finally we check the columns.
IF EXISTS (SELECT * FROM #EPParentObjects e
	LEFT OUTER JOIN  sys.columns c
	ON  e.level0_Name=Object_Schema_Name(c.object_id)
	AND e.level1_Name=Object_Name(c.object_id)
	AND e.level2_Name=c.name
	where e.level2_name IS NOT NULL AND level2_type ='Column'
	and c.column_id IS null
) RAISERROR('Sorry, but there are one or more columns that aren''t in the DATABASE',16,1)
--indexes should be checked in the same way, probably, but these are less frequent.

--we now iterate through all the lines of the table. Notice that I don't delete 
--documentation if the corresponding JSON record has a null. I just think that
--it is a bad way of deleting documentation. It is easy to add.
DECLARE @iiMax int= (SELECT Max(TheOneToDo) FROM #EPParentObjects)
 DECLARE @level0_type VARCHAR(128), @level0_Name sysname,
        @level1_type VARCHAR(128),@level1_Name sysname,
        @level2_type VARCHAR(128),@level2_Name sysname,@Description nvarchar (3750),
        @NeedsChanging BIT,@DidntExist BIT
DECLARE @ii INT =1
SELECT @Changed =0
WHILE @ii<=@iiMax
    BEGIN
    SELECT @level0_type =level0_type, @level0_Name=level0_Name,
        @level1_type =level1_type,@level1_Name =level1_Name,
        @level2_type=level2_type,@level2_Name =level2_Name,@Description=[description]
        FROM #EPParentObjects WHERE TheOneToDo=@ii
        SELECT @NeedsChanging=CASE WHEN value=@description THEN 0 ELSE 1 end --so what is there existing?
            FROM fn_listextendedproperty ('ms_description',
             @level0_type,@level0_Name,@level1_type,
              @level1_Name,@level2_type,@level2_Name) 
        IF @@RowCount=0 SELECT @DidntExist=1, @NeedsChanging=CASE WHEN @description IS NULL  THEN 0 ELSE 1 END
        IF @NeedsChanging =1
            BEGIN
            SELECT @Changed=@Changed+1
            IF @DidntExist=1
              EXEC sys.sp_addextendedproperty 'ms_description',@description,
                @level0_type,@level0_Name,@level1_type,
                @level1_Name,@level2_type,@level2_Name
            ELSE
              EXEC sys.sp_Updateextendedproperty  'ms_description',@description,
                @level0_type,@level0_Name,@level1_type,
                @level1_Name,@level2_type,@level2_Name 
            
            end
        SELECT @ii=@ii+1
    END
END

