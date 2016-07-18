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
        [Parameter(Mandatory,ValueFromPipeline)]
        [array] $Data # array of PSCustomObject
    )
    Begin { $DataTable = $DataSet.Tables['Table'] }
    Process {
        foreach ($Obj in $Data) {
            $ArrayList = New-Object System.Collections.ArrayList
		    $DataTable.Columns.ColumnName.ForEach({ [void]$ArrayList.Add($Obj.$_) })
            $DataTable.LoadDataRow($ArrayList.ToArray(),[System.Data.LoadOption]::Upsert)
            $ArrayList.Clear()
        }
	    #Write-Verbose "$(@($Data).Count) rows loaded"
    }
}
# SIG # Begin signature block
# MIIXkgYJKoZIhvcNAQcCoIIXgzCCF38CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUNnNqennqaUm1xNJ3EsbwWjeB
# CcOgghJVMIIEFDCCAvygAwIBAgILBAAAAAABL07hUtcwDQYJKoZIhvcNAQEFBQAw
# VzELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExEDAOBgNV
# BAsTB1Jvb3QgQ0ExGzAZBgNVBAMTEkdsb2JhbFNpZ24gUm9vdCBDQTAeFw0xMTA0
# MTMxMDAwMDBaFw0yODAxMjgxMjAwMDBaMFIxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMSgwJgYDVQQDEx9HbG9iYWxTaWduIFRpbWVzdGFt
# cGluZyBDQSAtIEcyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlO9l
# +LVXn6BTDTQG6wkft0cYasvwW+T/J6U00feJGr+esc0SQW5m1IGghYtkWkYvmaCN
# d7HivFzdItdqZ9C76Mp03otPDbBS5ZBb60cO8eefnAuQZT4XljBFcm05oRc2yrmg
# jBtPCBn2gTGtYRakYua0QJ7D/PuV9vu1LpWBmODvxevYAll4d/eq41JrUJEpxfz3
# zZNl0mBhIvIG+zLdFlH6Dv2KMPAXCae78wSuq5DnbN96qfTvxGInX2+ZbTh0qhGL
# 2t/HFEzphbLswn1KJo/nVrqm4M+SU4B09APsaLJgvIQgAIMboe60dAXBKY5i0Eex
# +vBTzBj5Ljv5cH60JQIDAQABo4HlMIHiMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMB
# Af8ECDAGAQH/AgEAMB0GA1UdDgQWBBRG2D7/3OO+/4Pm9IWbsN1q1hSpwTBHBgNV
# HSAEQDA+MDwGBFUdIAAwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFs
# c2lnbi5jb20vcmVwb3NpdG9yeS8wMwYDVR0fBCwwKjAooCagJIYiaHR0cDovL2Ny
# bC5nbG9iYWxzaWduLm5ldC9yb290LmNybDAfBgNVHSMEGDAWgBRge2YaRQ2XyolQ
# L30EzTSo//z9SzANBgkqhkiG9w0BAQUFAAOCAQEATl5WkB5GtNlJMfO7FzkoG8IW
# 3f1B3AkFBJtvsqKa1pkuQJkAVbXqP6UgdtOGNNQXzFU6x4Lu76i6vNgGnxVQ380W
# e1I6AtcZGv2v8Hhc4EvFGN86JB7arLipWAQCBzDbsBJe/jG+8ARI9PBw+DpeVoPP
# PfsNvPTF7ZedudTbpSeE4zibi6c1hkQgpDttpGoLoYP9KOva7yj2zIhd+wo7AKvg
# IeviLzVsD440RZfroveZMzV+y5qKu0VN5z+fwtmK+mWybsd+Zf/okuEsMaL3sCc2
# SI8mbzvuTXYfecPlf5Y1vC0OzAGwjn//UYCAp5LUs0RGZIyHTxZjBzFLY7Df8zCC
# BJkwggOBoAMCAQICEHGgtzaV3bGvwjsrmhjuVMswDQYJKoZIhvcNAQELBQAwgakx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwx0aGF3dGUsIEluYy4xKDAmBgNVBAsTH0Nl
# cnRpZmljYXRpb24gU2VydmljZXMgRGl2aXNpb24xODA2BgNVBAsTLyhjKSAyMDA2
# IHRoYXd0ZSwgSW5jLiAtIEZvciBhdXRob3JpemVkIHVzZSBvbmx5MR8wHQYDVQQD
# ExZ0aGF3dGUgUHJpbWFyeSBSb290IENBMB4XDTEzMTIxMDAwMDAwMFoXDTIzMTIw
# OTIzNTk1OVowTDELMAkGA1UEBhMCVVMxFTATBgNVBAoTDHRoYXd0ZSwgSW5jLjEm
# MCQGA1UEAxMddGhhd3RlIFNIQTI1NiBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqG
# SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCbVQJMFwXp0GbD/Cit08D+7+DpftQe9qob
# kUb99RbtmAdT+rqHG32eHwEnq7nSZ8q3ECVT9OO+m5C47SNcQu9kJVjliCIavvXH
# rvW+irEREZMaIql0acF0tmiHp4Mw+WTxseM4PvTWwfwS/nNXFzVXit1QjQP4Zs3K
# doMTyNcOcR3kY8m6F/jRueSI0iwoyCEgDUG3C+IvwoDmiHtTbMNEY4F/aEeMKyrP
# W/SMSWG6aYX9awB4BSZpEzCAOE7xWlXJxVDWqjiJR0Nc/k1zpUnFk2n+d5aar/OM
# Dle6M9kOxkLTA3fEuzmtkfnz95ZcOmSm7SdXwehA81Pyvik0/l/5AgMBAAGjggEX
# MIIBEzAvBggrBgEFBQcBAQQjMCEwHwYIKwYBBQUHMAGGE2h0dHA6Ly90Mi5zeW1j
# Yi5jb20wEgYDVR0TAQH/BAgwBgEB/wIBADAyBgNVHR8EKzApMCegJaAjhiFodHRw
# Oi8vdDEuc3ltY2IuY29tL1RoYXd0ZVBDQS5jcmwwHQYDVR0lBBYwFAYIKwYBBQUH
# AwIGCCsGAQUFBwMDMA4GA1UdDwEB/wQEAwIBBjApBgNVHREEIjAgpB4wHDEaMBgG
# A1UEAxMRU3ltYW50ZWNQS0ktMS01NjgwHQYDVR0OBBYEFFeGm1S4vqYpiuT2wuIT
# GImFzdy3MB8GA1UdIwQYMBaAFHtbRc+vzst6/TGSGmq280brV0hQMA0GCSqGSIb3
# DQEBCwUAA4IBAQAkO/XXoDYTx0P+8AmHaNGYMW4S5D8eH5Z7a0weh56LxWyjsQx7
# UJLVgZyxjywpt+75kQW5jkHxLPbQWS2Y4LnqgAFHQJW4PZ0DvXm7NbatnEwn9mdF
# EMnFvIdOVXvSh7vd3DDvxtRszJk1bRzgYNPNaI8pWUuJlghGyY78dU/F3AnMTieL
# RM0HvKwE4LUzpYef9N1zDJHqEoFv43XwHrWTbEQX1T6Xyb0HLFZ3H4XdRui/3iyB
# lKP35benwTefdcpVd01eNinKhdhFQXJXdcB5W/o0EAZtZCBCtzrIHx1GZAJfxke+
# 8MQ6KFTa9h5PmqIZQ6RvSfj8XkIgKISLRyBuMIIEnzCCA4egAwIBAgISESHWmadk
# lz7x+EJ+6RnMU0EUMA0GCSqGSIb3DQEBBQUAMFIxCzAJBgNVBAYTAkJFMRkwFwYD
# VQQKExBHbG9iYWxTaWduIG52LXNhMSgwJgYDVQQDEx9HbG9iYWxTaWduIFRpbWVz
# dGFtcGluZyBDQSAtIEcyMB4XDTE2MDUyNDAwMDAwMFoXDTI3MDYyNDAwMDAwMFow
# YDELMAkGA1UEBhMCU0cxHzAdBgNVBAoTFkdNTyBHbG9iYWxTaWduIFB0ZSBMdGQx
# MDAuBgNVBAMTJ0dsb2JhbFNpZ24gVFNBIGZvciBNUyBBdXRoZW50aWNvZGUgLSBH
# MjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALAXrqLTtgQwVh5YD7Ht
# VaTWVMvY9nM67F1eqyX9NqX6hMNhQMVGtVlSO0KiLl8TYhCpW+Zz1pIlsX0j4waz
# hzoOQ/DXAIlTohExUihuXUByPPIJd6dJkpfUbJCgdqf9uNyznfIHYCxPWJgAa9MV
# VOD63f+ALF8Yppj/1KvsoUVZsi5vYl3g2Rmsi1ecqCYr2RelENJHCBpwLDOLf2iA
# KrWhXWvdjQICKQOqfDe7uylOPVOTs6b6j9JYkxVMuS2rgKOjJfuv9whksHpED1wQ
# 119hN6pOa9PSUyWdgnP6LPlysKkZOSpQ+qnQPDrK6Fvv9V9R9PkK2Zc13mqF5iME
# Qq8CAwEAAaOCAV8wggFbMA4GA1UdDwEB/wQEAwIHgDBMBgNVHSAERTBDMEEGCSsG
# AQQBoDIBHjA0MDIGCCsGAQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNv
# bS9yZXBvc2l0b3J5LzAJBgNVHRMEAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMI
# MEIGA1UdHwQ7MDkwN6A1oDOGMWh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vZ3Mv
# Z3N0aW1lc3RhbXBpbmdnMi5jcmwwVAYIKwYBBQUHAQEESDBGMEQGCCsGAQUFBzAC
# hjhodHRwOi8vc2VjdXJlLmdsb2JhbHNpZ24uY29tL2NhY2VydC9nc3RpbWVzdGFt
# cGluZ2cyLmNydDAdBgNVHQ4EFgQU1KKESjhaGH+6TzBQvZ3VeofWCfcwHwYDVR0j
# BBgwFoAURtg+/9zjvv+D5vSFm7DdatYUqcEwDQYJKoZIhvcNAQEFBQADggEBAI+p
# GpFtBKY3IA6Dlt4j02tuH27dZD1oISK1+Ec2aY7hpUXHJKIitykJzFRarsa8zWOO
# sz1QSOW0zK7Nko2eKIsTShGqvaPv07I2/LShcr9tl2N5jES8cC9+87zdglOrGvbr
# +hyXvLY3nKQcMLyrvC1HNt+SIAPoccZY9nUFmjTwC1lagkQ0qoDkL4T2R12WybbK
# yp23prrkUNPUN7i6IA7Q05IqW8RZu6Ft2zzORJ3BOCqt4429zQl3GhC+ZwoCNmSI
# ubMbJu7nnmDERqi8YTNsz065nLlq8J83/rU9T5rTTf/eII5Ol6b9nwm8TcoYdsmw
# TYVQ8oDSHQb1WAQHsRgwggT5MIID4aADAgECAhA25UgNgLhTE6qJjFxm6xUnMA0G
# CSqGSIb3DQEBCwUAMEwxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwx0aGF3dGUsIElu
# Yy4xJjAkBgNVBAMTHXRoYXd0ZSBTSEEyNTYgQ29kZSBTaWduaW5nIENBMB4XDTE1
# MTIyOTAwMDAwMFoXDTE5MDEyNzIzNTk1OVowgZIxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpDYWxpZm9ybmlhMRYwFAYDVQQHFA1Nb3VudGFpbiBWaWV3MRwwGgYDVQQK
# FBNJbnRlcm1lZGlhLm5ldCwgSW5jMRowGAYDVQQLFBFJbnRlcm5ldCBTZXJ2aWNl
# czEcMBoGA1UEAxQTSW50ZXJtZWRpYS5uZXQsIEluYzCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAMCZZZMUuMOfXj33He0GzsA2lBP9CRrvQRzS5weO3juk
# X5AwYyD0YJeb39hmt0xwK/09BvamaSXznLT8ehIVZUENAzokR6tRK9WQD6X+v1vg
# KQmKTrmqWm9KJ+obsr8WWgj4N4/9J8d3QupZbY2Q5PPSeSkxfiCf4N76COtqNRCN
# F/V0w4JdBOQPtITJtx0CBEBwsTTWxB2qr1fkvLDzmdH+SxNscD9ljR1q5x1plxWd
# khJhBkRLKNl2Cnou2rLeiczCQwVPa8HRCU2BwtWOycgFox5muZNfU+YagP9Mup6q
# 5cUBhsHqpNRQo8gz7W91NpNK4MJA0d1PpEuLQ2pOFMMCAwEAAaOCAY4wggGKMAkG
# A1UdEwQCMAAwHwYDVR0jBBgwFoAUV4abVLi+pimK5PbC4hMYiYXN3LcwHQYDVR0O
# BBYEFI2trWtDPkeH/YiSDbpBmcqiHjOyMCsGA1UdHwQkMCIwIKAeoByGGmh0dHA6
# Ly90bC5zeW1jYi5jb20vdGwuY3JsMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAK
# BggrBgEFBQcDAzBzBgNVHSAEbDBqMGgGC2CGSAGG+EUBBzACMFkwJgYIKwYBBQUH
# AgEWGmh0dHBzOi8vd3d3LnRoYXd0ZS5jb20vY3BzMC8GCCsGAQUFBwICMCMMIWh0
# dHBzOi8vd3d3LnRoYXd0ZS5jb20vcmVwb3NpdG9yeTAdBgNVHQQEFjAUMA4wDAYK
# KwYBBAGCNwIBFgMCB4AwVwYIKwYBBQUHAQEESzBJMB8GCCsGAQUFBzABhhNodHRw
# Oi8vdGwuc3ltY2QuY29tMCYGCCsGAQUFBzAChhpodHRwOi8vdGwuc3ltY2IuY29t
# L3RsLmNydDANBgkqhkiG9w0BAQsFAAOCAQEAQldghwA5DW+zca++L7Gu1f5d0T4o
# 7Ko5SO4L6CPrW9Wv4zDVMjtQdG/y/s64LP+4KVlfRg/UeftCV1YxDwU7/O0/I+RV
# qkTDw9AhbnUzXVzsFMi2f34ywRKbGucmfKlJM9u8gWFLJBLhPSbxFhiDalCIQG2c
# CCGRIz9EqclDrL/doyT39fmpZ6IcxuDmspWX5cynYxW5tyjIcRztFLxYuhZzp0At
# vIvLAyvUNuPbdAA08wv6u+EJTbieti4nlVNDFm5CDvF8QbdgtJqtmH5GNb0Piqao
# eh76hQmpyEJAdBy1yL10itsGHYc1gCvk9UmH193qQ4ZGbQki5tEIucXtAzGCBKcw
# ggSjAgEBMGAwTDELMAkGA1UEBhMCVVMxFTATBgNVBAoTDHRoYXd0ZSwgSW5jLjEm
# MCQGA1UEAxMddGhhd3RlIFNIQTI1NiBDb2RlIFNpZ25pbmcgQ0ECEDblSA2AuFMT
# qomMXGbrFScwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARYwIwYJKoZIhvcNAQkEMRYEFMg062tBcT+ziMJtkryFL+os7/ujMA0G
# CSqGSIb3DQEBAQUABIIBAGXPe0sexsEHJtMfXwI7Y88GR5+iwzMVAtqcoe7nJpWR
# OlPQVvCucdR6USba9r3cQt3TFDcOVhjdmitXzk5dhThuZvUbyXi8Fy3xEjjS1M5u
# cmPHrxTENd1wDrb6bK7WY0DP9cB4BGH5bclpEinqj88HnFiTn6Cw44B+SgkEINug
# MPvRCB7QAONCDA70FIQWaXrvxUVQ4B0rZaKKFs1+Ci5r808+MJbYtUpDHtGmL6R2
# 2f18aPtAojBRkD+YVsFcyxkt9KH3KpahBW1zkp5yT1XNSX63qM6bQXoWMkDTN94Z
# U0wEL0GNNHZN8orJ68lNLwBguvwltgllNSjSrQQ/GpKhggKiMIICngYJKoZIhvcN
# AQkGMYICjzCCAosCAQEwaDBSMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFs
# U2lnbiBudi1zYTEoMCYGA1UEAxMfR2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcgQ0Eg
# LSBHMgISESHWmadklz7x+EJ+6RnMU0EUMAkGBSsOAwIaBQCggf0wGAYJKoZIhvcN
# AQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYwNzE4MTQwMzA2WjAj
# BgkqhkiG9w0BCQQxFgQUgZvg1W4znCuDoocsM6xwIupF/YAwgZ0GCyqGSIb3DQEJ
# EAIMMYGNMIGKMIGHMIGEBBRjuC+rYfWDkJaVBQsAJJxQKTPseTBsMFakVDBSMQsw
# CQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEoMCYGA1UEAxMf
# R2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcgQ0EgLSBHMgISESHWmadklz7x+EJ+6RnM
# U0EUMA0GCSqGSIb3DQEBAQUABIIBAB5K6qhf5GB87jwL/gK+ancQ+3NqL/XE4evx
# lBah2kEiHjoMnmqYI+LAZ3fIDosGBMf2lIfcL13PmlIGLMsBPfd8L0tVfYvqMd3N
# SYHI5xrp81zojtZD9ySEY3fZCdwPAougE0N0EbeknMAuw35B3f0FS4F8+0heUbfI
# gCUpM40RxOw4vbku/ZhNkiAky5dN4soBoI76GS/B9dVgKtmiZX8YlrR3w8iaeKn9
# AZ3C3c5lhsAXcsaMliQr8WshQUzeYqAtWaeBJZpz0YIxHnhHynTdtCBf/J3MPFSF
# SXmcmegbi0DteJFEbWm8xCOZJrUI4y1qIDnIcHJ1eNo0kAcfhEo=
# SIG # End signature block
