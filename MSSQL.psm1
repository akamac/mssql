$PSDefaultParameterValues = Import-PSDefaultParameterValues
try {
	#$MyInvocation.MyCommand.Module.RequiredModules does not work here
	(Test-ModuleManifest $PSScriptRoot\*.psd1).RequiredModules | % {
		Import-Module -RequiredVersion $_.Version -Name $_.Name -ea Stop
	}
} catch {
	Write-Error $_.Exception
	throw 'Failed to load required dependency'
}

#------------------------------------------------------------------------------

function New-SqlDataAdapter {
    param(
        [string] $SqlServer = '(local)',
        #[string] $Instance,
        [pscredential] $Credential,
        [Parameter(Mandatory)]
        [string] $Database,
        [Parameter(Mandatory,ParameterSetName='TableName')]
        [string] $TableName,
        [Parameter(Mandatory,ParameterSetName='SelectCommand')]
        [string] $SelectCommandText,
        [int] $UpdateBatchSize = 1
    )

    $SqlConnectionStringBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $SqlConnectionStringBuilder['Persist Security Info'] = $false
    
    if ($Credential) {
        $Credential.Password.MakeReadOnly()
        $SqlCredential = New-Object System.Data.SqlClient.SqlCredential($Credential.UserName,$Credential.Password)
        $SqlConnectionStringBuilder['Credential'] = $SqlCredential
    } else {
        $SqlConnectionStringBuilder['Integrated Security'] = $true
    }
    $SqlConnectionStringBuilder['Initial Catalog'] = $Database
    $SqlConnectionStringBuilder['Data Source'] = $SqlServer #, $Instance -join '\'
    #$SqlConnectionStringBuilder['TrustServerCertificate'] = $true
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($SqlConnectionStringBuilder.ConnectionString)
    $SqlConnection.Open()

    if ($PSCmdlet.ParameterSetName -eq 'TableName') {
        $SelectCommandText = "SELECT * FROM $TableName"
    }

    $SqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($SelectCommandText,$SqlConnection)
    $SqlDataAdapter.UpdateBatchSize = $UpdateBatchSize
    $SqlDataAdapter.MissingSchemaAction = 'AddWithKey'
    #$SqlDataAdapter.TableMappings
    #$SqlDataAdapter.FillLoadOption LoadOption.Upsert or LoadOption.PreserveChanges
    
    $SqlDataAdapter
}

function Invoke-SqlDb {
    param(
        [Parameter(Mandatory)]
        [System.Data.SqlClient.SqlDataAdapter] $SqlDataAdapter,
        [Parameter(Mandatory,ParameterSetName='Select')]
        [switch] $Select,
        [Parameter(ParameterSetName='Select')]
        [switch] $FillSchemaOnly,
        [Parameter(Mandatory,ParameterSetName='Update')]
        [switch] $Update,
        [Parameter(Mandatory,ParameterSetName='BulkInsert')]
        [switch] $BulkInsert,
        [Parameter(ParameterSetName='Select')]
        [Parameter(Mandatory,ParameterSetName='Update')]
        [Parameter(Mandatory,ParameterSetName='BulkInsert')]
        [System.Data.DataSet] $DataSet
        
    )
    $TableName = ([regex]'FROM ([\w\.]+)').Match($SqlDataAdapter.SelectCommand.CommandText).Groups[1].Value
    # AS handling
    switch ($PSCmdlet.ParameterSetName) {
        Select {
            if (-not $DataSet) {
                $DataSet = New-Object System.Data.DataSet #($TableName)
            }
            if ($FillSchemaOnly.IsPresent) {
                $SqlDataAdapter.FillSchema($DataSet,[System.Data.SchemaType]::Source) #,$TableName)
            } else {
                [void]$SqlDataAdapter.Fill($DataSet) #,$TableName)
            }
            $DataSet
        }
        Update {
            $SqlCommandBuilder = New-Object System.Data.SqlClient.SqlCommandBuilder($SqlDataAdapter)
            #$SqlCommandBuilder.SetAllValues = $true
            $SqlCommandBuilder.SchemaSeparator = '.'
            $SqlCommandBuilder.QuotePrefix = '['
            $SqlCommandBuilder.QuoteSuffix = ']'
            [void]$SqlCommandBuilder.GetDeleteCommand($true)
            [void]$SqlCommandBuilder.GetUpdateCommand($true)
            [void]$SqlCommandBuilder.GetInsertCommand($true)
            $Count = $SqlDataAdapter.Update($DataSet)
			Write-Verbose "$Count rows updated"
        }
        BulkInsert {
            $BulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($SqlDataAdapter.SelectCommand.Connection)
            $BulkCopy.DestinationTableName = "dbo.$TableName"
            #$BulkCopy.BatchSize
            #$BulkCopy.EnableStreaming
            <#
            ($Data | Get-Member -MemberType Property).Name | % {
                [void]$BulkCopy.ColumnMappings.Add($_, $_)
            }
            #>
            $BulkCopy.WriteToServer($DataSet)
            #WriteToServer(DataRow[])
            #WriteToServer(IDataReader)
        }
    }
}

