param (
    [Parameter(Mandatory = $true)]
    [string]$sourceKeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$destKeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$sourceSubId,

    [Parameter(Mandatory = $true)]
    [string]$destSubId,

    [Parameter(Mandatory = $true)]
    [string]$location
)




$osDisksCollection = @()
$rgCollection =@()
$dataDisksSharedSourceCollection = @()
$dataDisksNSSourceCollection = @()

$sharedDataDisksQueryFiltCollection = @()

$nicCollection = @()
$vmConfigCollection = @()
$ipConfigCollection = @()
$dataDiskRefCollection = @()
$subnet = @()
$config = @()
$ipConfigurations =@()
$nicCreateCollection = @()

$ipSettingsCreate = @()

$sqlDBVMs = @()


$secretCollection = @()
$certificateCollection = @()




#Connect to Account
Connect-AzAccount

#Set context to source sub
Set-AzContext -Subscription $sourceSubId

$vms = Get-AzVm | Select-Object *

$snapshotRG = "rg-Snapshots"

$dataDisksQuery = Get-AzDisk

# Get OS Disk Information from VMs
foreach($osDisk in $vms){
    $osDisksCollection += [pscustomobject]@{
        osDiskName = $osDisk.StorageProfile.OsDisk.Name 
        osDiskId = $osDisk.StorageProfile.OsDisk.ManagedDisk.Id
        DiskSizeGB = (Get-AzDisk -Name $osDisk.StorageProfile.OsDisk.Name).DiskSizeGB #$osDisk.StorageProfile.OsDisk.DiskSizeGB
        VMName = $osDisk.Name
        vmId = $osDisk.id
        resourceGroup = $osDisk.ResourceGroupName
        location = $osDisk.Location
        storageAccountType = (Get-AzDisk -Name $osDisk.StorageProfile.OsDisk.Name).Sku.Name #$osDisk.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
    }
}



# Get Unshared Data Disk Information from VMs
foreach($dataDisk in $vms){

    foreach($diskInfo in $dataDisk.storageProfile.dataDisks){
        $maxSharesCheck = (Get-AzDisk -Name $diskInfo.Name).MaxShares
        $diskName = (Get-AzDisk -Name $diskInfo.Name).Name
        if($null -eq $maxSharesCheck){
            $dataDisksNSSourceCollection += [pscustomobject]@{
                Name = $diskName
                location = $dataDisk.Location
                VMName = $dataDisk.Name
                DiskSizeGB = (Get-AzDisk -Name $diskInfo.name).DiskSizeGB
                resourceGroup = $dataDisk.ResourceGroupName
                #diskId = "/subscriptions/$($destSubId)/resourceGroups/$($dataDisk.ResourceGroupName)/providers/Microsoft.Compute/disks/$($diskIdRaw)"
                sourceDiskId = $diskInfo.ManagedDisk.Id
                tier = (Get-AzDisk -Name $diskInfo.Name).Tier 
                storageAccountType = (Get-AzDisk -Name $diskInfo.Name).Sku.Name #$diskInfo.ManagedDisk.StorageAccountType
                MaxShares = $maxSharesCheck
            }  
        }
    }
}





#Gets RG Information from VMs
foreach($rgs in $vms){
    $rgCollection += [PSCustomObject]@{
        name = $rgs.ResourceGroupName
    }
}



# Gets Shared Data Disk Information from Disks
foreach($sharedDataDisks in $dataDisksQuery){

    if($sharedDataDisks.ManagedBy -notmatch "aks" -And($sharedDataDisks.Name -notmatch "OsDisk") -and($null -ne $sharedDataDisks.MaxShares)){
        $sharedDataDisksQueryFiltCollection += [PSCustomObject]@{
            Name = $sharedDataDisks.Name
            location = $sharedDataDisks.Location
            VMName = $sharedDataDisks.ManagedBy -replace ".*\/", ""
            DiskSizeGB = $sharedDataDisks.DiskSizeGB 
            resourceGroup = $sharedDataDisks.ResourceGroupName
            #diskId = "/subscriptions/$($destSubId)/resourceGroups/$($dataDisk.ResourceGroupName)/providers/Microsoft.Compute/disks/$($diskIdRaw)" 
            sourceDiskId = $sharedDataDisks.Id
            tier = $sharedDataDisks.Sku.Tier 
            MaxShares = $maxSharesCheck
            storageAccountType = $sharedDataDisks.sku.Name
        }
    }
}




