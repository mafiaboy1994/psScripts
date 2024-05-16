
$osDisksCollection = @()

$dataDisksSharedCollection = @()
$dataDisksNonSharedCollection = @()
$dataDisksSharedSourceCollection = @()
$dataDisksNSSourceCollection = @()

$newNonSharedDataDisksCreated = @()
$newSharedDataDisksCreated = @()

$nicCollection = @()
$vmConfigCollection = @()
$ipConfigCollection = @()



$sourceSubId = ""
$destSubId = ""

$location = "uksouth"


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
        skuName = $osDisk.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
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
    $snapshot = New-AzSnapshotConfig -SourceUri $vm.osDiskId -Location $vm.location -CreateOption copy

    New-AzSnapshot -Snapshot $snapshot -SnapshotName $vm.osDiskName -ResourceGroupName $snapshotRG

}


# Data Disks Shared Disk Snapshot Creation
foreach($disks in $dataDisksSharedSourceCollection){

    $snapshot = New-AzSnapshotConfig -SourceUri $disks.sourceDiskId -Location $disks.location -CreateOption Copy 
    New-AzSnapshot -Snapshot $snapshot -SnapshotName $disks.Name -ResourceGroupName $snapshotRG
}


# Data Disks Non Shared Disk Snapshot Creation
foreach($nonSharedDisks in $dataDisksNSSourceCollection){
    $snapshot = New-AzSnapshotConfig -SourceUri $nonSharedDisks.sourceDiskId -Location $nonSharedDisks.location -CreateOption Copy 
    New-AzSnapshot -Snapshot $snapshot -SnapshotName $nonSharedDisks.Name -ResourceGroupName $snapshotRG
}

#OS Disk Snapshot Get, Disk Config, Disk Create & OS Disk Info Export

foreach($osDiskSnapshot in $osDisksCollection){

    $snapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name $osDiskSnapshot.osDiskName

    $disksSnapshotObject= New-AzDiskConfig -SkuName $osDiskSnapshot.skuName -Location $snapshotInfo.Location  -CreateOption $snapshotInfo.CreationData.CreateOption -SourceResourceId $snapshotInfo.Id -DiskSizeGB $snapshotInfo.DiskSizeGB

    $osDiskCreate = New-AzDisk -Disk $disksSnapshotObject -ResourceGroupName $osDiskSnapshot.resourceGroup -DiskName "new$($snapshotInfo.Name)" -Verbose


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

    $dataDisksSnapshotObject= New-AzDiskConfig -SkuName $datadisksnapshotInfo.Sku.Name -Location $datadisksnapshotInfo.Location  -CreateOption $datadisksnapshotInfo.CreationData.CreateOption -SourceResourceId $datadisksnapshotInfo.Id -DiskSizeGB $datadisksnapshotInfo.DiskSizeGB -MaxSharesCount $dataDiskSnapshot.MaxShares

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

foreach($dataDiskNonSharedSnapshot in $dataDisksNonSharedCollection){


    $datadisksnapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name $dataDiskSnapshot.Name

    $dataDisksSnapshotObject= New-AzDiskConfig -SkuName $datadisksnapshotInfo.Sku.Name -Location $datadisksnapshotInfo.Location  -CreateOption $datadisksnapshotInfo.CreationData.CreateOption -SourceResourceId $datadisksnapshotInfo.Id -DiskSizeGB $datadisksnapshotInfo.DiskSizeGB

    $dataDiskCreate = New-AzDisk -Disk $dataDisksSnapshotObject -ResourceGroupName $dataDiskNonSharedSnapshot.resourceGroup -DiskName "new$($datadisksnapshotInfo.Name)" -Verbose

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


# foreach($vmconfig in $vms){

#     $nicCleanup = $vmconfig.NetworkProfile.NetworkInterfaces

#     ##$subnetId = Get-AzNetworkInterface -Name 


#     foreach($nic in $nicCleanup){

#         $subnetId = Get-AzNetworkInterface -Name ($nic.Id -replace  '.*\/')

#         $ipConfigSettings = $subnetId.IpConfigurations | Select-Object *

#         foreach($ipconfig in $ipConfigSettings){

#             $subnetId01 = get-azsubnet - name $name

#             $ipConfigCollection += [pscustomobject]@{
#                 Name = $ipconfig.Name
#                 Primary = $ipconfig.Primary
#                 PrivateIpAddress = $ipconfig.PrivateIpAddress
#                 PublicIpAddress = $ipconfig.PublicIpAddress
#                 PrivateIpAllocationMethod = $ipconfig.PrivateIpAllocationMethod

#                 subnet = [pscustomobject]@{
#                     Id = 
#                 }
#             }

#         }
        


#         $nicCollection += [pscustomobject]@{
#             name = $nic.Id -replace  '.*\/'
#             subnetId = $subnetId
#         }
#     }


#     $vmConfigCollection += [pscustomobject]@{
#         VMName = $vmconfig.Name
#         vmSize = $vmconfig.HardwareProfile.vmSize
#         computerName = $vmconfig.Name
#         securityTypeStnd = "Standard"
#         publisherName = $vmconfig.StorageProfile.ImageReference.Publisher 
#         offer = $vmconfig.StorageProfile.ImageReference.Offer 
#         sku = $vmconfig.StorageProfile.ImageReference.Sku 
#         version = $vmconfig.StorageProfile.ImageReference.Version 
#         nics = $vmconfig.NetworkProfile
#         #subnetName = $vmconfig.

#     }
# }




# 2. Attach OS Disks 
# 3. Attach Data Disks


