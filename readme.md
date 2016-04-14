# Usage examples

## Working with dataset
```
$SqlDataAdapter = New-SqlDataAdapter -SqlServer <SQLServerFqdn> -Database <DbName> -TableName <TableName>
$DataSet = Invoke-SqlDb -SqlDataAdapter $SqlDataAdapter -Select
$Data = @([PSCustomObject]@{Name='Joe';Age=21},[PSCustomObject]@{Name='Michael';Age=27})
Load-DataRows -DataSet $DataSet -Data $Data
Invoke-SqlDb -SqlDataAdapter $SqlDataAdapter -Update -DataSet $DataSet
```
## Running a single command
```
$Param = @{SqlServer = 'SQLServerFqdn'; Database = 'DbName'}

Invoke-SqlCommand @Param -CommandType NonQuery -CommandText "UPDATE TableName SET Notes = NULL WHERE Notes IS NOT NULL"
Invoke-SqlCommand @Param -CommandType Reader -CommandText "SELECT * FROM TableName"
Invoke-SqlCommand @Param -CommandType Scalar -CommandText "SELECT MAX(Updated) FROM TableName"
```