#Key Vault Source Retrieve
$sourceKeyvault= Get-AzKeyVault -VaultName $sourceKeyVaultName
#$sourceKeyvaultId = $sourceKeyvault.ResourceId



#Key Vault Secret Retrieve
#$secrets = Get-AzKeyVaultSecret -ResourceId $sourceKeyvaultId | Select *
$secretProperties= Get-AzKeyVaultSecret -VaultName $sourceKeyVaultName
$certificateProperties = Get-AzKeyVaultSecret -VaultName $sourceKeyVaultName

foreach($secret in $secretProperties){


    $secretfullProperties = Get-AzKeyVaultSecret -Vault $sourceKeyVaultName -Name $secret.Name

    $secretValue = $secretfullProperties.SecretValue

    $secretName = $secretfullProperties.Name
    
    if($secretName -notlike "*star*"){
        $secretCollection += [PSCustomObject]@{
            Name = $secretName #$secretfullProperties.Name
            vaultName = $destKeyVaultName
            secretValue = $secretValue
        }
    }

    
}

foreach($cert in $certificateProperties){

    $certFullProperties = Get-AzKeyVaultSecret -Vault $sourceKeyVaultName -Name $cert.Name 

    $certValue = $certFullProperties.SecretValue

    $secretName = $certFullProperties.Name

    if($secretName -like "*star*"){

        

        # if($secretfullProperties.Name -match "ra001" -or($secretfullProperties.Name -match "star-pasngr") -or($secretfullProperties.Name -match "ra002")){
        #     $secretName = "$($secret.Name)-migrated" 
        # }
        # else {
        #     $secretName = $secretfullProperties.Name
        # }
    

        $certificateCollection += [PSCustomObject]@{
            Name = "$($secretName)-migratedCert" #$secretfullProperties.Name
            vaultName = $destKeyVaultName
            certValue = $certValue
        }
    }

}


#Set context to dest sub
Set-AzContext -Subscription $destSubId

#Key Vault Destination Retrieve
$destKeyVault = Get-AzKeyVault -VaultName $destKeyVaultName
#$destkeyvaultId = $destKeyVault.ResourceId

foreach($secretCollectionitem in $secretCollection){
    
    Set-AzKeyVaultSecret -VaultName $secretCollectionitem.vaultName -Name $secretCollectionitem.Name -SecretValue $secretCollectionitem.secretValue

}

foreach($certCollectionItem in $certificateCollection){
    Set-AzKeyVaultSecret -VaultName $certCollectionItem.vaultName -Name $certCollectionItem.Name -SecretValue $certCollectionItem.certValue

}


# Switch to the destination subscription
Write-Output "Switching to destination subscription: $destSubId"
Select-AzSubscription -SubscriptionId $destSubId

New-AzResourceGroup -Name $snapshotRG -Location $location


#RG VM Creation

$rgCollectionUnique = $rgCollection | Select-Object name -Unique

foreach($uniqueRG in $rgCollectionUnique){
    New-AzResourceGroup -Name $uniqueRG.name -Location $location
}


#OS Disk Snapshot Config & Create

foreach($vm in $osDisksCollection){

    # Switch to the source subscription
    Write-Output "Switching to source subscription: $sourceSubId"
    Select-AzSubscription -SubscriptionId $sourceSubId

    # Debugging output to check values
    Write-Output "Processing disk: $($disks.Name)"
    Write-Output "Source Disk ID: $($disks.sourceDiskId)"
    Write-Output "Location: $($disks.location)"
    Write-Output "Storage Account Type: $($disks.storageAccountType)"

    if($vm.storageAccountType -eq "StandardSSD_LRS"){
        $storageAccountType = "Standard_LRS"
    }

    # Ensure the source disk ID is correctly set
    $sourceDisk = Get-AzDisk -ResourceGroupName $vm.resourceGroup -DiskName $vm.osDiskName
    $sourceDiskId = $sourceDisk.Id

    $snapshotConfig = New-AzSnapshotConfig -SourceResourceId $vm.osDiskId -Location $vm.location -CreateOption copy  -SkuName $storageAccountType -DiskSizeGB $vm.DiskSizeGB

    # Debugging output for snapshot configuration
    Write-Output "Snapshot configuration created: $($snapshotConfig | ConvertTo-Json -Depth 10)"

    # Switch to the destination subscription
    Write-Output "Switching to destination subscription: $destSubId"
    Select-AzSubscription -SubscriptionId $destSubId

    # Create the snapshot using the configuration in the destination subscription
    $snapshotCreate = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName "snapshot-$($vm.osDiskName)" -ResourceGroupName $snapshotRG

     

    # Output snapshot creation result
    Write-Output "Snapshot created with ID: $($snapshotCreate.Id)"

}





