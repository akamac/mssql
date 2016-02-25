# Usage examples

## Working with dataset
```
$SqlDataAdapter = New-SqlDataAdapter -SqlServer <SQLServerFqdn> -Database <DbName> -TableName <TableName>
$DataSet = Invoke-SqlDb -SqlDataAdapter $SqlDataAdapter -Select
$Data = @([PSCustomObject]@{Name='Joe';Age=21},[PSCustomObject]@{Name='Michael';Age=27})
Load-DataRows -DataSet $DataSet -Data $Data
Invoke-SqlDb -SqlDataAdapter $SqlDataAdapter -Update -DataSet $DataSet
```
## Run a single command
```
Invoke-SqlCommand -SqlServer <SQLServerFqdn> -Database <DbName> -CommandType NonQuery -CommandText @'
UPDATE TableName SET Notes = NULL WHERE Notes IS NOT NULL
'@

Invoke-SqlCommand -SqlServer <SQLServerFqdn> -Database <DbName> -CommandType Reader -CommandText @'
SELECT * FROM TableName
'@

Invoke-SqlCommand -SqlServer <SQLServerFqdn> -Database <DbName> -CommandType Scalar -CommandText @'
SELECT MAX(Updated) FROM TableName
'@
```
