
$osDisksCollection = @()

$dataDisksSharedSourceCollection = @()
$dataDisksNSSourceCollection = @()

$nicCollection = @()
$vmConfigCollection = @()
$ipConfigCollection = @()
$dataDiskRefCollection = @()
$config = @()
$ipConfigurations =@()

$nicCreateCollection = @()

$keyVaultName = "kv-15b-uat-eus2-01"

$sourceSubId = ""
$destSubId = ""

$location = "eastus2"


#Connect to Account
Connect-AzAccount

#Set context to source sub
Set-AzContext -Subscription $sourceSubId

$vms = Get-AzVm | Select-Object *

$snapshotRG = "rg-Snapshots"



foreach($osDisk in $vms){
    $osDisksCollection += [pscustomobject]@{
        osDiskName = $osDisk.StorageProfile.OsDisk.Name 
        osDiskId = $osDisk.StorageProfile.OsDisk.ManagedDisk.Id
        DiskSizeGB = $osDisk.StorageProfile.OsDisk.DiskSizeGB
        VMName = $osDisk.Name
        vmId = $osDisk.id
        resourceGroup = $osDisk.ResourceGroupName
        location = $osDisk.Location
        storageAccountType = $osDisk.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
    }
}




foreach($dataDisk in $vms){

    foreach($diskInfo in $dataDisk.storageProfile.dataDisks){
        $maxSharesCheck = (Get-AzDisk -Name $diskInfo.Name).MaxShares
        $diskName = (Get-AzDisk -Name $diskInfo.Name).Name

        #$diskIdRaw = $diskInfo.ManagedDisk.Id -replace  '.*\/'

        if($null -ne $maxSharesCheck){
            $dataDisksSharedSourceCollection += [pscustomobject]@{
                Name = $diskName
                location = $dataDisk.Location
                VMName = $dataDisk.Name
                DiskSizeGB = $diskInfo.DiskSizeGB
                resourceGroup = $dataDisk.ResourceGroupName
                #diskId = "/subscriptions/$($destSubId)/resourceGroups/$($dataDisk.ResourceGroupName)/providers/Microsoft.Compute/disks/$($diskIdRaw)" 
                sourceDiskId = $diskInfo.ManagedDisk.Id
                tier = (Get-AzDisk -Name $diskInfo.Name).Tier 
                MaxShares = $maxSharesCheck
                storageAccountType = $diskInfo.ManagedDisk.StorageAccountType
            }   
        }
        else{
            $dataDisksNSSourceCollection += [pscustomobject]@{
                Name = $diskName
                location = $dataDisk.Location
                VMName = $dataDisk.Name
                DiskSizeGB = $diskInfo.DiskSizeGB
                resourceGroup = $dataDisk.ResourceGroupName
                #diskId = "/subscriptions/$($destSubId)/resourceGroups/$($dataDisk.ResourceGroupName)/providers/Microsoft.Compute/disks/$($diskIdRaw)"
                sourceDiskId = $diskInfo.ManagedDisk.Id
                tier = (Get-AzDisk -Name $diskInfo.Name).Tier 
                storageAccountType = $diskInfo.ManagedDisk.StorageAccountType
                MaxShares = $maxSharesCheck
            }  
        }
    }
}



#Set context to dest sub
Set-AzContext -Subscription $destSubId


New-AzResourceGroup -Name $snapshotRG -Location $location

#OS Disk Snapshot Config & Create

foreach($vm in $osDisksCollection){

    if($vm.storageAccountType -eq "StandardSSD_LRS"){
        $storageAccountType = "Standard_LRS"
    }

    $snapshot = New-AzSnapshotConfig -SourceUri $vm.osDiskId -Location $vm.location -CreateOption copy  -SkuName $storageAccountType

    New-AzSnapshot -Snapshot $snapshot -SnapshotName "new$($vm.osDiskName)" -ResourceGroupName $snapshotRG

}


# Data Disks Shared Disk Snapshot Creation
foreach($disks in $dataDisksSharedSourceCollection){

    if($disks.storageAccountType -eq "StandardSSD_LRS"){
        $storageAccountType = "Standard_LRS"
    }

    $snapshot = New-AzSnapshotConfig -SourceUri $disks.sourceDiskId -Location $disks.location -CreateOption Copy -SkuName $storageAccountType 
    New-AzSnapshot -Snapshot $snapshot -SnapshotName "new$($disks.Name)" -ResourceGroupName $snapshotRG
}