# Data Disks Shared Disk Snapshot Creation
foreach($disks in $sharedDataDisksQueryFiltCollection){

      # Debugging output to check values
      Write-Output "Processing disk: $($disks.Name)"
      Write-Output "Source Disk ID: $($disks.sourceDiskId)"
      Write-Output "Location: $($disks.location)"
      Write-Output "Storage Account Type: $($disks.storageAccountType)"


     # Set storage account type
    if($disks.storageAccountType -eq "StandardSSD_LRS"){
        $storageAccountType = "Standard_LRS"
    }

     # Debugging output for storage account type
     Write-Output "Using Storage Account Type: $storageAccountType"


    # Switch to the source subscription
    Write-Output "Switching to source subscription: $sourceSubId"
    Select-AzSubscription -SubscriptionId $sourceSubId

    # Ensure the source disk ID is correctly set
    $sourceDisk = Get-AzDisk -ResourceGroupName $disks.resourceGroup -DiskName $disks.Name
    $sourceDiskId = $sourceDisk.Id


    # Create the snapshot configuration in the source subscription
    $snapshotConfig = New-AzSnapshotConfig -SourceResourceId $sourceDiskId -Location $disks.location -CreateOption Copy -SkuName $storageAccountType -DiskSizeGB $disks.DiskSizeGB
    
    # Debugging output for snapshot configuration
    Write-Output "Snapshot configuration created: $($snapshotConfig | ConvertTo-Json -Depth 10)"
    
    # Switch to the destination subscription
    Write-Output "Switching to destination subscription: $destSubId"
    Select-AzSubscription -SubscriptionId $destSubId

    
    # Create the snapshot using the configuration in the destination subscription
    $snapshotCreate = New-AzSnapshot -ResourceGroupName $snapshotRG -SnapshotName "snapshot-$($disks.Name)" -Snapshot $snapshotConfig

    # Output snapshot creation result
    Write-Output "Snapshot created with ID: $($snapshotCreate.Id)"

}


# Data Disks Non Shared Disk Snapshot Creation
foreach($nonSharedDisks in $dataDisksNSSourceCollection){

    # Switch to the source subscription
    Write-Output "Switching to source subscription: $sourceSubId"
    Select-AzSubscription -SubscriptionId $sourceSubId

     # Debugging output to check values
     Write-Output "Processing disk: $($disks.Name)"
     Write-Output "Source Disk ID: $($disks.sourceDiskId)"
     Write-Output "Location: $($disks.location)"
     Write-Output "Storage Account Type: $($disks.storageAccountType)"

    # Set storage account type
   if($nonSharedDisks.storageAccountType -eq "StandardSSD_LRS"){
       $storageAccountType = "Standard_LRS"
   }
   else{
    $storageAccountType = $nonSharedDisks.storageAccountType
   }

    # Ensure the source disk ID is correctly set
    $sourceDisk = Get-AzDisk -ResourceGroupName $nonSharedDisks.resourceGroup -DiskName $nonSharedDisks.Name
    $sourceDiskId = $sourceDisk.Id


    $snapshot = New-AzSnapshotConfig -SourceResourceId $nonSharedDisks.sourceDiskId -Location $nonSharedDisks.location -CreateOption Copy -SkuName $storageAccountType -DiskSizeGB $nonSharedDisks.DiskSizeGB

   # Switch to the dest subscription
   Write-Output "Switching to dest subscription: $destSubId"
   Select-AzSubscription -SubscriptionId $destSubId



    # Create the snapshot using the configuration in the destination subscription
    $snapshotCreate = New-AzSnapshot -ResourceGroupName $snapshotRG -SnapshotName "snapshot-$($nonSharedDisks.Name)" -Snapshot $snapshot

    # Output snapshot creation result
    Write-Output "Snapshot created with ID: $($snapshotCreate.Id)"
}





