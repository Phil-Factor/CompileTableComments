# you need to have all your other files in the same directory to execute this, though
# you can always move them around later when you get more familiar with it

<# You need to fill in the correct connection string and the filepath where you have stored
the code #>
cd 'MyPathTo/CompileTableComments' # where the directory is.
$ConnectionString= "Data Source=MyServer;Initial Catalog=Customers;user id=MyUID;Password=MyPassword"
 
 <# here is the script for building the little sample database and making sure that all the 
comments were picked up and added to the database as extended properties  #>
.\ParseTable.ps1 #execute the function 

    <# we start with the build script, the SqlServer module, the Powershell function, the 
    Microsoft.SqlServer.Management.SqlParser parser from microsoft and the source code for 
    the import temporary #AddDocumentation procedure #>

    <#
    We need to use the System.Data.SqlClient library because we want to create a 
    connection where we can first install our temporary stored procedure and then run it. 
    We need Invoke-Sqlcmd from the SqlServer module for the build script because it has
    GO batch terminators. #>
    #get the build script
    $content = [System.IO.File]::ReadAllText("$PWD\Customers Database Documented.sql")
    # parse it to get the json model of the contents
    $JsonResult=(Parse-TableDDLScript $content)|ConvertTo-Json -Depth 5
    # now make a connection string (we use a more elaborate approach
    # we never put it in a string in a script! 
    # we execute the build script (you'll need the SQLServer library for this)
    Invoke-Sqlcmd -Query $content  -ConnectionString $connectionString
    #now we use a sqlclient connection 
    $sqlconn = New-Object System.Data.SqlClient.SqlConnection
    $sqlconn.ConnectionString = $ConnectionString
    # we now read in the code for the temporary stored procedure
    $Procedure = [System.IO.File]::ReadAllText("$PWD\AddDocumentation.sql")
    #now we make a connection and install the temporary procedure
    $cmd = New-Object System.Data.SqlClient.SqlCommand
    $cmd.Connection = $sqlconn
    $cmd.CommandTimeout = 0
    $cmd.CommandText=$Procedure
    # Now we execute the build for the temp stored procedure
    try
    {
        $sqlconn.Open()
        $cmd.ExecuteNonQuery() | Out-Null
    }
    catch [Exception]
    {
        Write-error $_.Exception.Message
    }
    # now we execute the procedure, passing the JSON as a parameter
    $HowManyUpdates=0; #initialise the output variable
    $cmd.Parameters.Clear(); # just in case you rerun it absent-mindedly
    # add in the JSON as the first input parameter
    $sqlParam1 = New-Object System.Data.SqlClient.SqlParameter("@JSON",$JsonResult)
    # add in the integer output parameter as the second parameter
    $sqlParam2 = New-Object System.Data.SqlClient.SqlParameter("@changed",$HowManyUpdates)
    $sqlParam2.Direction = [System.Data.ParameterDirection]'Output';
    $cmd.CommandText = "EXEC #AddDocumentation @JSON,@changed"
    #Add the parameters
    $Null=$cmd.Parameters.Add($sqlParam1)
    $Null=$cmd.Parameters.Add($sqlParam2)

    try
    {
         $Updates=$cmd.ExecuteNonQuery() 
    }
    catch [Exception]
    {
        Write-error $_.Exception.Message
    }
    finally
    { # the temporary procedure is cleaned out at this point
        $sqlconn.Dispose()
        $cmd.Dispose()
    }

    "We updated or created $Updates Extended properties."



