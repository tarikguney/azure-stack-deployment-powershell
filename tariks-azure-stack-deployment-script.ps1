﻿
# ========================= GLOBAL VARIABLES ============================== #

$UserName='p1admin@engsrinihotmail.onmicrosoft.com'      
$Password='G00dj0b!'| ConvertTo-SecureString -Force -AsPlainText    
$Credentials  = New-Object PSCredential($UserName,$Password)

# Setting environment and endpoints
$EnvironmentVariable = "AzureStackAdmin"
$TenantName = "tenantname.onmicrosoft.com"
$AzureRmServiceEndpoint = "https://adminmanagement.local.azurestack.external"
$Location = "local" # The location of the cloud resources.

$Increment = "6" #this is for testing so that I don't have to change of the resource group, container name, etc.

# Setting creation variables
$StorageAccountName = "p1recordsstorageaccount" + $Increment
$SkuName = "Standard_LRS" # This is an enum. https://docs.microsoft.com/en-us/dotnet/api/microsoft.azure.management.storage.models.skuname?view=azure-dotnet
$ResourceGroupName = "p1recordsResource" + $Increment
$ContainerName = "p1recordscontainer" + $Increment

$TargetVhdFileName = "AzureAD.vhd"
$VhdFileLocalPath = "C:\images\AzureAD\AD.vhd"

$VmSourceUriPlain = "https://$($StorageAccountName).blob.local.azurestack.external/$($ContainerName)/$($TargetVhdFileName)"
$OsDiskName = "precordsDisk" + $Increment
$SubnetName = 'p1recordsSubnet' + $Increment
$VnetName = "p1recordsVirtualNetwork" + $Increment
$NsgName = "p1recordsNsg" + $Increment
$IpName = "p1recordsIP" + $Increment
$NicName = "p1recordsNetworkInterface" + $Increment
$VmName = "p1recordsVM" + $Increment


# ====================================== BODY ================================= #

Write-Host "Signing into Azure now..."
# Register an Azure Resource Manager environment that targets your Azure Stack instance
Add-AzureRMEnvironment -Name $EnvironmentVariable -ArmEndpoint $AzureRmServiceEndpoint

$authEndpoint = (Get-AzureRmEnvironment -Name $EnvironmentVariable).ActiveDirectoryAuthority.TrimEnd('/')
$tenantId = (invoke-restmethod "$($authEndpoint)/$($TenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]

# Sign in to your environment
Login-AzureRmAccount -EnvironmentName $EnvironmentVariable -TenantId $tenantId -Credential $Credentials

#-------------------------------------------------------------------------------#

Write-Host "Creating a resource group..."
Get-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -ErrorVariable notPresent -ErrorAction SilentlyContinue
if ($notPresent) {
	New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Force -Confirm:$false -ErrorAction Stop
}

#-------------------------------------------------------------------------------#

Write-Host "Creating storage account..."
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorVariable notPresent -ErrorAction SilentlyContinue
if($notPresent){
	$storageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location -SkuName $SkuName
}

#-------------------------------------------------------------------------------#

Write-Host "Creating storage container..."
$storageContext = $storageAccount.Context
Get-AzureStorageContainer -Name $ContainerName -Context $storageContext -ErrorVariable notPresent -ErrorAction SilentlyContinue
if($notPresent){
	New-AzureStorageContainer -Name $ContainerName -Context $storageContext -Permission blob
}

#-------------------------------------------------------------------------------#

Write-Host "Uploading the selected VHD file..."
Set-AzureStorageBlobContent -File $VhdFileLocalPath -Container $ContainerName -Blob $TargetVhdFileName -Context $storageContext -ConcurrentTaskCount 100 -BlobType Page

#-------------------------------------------------------------------------------#

# Giving some time to Azure to process the uploaded VHD file.
Write-Host "Waiting for 5 seconds to allow Azure to process the uploaded file..."
Start-Sleep 5

#-------------------------------------------------------------------------------#

Write-Host "Creating OS Disk..."
$osDisk = New-AzureRmDisk -DiskName $OsDiskName -Disk (New-AzureRmDiskConfig -AccountType "StandardLRS" -Location $Location -CreateOption Import -SourceUri $VmSourceUriPlain) -ResourceGroupName $ResourceGroupName

#-------------------------------------------------------------------------------#

Write-Host "Creating virtual network..."
$vnet = Get-AzureRmVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue
if($notPresent){
	$singleSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix 10.0.0.0/24
	$vnet = New-AzureRmVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix 10.0.0.0/16 -Subnet $singleSubnet
}

#-------------------------------------------------------------------------------#   

Write-Host "Creating RDP rule and Network Security Group..."
$nsg = Get-AzureRmNetworkSecurityGroup -Name $NsgName -ResourceGroupName $ResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue
if($notPresent){
	$rdpRule = New-AzureRmNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow RDP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
	$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NsgName -SecurityRules $rdpRule
}

#-------------------------------------------------------------------------------#

Write-Host "Setting public IP..."
$pip = Get-AzureRmPublicIpAddress -Name $IpName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue -ErrorVariable notPresent
if($noPresent){
	$pip = New-AzureRmPublicIpAddress -Name $IpName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic
}

#-------------------------------------------------------------------------------#

Write-Host "Creating network interface..."
$nic = Get-AzureRmNetworkInterface -Name $NicName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue -ErrorVariable notPresent
if($notPresent){
	$nic = New-AzureRmNetworkInterface -Name $NicName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
}

#-------------------------------------------------------------------------------#

Write-Host "Creating new Azure Virtual Machine configuration..."
$vmConfig = New-AzureRmVMConfig -VMName $VmName -VMSize "Standard_A2"
$vm = Add-AzureRmVMNetworkInterface -VM $vmConfig -Id $nic.Id

#-------------------------------------------------------------------------------#

Write-Host "Setting virtual machine OS disk..."
$vm = Set-AzureRmVMOSDisk -VM $vm -ManagedDiskId $osDisk.Id `
	-StorageAccountType StandardLRS -DiskSizeInGB 128 `
	-CreateOption Attach -Windows

#-------------------------------------------------------------------------------#

Write-Host "Creating virtual machine. This may take a while. Please wait..."
New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vm -AsJob

##-------------------------------------------------------------------------------#

Write-Host "The new VM creation proces will take in place in the background. You can close this window and check azure portal to see the result!"
	
	
	