function Invoke-SqlCommand {
    param(
        [string] $SqlServer = '(local)',
        [pscredential] $Credential,
		[string] $Database,
        [Parameter(Mandatory,ParameterSetName='Command')]
        [string] $CommandText,
		[ValidateSet('Reader','NonQuery','Scalar')]
		[string] $CommandType = 'NonQuery'
    )
    $SqlConnectionStringBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $SqlConnectionStringBuilder['Persist Security Info'] = $false
    
    if ($Credential) {
        $Credential.Password.MakeReadOnly()
        $SqlCredential = New-Object System.Data.SqlClient.SqlCredential($Credential.UserName,$Credential.Password)
        $SqlConnectionStringBuilder['Credential'] = $SqlCredential
    } else {
        $SqlConnectionStringBuilder['Integrated Security'] = $true
    }
    $SqlConnectionStringBuilder['Initial Catalog'] = $Database
    $SqlConnectionStringBuilder['Data Source'] = $SqlServer #, $Instance -join '\'
    #$SqlConnectionStringBuilder['TrustServerCertificate'] = $true
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($SqlConnectionStringBuilder.ConnectionString)
    $SqlConnection.Open()

    $SqlCommand = New-Object System.Data.SqlClient.SqlCommand($CommandText,$SqlConnection)
	switch ($CommandType) {
		Reader {
			$SqlDataReader = $SqlCommand.ExecuteReader()
			$Result = New-Object System.Collections.ArrayList
			[array]$ColumnName = $SqlDataReader.GetSchemaTable().ColumnName
			$Row = New-Object Object[] $SqlDataReader.FieldCount
			$ht = [ordered]@{}
			while ($SqlDataReader.Read()) {
				[void]$SqlDataReader.GetValues($Row)
				for ($i = 0; $i -lt $Row.Count; ++$i) {
					$ht[$ColumnName[$i]] = $Row[$i]
				}
				[void]$Result.Add((New-Object PSCustomObject -Property $ht))
			}
			$Result
		}
		NonQuery {
			$SqlCommand.ExecuteNonQuery()
		}
		Scalar {
			$SqlCommand.ExecuteScalar()
		}
	}
    $SqlConnection.Close()
}

function Load-DataRows {
    param(
        [Parameter(Mandatory)]
        [System.Data.DataSet] $DataSet,
        [Parameter(Mandatory)]
        $Data # array of PSCustomObject
    )
    $DataTable = $DataSet.Tables['Table']
    foreach ($Obj in $Data) {
        $ArrayList = New-Object System.Collections.ArrayList
		$DataTable.Columns.ColumnName.ForEach({ [void]$ArrayList.Add($Obj.$_) })
        $DataTable.LoadDataRow($ArrayList.ToArray(),[System.Data.LoadOption]::Upsert)
        $ArrayList.Clear()
    }
	#Write-Verbose "$(@($Data).Count) rows loaded"
}