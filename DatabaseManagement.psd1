@{
	RootModule = 'MSSQL.psm1'
	ModuleVersion = '1.0.0'
	GUID = '1c6a21d1-d665-499b-9753-d8908a736c43'
	Author = 'Alexey Miasoedov'
	CompanyName = 'Intermedia'
	Copyright = '(c) 2016 Alexey Miasoedov. All rights reserved.'
	Description = 'Database interaction cmdlets'
	PowerShellVersion = '4.0'
	# PowerShellHostName = ''
	# PowerShellHostVersion = ''
	# DotNetFrameworkVersion = ''
	# CLRVersion = ''
	# ProcessorArchitecture = ''
	# RequiredModules = @()
	# RequiredAssemblies = @()
	# ScriptsToProcess = @()
	# TypesToProcess = @()
	# FormatsToProcess = @()
	# NestedModules = @()
	FunctionsToExport = #'*-*' # only Verb-Noun; avoid helper functions
		'Invoke-SqlCommand',
		'Invoke-SqlDb',
		'Load-DataRows',
		'New-SqlDataAdapter'
	CmdletsToExport = '*'
	VariablesToExport = '*'
	AliasesToExport = '*'
	# ModuleList = @()
	FileList = 'MSSQL.psm1'
	# PrivateData = ''
	# HelpInfoURI = ''
	# DefaultCommandPrefix = ''
}