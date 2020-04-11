
 import-module sqlserver 
 
 function Parse-TableDDLScript
{
  param
  (
    $Sql # the string containing one or more SQL Server tables
  )
<#
This uses the Microsoft parser to iterate through the tokens and construct enough details of 
the table to get the various components such as columns, constraints and inline indexes, along
with the comments and documentation
#>
  $msms = 'Microsoft.SqlServer.Management.SqlParser'
  $Assembly = [System.Reflection.Assembly]::LoadWithPartialName("$msms")
  $psr = "$msms.Parser"
  $ParseOptions = New-Object "$psr.ParseOptions"
  $ParseOptions.BatchSeparator = 'GO'
  $anonymous=1 #the number of anonymous constraints
  $FirstScript = [Microsoft.SqlServer.Management.SqlParser.Parser.Parser]::Parse(
    $SQL, $ParseOptions)
  $State = 'StartOfExpression' #this is the current state
  $TableDetails = @{ TableName = $null; Documentation = $null; 
                     Columns = @(); Constraints = @(); Indexes = @() }
  $AllTablesDetails = @() #the returned list of tableDetails found in the script
  $ListItemType = 'unknown' # we start y not knowing what sort of object is in the create staement
  $LineCommentRegex = [regex] '(?im)--(.*)\r' # to clean up an end-of-line comment
  $MultiLineCommentRegex = [regex] '(?ism)/\*(.*)\*/' # to clean up a block comment
  $ListItemDetails = @{ } #the details of the current column found if any
  $ExpressionLevel = 0 #used to work out whether you are in an expression
  $FirstScript.script.tokens | select Text, Id, Type | foreach {
    # if this works out, we've found the first create statement
    if ($_.Type -eq ';') { $State = 'StartOfExpression' }
    Write-Verbose "State:'$state', Type:'$($_.Type)', Expressionlevel:'$ExpressionLevel' ListItemType:'$ListItemType'"
    if ($_.Type -eq 'TOKEN_CREATE')
    {
      #If the state is 'initialBlock, it is  expecting a create statement 
      if ($state -eq 'initialBlock') 
        { $blockComment = $TableDetails.Documentation }; #because it is cleared out
      $state = 'CreateStatement' # change state
    }
    # now we need to keep tabs of the expression level based on the nesting of the brackets
    if ($_.Type -eq '(') { $ExpressionLevel++ } #to deal with bracketed expressions- start of expression
    if ($_.Type -eq ')')
    {
      $ExpressionLevel--;
      if ($ExpressionLevel -eq 0)
      {
        # end of the table script so save anything and initialise.
        # deal with the problem of having several CREATE statements in a batch
        if (($state -ne 'CreateStatement') -or ($_.Type -eq 'LEX_BATCH_SEPERATOR')) 
        { $State = 'StartOfExpression'; }
        # here we reset the state, expression level and ListItem type
        $ExpressionLevel = 0;
        $ListItemType = 'unknown';
        
        if ($TableDetails.TableName -ne $null) #then there is something there
        {
          Write-Verbose "storing table $($TableDetails.TableName)";
          $AllTablesDetails += $TableDetails;
        }
        
        write-verbose "$state zapping table details"
        $TableDetails = @{ TableName = $null; Documentation = $null; 
                           Columns = @(); Indexes = @(); Constraints = @() }
        $blockcomment = $null;
      } #save any existing table 
      
    } #to deal with bracketed expressions- end of expression
    #is it the start of a list?
    if (($_.Type -eq '(') -and ($ExpressionLevel -eq 1)) { $ListItemType = 'unknown' }
    # if we definitely have a CREATE TABLE so...
    if ($state -notin ('CreateStatement', 'StartOfExpression')) 
    {
      # Do we need to save any current object and then reinitialise?
      # to keep this operation in one place we have some complicated condition tests here
      if (($_.Type -eq ',' -and $ExpressionLevel -eq 1 #if it is the start of a new list item
        ) -or ($_.Type -in @('LEX_BATCH_SEPERATOR',
            'TOKEN_INDEX',
            'TOKEN_CONSTRAINT') #change in object being defined
        ) -or ($_.Type -eq ')' -and $expressionLevel -eq 0
        # or it is one of the anonymous constraints such as a default constraint or a foreign key constraint
        ) -or (($ListItemType -ne 'Constraint') -and
             ($_.Type -in @('TOKEN_FOREIGN','TOKEN_DEFAULT','TOKEN_REFERENCES'))))
      { #we've found a new component of the table
        # we have to make sure that we've got the current line saved
        $State = 'startOfLine'; #OK. This is the start of a list item of the create statement
        #we save the details of the previous list item
        if ($ListItemDetails.Name -ne $null) # if it exists, save it
        {
          if ($ListItemType -eq 'column')
          {
            # if we are needing to save the column whose details we collected ...
            $TableDetails.columns += $ListItemDetails;
            Write-Verbose "column found $($ListItemDetails.Name) $($ListItemDetails.Documentation)";
          }
          if ($ListItemType -eq 'constraint')
          {
            # if we are needing to save the constraint whose details we assembled ...
            $TableDetails.constraints += $ListItemDetails;
            Write-Verbose "constraint found and added to $($TableDetails.constraints | convertto-json)";
          }
          if ($ListItemType -eq 'index')
          {
            # if we are needing to save the index whose details we gathered ...
            $TableDetails.Indexes += $ListItemDetails;
            Write-Verbose "Index found $($ListItemDetails.Name) $($ListItemDetails.Documentation)";
          } # so now we try to work out what sort if list item we have
          if ($_.Type -in @('TOKEN_CONSTRAINT', 'TOKEN_FOREIGN'))
          { $ListItemType = 'constraint' }
          elseif ($_.Type -eq 'TOKEN_INDEX') { $ListItemType = 'index' }
          elseif ($_.Type -eq 'TOKEN_REFERENCES')
          {
            $ListItemType = 'constraint'
            $State = 'Identifier';
            $ListItemDetails = 
               @{ Name = '*FK'+($anonymous++); 
                  Documentation = $null ; 
                  Type = 'Foreign key (anonymous) for '+$ListItemdetails.Name };
          }
          elseif ($_.Type -eq 'TOKEN_DEFAULT')
          {
            $ListItemType = 'constraint'
            $State = 'Identifier';
            $ListItemDetails = 
               @{ Name = '*D'+($anonymous++); 
                  Documentation = $null; 
                  Type = 'Default (anonymous) for '+$ListItemdetails.Name  };
          }         else { $ListItemType = 'unknown' }
        }
      }
    } #end of list item (column or table constraint or index)
    if ($State -eq 'CreateStatement')
    #we are looking for the first token which will be a table name. 
    #If no table name, the expression must be ignored.
    {
      if ($_.Type -eq 'TOKEN_TABLE')
      { $state = 'WhatNameIsTable'; $ListItemType = 'table' }
      #the table can be in several different consecutive tokens following this
    };
    if ($State -eq 'identifier') # it could be adding the NOT NULL constraint
        {if ($_.Type -eq 'TOKEN_NOT') {$ListItemDetails.Type+=' NOT'}
         if ($_.Type -eq 'TOKEN_NULL') {$ListItemDetails.Type+=' NULL'}
        }
    # we may want to remember the actual data type of a column. This token follows a column name 
    if (($State -eq 'GetDataType') -and ($_.Type -eq 'TOKEN_ID') -and $ExpressionLevel -eq 1)
    { $ListItemDetails.Type = $_.Text; $State = 'identifier' }
    #we need to react according to the type of list item/line being written
    if (($State -eq 'startOfLine')) 
    {
      if (($_.Type -eq 'TOKEN_WITH') -and ($ExpressionLevel -eq 0)) #
      { $State = 'with' } # a TableOption expression is coming
      if (($_.Type -eq 'TOKEN_ON') -and ($ExpressionLevel -eq 0)) #
      { $State = 'on' } # a TableOption expression is coming
      if ($_.Type -eq 'TOKEN_ID')
      {
        if ($ListItemType -eq 'unknown') { $ListItemType = 'column' };
        $ListItemDetails = @{ Name = $_.Text; Documentation = $null; Type = '' };
        $State = 'GetDataType';
      };
    };
    #now save the tokens that tell us about the type of the object
    if ($_.Type -eq 'TOKEN_CLUSTERED') { $ListItemDetails.type += 'Clustered ' }
    if ($_.Type -eq 'TOKEN_NONCLUSTERED') { $ListItemDetails.type += 'NonClustered ' }
    if ($_.Type -eq 'TOKEN_UNIQUE') { $ListItemDetails.type += 'Unique ' } # Token_on
    if ($_.Type -eq 'TOKEN_PRIMARY') { $ListItemDetails.type += 'Primary ' } # Token_on
    if ($_.Type -eq 'TOKEN_ROWGUIDCOL') { $ListItemDetails.type += 'RowguidCol ' }
    if ($_.Type -eq 'TOKEN_DEFAULT') { $ListItemDetails.type += 'Default ' }
    if ($_.Type -eq 'TOKEN_AS') { $ListItemDetails.type += ' computed' }
    if ($_.Type -eq 'TOKEN_s_CTW_DATA_COMPRESSION') { $tableDetails.type += 'Data-compression ' }
    # if we his a batch separator (eg Go) then we save the current table if there is one
    if ($_.Type -in @('LEX_BATCH_SEPERATOR'))
    {
      #gone to expressionLevel
      $State = 'StartOfExpression'
    };
    # store any comments with the current object
    if ($State -in @('startOfLine', 'Identifier', 'GetDataType'))
    {
      if ($_.Type -eq 'LEX_END_OF_LINE_COMMENT')
      {
        # one has to strip out the delimiters in both cases
        $ListItemDetails.Documentation += $LineCommentRegex.Replace($_.Text, '${1}');
      }
      if ($_.Type -eq 'LEX_MULTILINE_COMMENT')
      {
        $ListItemDetails.Documentation += $MultiLineCommentRegex.Replace($_.Text, '${1}');
      }
    }
    if ($State -eq 'WhatNameIsTable') # we are trying to find out the name of the table
    {
      if ($_.Type -in @('TOKEN_ID', '.'))
      {
        $TableDetails.TableName += $_.Text;
        Write-Verbose "Table name found $($TableDetails.TableName)";
      }
      if ($_.Type -eq '(' -and $ExpressionLevel -eq 1) { $State = 'startOfLine' };
    };
    if ($_.Type -eq 'LEX_MULTILINE_COMMENT')
    # deal with multiline comments that can be associated with a table
    {
      $blockComment = $MultiLineCommentRegex.Replace($_.Text, '${1}')
      if (($ListItemType -in ('table')) -or 
                ($state -in @('StartOfExpression', 'initialBlock')))
      { $TableDetails.Documentation += $blockComment; $blockComment = $null }
      Write-Verbose "Found block comment $($_.Text) "
      if ($state -eq 'StartOfExpression') { $state = 'InitialBlock' }
      
    }
    
  }
  
  # now we add the table to the list of tables
  
  if ($TableDetails.TableName -ne $null)
  {
    $AllTablesDetails += $TableDetails;
    $TableDetails = @{ TableName = $null; Documentation = $null; 
                       Columns = @(); indexes = @(); constraints = @() }
    
  }
  Write-Verbose "found $($AllTablesDetails.count) tables"
  $AllTablesDetails
}