# Data Disks Non Shared Disk Snapshot Creation
foreach($nonSharedDisks in $dataDisksNSSourceCollection){

    if($disks.storageAccountType -eq "StandardSSD_LRS"){
        $storageAccountType = "Standard_LRS"
    }


    $snapshot = New-AzSnapshotConfig -SourceUri $nonSharedDisks.sourceDiskId -Location $nonSharedDisks.location -CreateOption Copy -SkuName $storageAccountType
    New-AzSnapshot -Snapshot $snapshot -SnapshotName "new$($nonSharedDisks.Name)" -ResourceGroupName $snapshotRG
}

#OS Disk Snapshot Get, Disk Config, Disk Create & OS Disk Info Export

foreach($osDiskSnapshot in $osDisksCollection){

    $snapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name "new$($osDiskSnapshot.osDiskName)"

    $disksSnapshotObject= New-AzDiskConfig -SkuName $osDiskSnapshot.storageAccountType -Location $snapshotInfo.Location  -CreateOption $snapshotInfo.CreationData.CreateOption -SourceResourceId $snapshotInfo.Id -DiskSizeGB $snapshotInfo.DiskSizeGB

    $osDiskCreate = New-AzDisk -Disk $disksSnapshotObject -ResourceGroupName $osDiskSnapshot.resourceGroup -DiskName $snapshotInfo.Name -Verbose


    $newdOsDisksCreated = [pscustomobject]@{
        vmName = $osDiskSnapshot.VMName
        DiskSizeGB = $osDiskCreate.DiskSizeGB
        name = $osDiskCreate.Name 
        id = $osDiskCreate.Id
        resourceGroup = $osDiskCreate.ResourceGroupName
        location = $osDiskCreate.Location
    }

}


#Data Disk Shared Disks Snapshot Get, Disk Config, Disk Create & Data Disk Info Export

foreach($dataDiskSnapshot in $dataDisksSharedSourceCollection){


    $datadisksnapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name $dataDiskSnapshot.Name

    $dataDisksSnapshotObject= New-AzDiskConfig -SkuName $datadisksnapshotInfo.StorageAccountType -Location $datadisksnapshotInfo.Location  -CreateOption $datadisksnapshotInfo.CreationData.CreateOption -SourceResourceId $datadisksnapshotInfo.Id -DiskSizeGB $datadisksnapshotInfo.DiskSizeGB -MaxSharesCount $dataDiskSnapshot.MaxShares

    $dataDiskCreate = New-AzDisk -Disk $dataDisksSnapshotObject -ResourceGroupName $dataDiskSnapshot.resourceGroup -DiskName "new$($datadisksnapshotInfo.Name)" -Verbose

    $newSharedDataDisksCreated = [pscustomobject]@{
        vmName = $dataDiskSnapshot.VMName
        DiskSizeGB = $diskCdataDiskCreatereate.DiskSizeGB
        name = $dataDiskCreate.Name 
        id = $dataDiskCreate.Id
        resourceGroup = $dataDiskCreate.ResourceGroupName
        location = $dataDiskCreate.Location
    }
    
}


#Data Disk Non Shared Disks Snapshot Get, Disk Config, Disk Create & Data Disk Info Export

foreach($dataDiskNonSharedSnapshot in $dataDisksNSSourceCollection){


    $datadisksnapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name "new$($dataDiskNonSharedSnapshot.Name)"

    $dataNonSharedDisksSnapshotObject= New-AzDiskConfig -SkuName $dataDiskNonSharedSnapshot.StorageAccountType -Location $datadisksnapshotInfo.Location  -CreateOption $datadisksnapshotInfo.CreationData.CreateOption -SourceResourceId $datadisksnapshotInfo.Id -DiskSizeGB $datadisksnapshotInfo.DiskSizeGB

    $dataDiskCreate = New-AzDisk -Disk $dataNonSharedDisksSnapshotObject -ResourceGroupName $dataDiskNonSharedSnapshot.resourceGroup -DiskName $datadisksnapshotInfo.Name -Verbose

    $newNonSharedDataDisksCreated = [pscustomobject]@{
        vmName = $dataDiskSnapshot.VMName
        DiskSizeGB = $diskCdataDiskCreatereate.DiskSizeGB
        name = $dataDiskCreate.Name 
        id = $dataDiskCreate.Id
        resourceGroup = $dataDiskCreate.ResourceGroupName
        location = $dataDiskCreate.Location
    }
    
}


#Left to do

# 1. Create VM Config 