#OS Disk Snapshot Get, Disk Config, Disk Create & OS Disk Info Export

foreach($osDiskSnapshot in $osDisksCollection){

    $snapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name "snapshot-$($osDiskSnapshot.osDiskName)"

    $disksSnapshotObject= New-AzDiskConfig -SkuName $osDiskSnapshot.storageAccountType -Location $snapshotInfo.Location  -CreateOption $snapshotInfo.CreationData.CreateOption -SourceResourceId $snapshotInfo.Id -DiskSizeGB $snapshotInfo.DiskSizeGB

    $osDiskCreate = New-AzDisk -Disk $disksSnapshotObject -ResourceGroupName $osDiskSnapshot.resourceGroup -DiskName $osDiskSnapshot.osDiskName -verbose #$snapshotInfo.Name -Verbose


    $newdOsDisksCreated = [pscustomobject]@{
        vmName = $osDiskSnapshot.VMName
        DiskSizeGB = $osDiskCreate.DiskSizeGB
        name = $osDiskCreate.Name 
        id = $osDiskCreate.Id
        resourceGroup = $osDiskCreate.ResourceGroupName
        location = $osDiskCreate.Location
    }

}

#Data Disk  Shared Disks Snapshot Get, Disk Config, Disk Create & Data Disk Info Export

foreach($dataDiskSharedSnapshot in $sharedDataDisksQueryFiltCollection){


    $shareddatadisksnapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name "snapshot-$($dataDiskSharedSnapshot.Name)"

    $dataSharedDisksSnapshotObject= New-AzDiskConfig -SkuName $dataDiskSharedSnapshot.StorageAccountType -Location $shareddatadisksnapshotInfo.Location  -CreateOption $shareddatadisksnapshotInfo.CreationData.CreateOption -SourceResourceId $shareddatadisksnapshotInfo.Id -DiskSizeGB $shareddatadisksnapshotInfo.DiskSizeGB -MaxSharesCount $dataDiskSharedSnapshot.MaxShares # -Tier $dataDiskSharedSnapshot.storageAccountType

    $dataDiskCreate = New-AzDisk -Disk $dataSharedDisksSnapshotObject -ResourceGroupName $dataDiskSharedSnapshot.resourceGroup -DiskName $dataDiskSharedSnapshot.Name -Verbose

    $newNonSharedDataDisksCreated = [pscustomobject]@{
        vmName = $dataDiskSnapshot.VMName
        DiskSizeGB = $dataDiskCreate.DiskSizeGB
        name = $dataDiskCreate.Name 
        id = $dataDiskCreate.Id
        resourceGroup = $dataDiskCreate.ResourceGroupName
        location = $dataDiskCreate.Location
    }
    
}


#Data Disk Non Shared Disks Snapshot Get, Disk Config, Disk Create & Data Disk Info Export

foreach($dataDiskNonSharedSnapshot in $dataDisksNSSourceCollection){


    $datadisksnapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name "snapshot-$($dataDiskNonSharedSnapshot.Name)"

    $dataNonSharedDisksSnapshotObject= New-AzDiskConfig -SkuName $dataDiskNonSharedSnapshot.StorageAccountType -Location $datadisksnapshotInfo.Location  -CreateOption $datadisksnapshotInfo.CreationData.CreateOption -SourceResourceId $datadisksnapshotInfo.Id -DiskSizeGB $datadisksnapshotInfo.DiskSizeGB

    $dataDiskCreate = New-AzDisk -Disk $dataNonSharedDisksSnapshotObject -ResourceGroupName $dataDiskNonSharedSnapshot.resourceGroup -DiskName $dataDiskNonSharedSnapshot.Name -Verbose

    $newNonSharedDataDisksCreated = [pscustomobject]@{
        vmName = $dataDiskSnapshot.VMName
        DiskSizeGB = $diskCdataDiskCreatereate.DiskSizeGB
        name = $dataDiskCreate.Name 
        id = $dataDiskCreate.Id
        resourceGroup = $dataDiskCreate.ResourceGroupName
        location = $dataDiskCreate.Location
    }
    
}