foreach($vmconfig in $vms){

    $nicCleanup = $vmconfig.NetworkProfile.NetworkInterfaces

    ##$subnetId = Get-AzNetworkInterface -Name 




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


    foreach($nicCollectionItem in $nicCollection){


        foreach($ipconfigSettingsCollection in $nicCollectionItem.IpConfigurations){

            if($ipconfigSettingsCollection.Primary -eq $true){
                $ipSettingsCreate = New-AzNetworkInterfaceIpConfig -Name $ipconfigSettingsCollection.Name -Subnet $ipconfigSettingsCollection.Subnet -Primary -PrivateIpAddress $ipconfigSettingsCollection.PrivateIpAddress -PrivateIpAddressVersion $ipconfigSettingsCollection.PrivateIpAddressVersion
            }
            elseif($ipconfigSettingsCollection.Primary -eq $false){
                $ipSettingsCreate = New-AzNetworkInterfaceIpConfig -Name $ipconfigSettingsCollection.Name -Subnet $ipconfigSettingsCollection.Subnet -PrivateIpAddress $ipconfigSettingsCollection.PrivateIpAddress -PrivateIpAddressVersion $ipconfigSettingsCollection.PrivateIpAddressVersion
            }
        }

        $nicCreate = New-AzNetworkInterface -Name "new$($nicCollectionItem.name)" -ResourceGroupName $nicCollectionItem.rg -location $nicCollectionItem.location  -IpConfiguration $ipSettingsCreate #-SubnetId $nicCollectionItem.subnetId


        $nicCreateCollection += [pscustomobject]@{
            name = $nicCreate.Name
            id = $nicCreate.Id
        }

    }

    $osDiskId = $vmConfig.StorageProfile.OsDisk.ManagedDisk.Id -replace $sourceSubId, $destSubId 

    $diskNamePattern = "(?<=disks/).*$"
    $diskName = [regex]::Match($osDiskId, $diskNamePattern).Value

    # Add "new" to the beginning of the disk name
    $newDiskName = "new" + $diskName

    # Replace the old disk name with the new disk name in the updated string
    $osDiskIdFormat = $osDiskId -replace $diskName, $newDiskName

    $vmConfigCollection = [pscustomobject]@{
        VMName = "new$($vmconfig.Name)"
        vmSize = $vmconfig.HardwareProfile.vmSize
        computerName = "new$($vmconfig.Name)"
        securityTypeStnd = "Standard"
        managedDiskId = $osDiskIdFormat
        createOption = $vmconfig.StorageProfile.OsDisk.CreateOption
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
        $newDiskName = "new" + $diskName

        # Replace the old disk name with the new disk name in the updated string
        $DataDiskIdFormat = $osDiskId -replace $diskName, $newDiskName




        $dataDiskRefCollection += [PSCustomObject]@{
            name = $datadiskref.Name
            DiskSizeGB = $datadiskref.DiskSizeGB
            Lun = $datadiskref.Lun
            Caching = $datadiskref.Caching
            CreateOption = $datadiskref.CreateOption
            Id = $DataDiskIdFormat
        }
    }

    foreach($dataDiskRefCollectionItem in $dataDiskRefCollection ){
        $config = Add-AzVMDataDisk -VM $config -ManagedDiskId $dataDiskRefCollectionItem.Id -Lun $dataDiskRefCollectionItem.Lun -CreateOption $dataDiskRefCollectionItem.CreateOption
        $config = Set-AzVMDataDisk -Caching $dataDiskRefCollectionItem.Caching -Lun $dataDiskRefCollectionItem.Lun -VM $config
    }


    $config

    
    #Key Vault Retrieve
    $keyvault= Get-AzKeyVault -VaultName $keyVaultName 
    $keyvaultId = $keyvault.ResourceId

    #Key Vault Secret
    $secretName = "$($vmConfigCollection.VMName)-admin-password"
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName
    $adminPassword = $secret.SecretValue
    $securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
    $adminCredential = New-Object System.Management.Automation.PSCredential ("localadmin", $securePassword)

    $linuxSecretName = "$($vmConfigCollection.VMName)-localadmin-ssh-private-key"
    $linuxSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $linuxSecretName
    $linuxAdminPassword = $linuxSecret.SecretValue
    $linuxSecurePassword = ConvertTo-SecureString $linuxAdminPassword -AsPlainText -Force
    $linuxAdminCredential = New-Object System.Management.Automation.PSCredential ("localadmin", $linuxSecurePassword)


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

   
    # Preserve existing configuration settings before setting the OS type
    #$config.NetworkProfile = $vm.NetworkProfile
    #$config.OSProfile = $vm.OSProfile
    #$config.StorageProfile = $vm.StorageProfile
    #$config.HardwareProfile = $vm.HardwareProfile



}




# 2. Attach OS Disks 
# 3. Attach Data Disks