foreach($vmconfig in $vms){

    # Switch to the destination subscription
    Write-Output "Switching to destination subscription: $sourcesubId"
    Select-AzSubscription -SubscriptionId $sourcesubId

    $nicCleanup = $vmconfig.NetworkProfile.NetworkInterfaces

    foreach($nic in $nicCleanup){
        $subnetId = Get-AzNetworkInterface -Name ($nic.Id -replace  '.*\/')

        #$subnetName = $subnetId.Name
        $subnetNamePattern = '.*/subnets/([^/]+).*'
        $subnetName = $subnetId.IpConfigurations.Subnet.Id -replace $subnetNamePattern, '$1'
        $subnetRGpattern = '.*resourceGroups/([^/]+).*'
        $subnetRG  = $subnetId.IpConfigurations.Subnet.Id -replace $subnetRGpattern, '$1'
        $vnetNamePattern = '.*/virtualNetworks/([^/]+)/.*'
        $vnetName = $subnetId.IpConfigurations.Subnet.Id -replace $vnetNamePattern, '$1'
        $nicRG = $subnetId.ResourceGroupName


        foreach($ipconfigSettings in $subnetId.IpConfigurations){
            $ipConfigsubnetNamePattern = '.*/subnets/([^/]+).*'
            $ipConfigsubnetName = $ipconfigSettings.Subnet.Id -replace $ipConfigsubnetNamePattern, '$1'
            $ipConfigsubnetRGpattern = '.*resourceGroups/([^/]+).*'
            $ipConfigsubnetRG  = $ipconfigSettings.Subnet.Id -replace $ipConfigsubnetRGpattern, '$1'
            $ipConfigvnetNamePattern = '.*/virtualNetworks/([^/]+)/.*'
            $ipConfigvnetName = $ipconfigSettings.Subnet.Id -replace $ipConfigvnetNamePattern, '$1'


            $ipConfigurations += [pscustomobject]@{
                Name = $ipconfigSettings.Name
                PrivateIpAddressVersion = $ipconfigSettings.PrivateIpAddressVersion
                Primary = $ipconfigSettings.Primary
                PrivateIpAddress = $ipconfigSettings.PrivateIpAddress
                PrivateIpAllocationMethod = "Static"
                subnet = [pscustomobject]@{
                    Id = "/subscriptions/$($destSubId)/resourceGroups/$($ipConfigsubnetRG)/providers/Microsoft.Network/virtualNetworks/$($ipConfigvnetName)/subnets/$($ipConfigsubnetName)"
                }
            }

        }

        $nicCollection +=[pscustomobject]@{
            name = $SubnetId.Name
            rg = $nicRG 
            location = $vmconfig.location
            subnetId = "/subscriptions/$($destSubId)/resourceGroups/$($subnetRG)/providers/Microsoft.Network/virtualNetworks/$($vnetName)/subnets/$($subnetName)"
            IpConfigurations = $ipConfigurations
        }

    }

    # Switch to the destination subscription
    Write-Output "Switching to destination subscription: $destsubId"
    Select-AzSubscription -SubscriptionId $destsubId


    foreach($nicCollectionItem in $nicCollection){


        foreach($ipconfigSettingsCollection in $nicCollectionItem.IpConfigurations){

            if($ipconfigSettingsCollection.Primary -eq $true){
                $ipSettingsCreate += New-AzNetworkInterfaceIpConfig -Name $ipconfigSettingsCollection.Name -Subnet $ipconfigSettingsCollection.Subnet -Primary -PrivateIpAddress $ipconfigSettingsCollection.PrivateIpAddress -PrivateIpAddressVersion $ipconfigSettingsCollection.PrivateIpAddressVersion
            }
            elseif($ipconfigSettingsCollection.Primary -eq $false){
                $ipSettingsCreate += New-AzNetworkInterfaceIpConfig -Name $ipconfigSettingsCollection.Name -Subnet $ipconfigSettingsCollection.Subnet -PrivateIpAddress $ipconfigSettingsCollection.PrivateIpAddress -PrivateIpAddressVersion $ipconfigSettingsCollection.PrivateIpAddressVersion
            }
        }

        $nicCreate = New-AzNetworkInterface -Name $nicCollectionItem.name -ResourceGroupName $nicCollectionItem.rg -location $nicCollectionItem.location  -IpConfiguration $ipSettingsCreate -force #-SubnetId $nicCollectionItem.subnetId


        $nicCreateCollection += [pscustomobject]@{
            name = $nicCreate.Name
            id = $nicCreate.Id
        }

    }

    $osDiskId = $vmConfig.StorageProfile.OsDisk.ManagedDisk.Id -replace $sourceSubId, $destSubId 

    $diskNamePattern = "(?<=disks/).*$"
    $diskName = [regex]::Match($osDiskId, $diskNamePattern).Value

    # Add "new" to the beginning of the disk name
    $newDiskName = $diskName

    # Replace the old disk name with the new disk name in the updated string
    $osDiskIdFormat = $osDiskId -replace $diskName, $newDiskName

    $vmConfigCollection = [pscustomobject]@{
        VMName = $vmconfig.Name
        vmSize = $vmconfig.HardwareProfile.vmSize
        computerName = $vmconfig.Name
        securityTypeStnd = "Standard"
        managedDiskId = $osDiskIdFormat
        createOption = "Attach" #$vmconfig.StorageProfile.OsDisk.CreateOption
    }


    $config = New-AzVMConfig -VMName $vmConfigCollection.VMName -VMSize $vmConfigCollection.vmSize -SecurityType $vmConfigCollection.securityTypeStnd


    foreach($nicCollectionCreate in $nicCreateCollection){
        $config = Add-AzVMNetworkInterface -VM $config -id $nicCollectionCreate.id
    }


    $OSTypeVersion = $vmconfig.StorageProfile.OsDisk.OsType

    $config = Set-AzVMOSDisk -VM $config -ManagedDiskId $vmConfigCollection.managedDiskId  -CreateOption $vmConfigCollection.createOption #-OSType $OSTypeVersion
    $config.StorageProfile.OsDisk.OsType = $OSTypeVersion 
    
    foreach($datadiskref in $vmconfig.StorageProfile.DataDisks){

        $osDiskId = $datadiskref.ManagedDisk.Id -replace $sourceSubId, $destSubId 

        $diskNamePattern = "(?<=disks/).*$"
        $diskName = [regex]::Match($osDiskId, $diskNamePattern).Value

        # Add "new" to the beginning of the disk name
        $newDiskName = $diskName

        # Replace the old disk name with the new disk name in the updated string
        $DataDiskIdFormat = $osDiskId -replace $diskName, $newDiskName




        $dataDiskRefCollection += [PSCustomObject]@{
            name = $datadiskref.Name
            DiskSizeGB = $datadiskref.DiskSizeGB
            Lun = $datadiskref.Lun
            Caching = $datadiskref.Caching
            CreateOption = "Attach" #$datadiskref.CreateOption
            Id = $DataDiskIdFormat
        }
    }

    foreach($dataDiskRefCollectionItem in $dataDiskRefCollection ){
        $config = Add-AzVMDataDisk -VM $config -ManagedDiskId $dataDiskRefCollectionItem.Id -Lun $dataDiskRefCollectionItem.Lun -CreateOption $dataDiskRefCollectionItem.CreateOption
        $config = Set-AzVMDataDisk -Caching $dataDiskRefCollectionItem.Caching -Lun $dataDiskRefCollectionItem.Lun -VM $config
    }



    #Boot Diagnostics
    $config = Set-AzVMBootDiagnostic -VM $config -Enable 

    # Verify the final VM configuration
    $config | Format-List



    $vmParams = @{
        ResourceGroupName = $vmconfig.ResourceGroupName
        Location = $vmconfig.Location
        VM = $config
    }

    #VM Creation 
    New-AzVM @vmParams


    $nicCollection = @()
    $vmConfigCollection = @()
    $ipConfigCollection = @()
    $dataDiskRefCollection = @()
    $subnet = @()
    $config = @()
    $ipConfigurations =@()
    $nicCreateCollection = @()

}