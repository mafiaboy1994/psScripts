
$osDisksCollection = @()
$dataDisksCollection = @()


$sourceSubId = ""
$destSubId = ""

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
    $dataDisksCollection += [pscustomobject]@{
        VMName = $dataDisk.Name
        location = $dataDisk.location
        dataDisks = $dataDisk.StorageProfile.DataDisks
        resourceGroup = $dataDisk.ResourceGroupName

    }
}

#Set context to dest sub
Set-AzContext -Subscription $destSubId


New-AzResourceGroup -Name $snapshotRG -Location "uksouth"

foreach($vm in $osDisksCollection){
    $snapshot = New-AzSnapshotConfig -SourceUri $vm.osDiskId -Location $vm.location -CreateOption copy

    New-AzSnapshot -Snapshot $snapshot -SnapshotName $vm.osDiskName -ResourceGroupName $snapshotRG

}


foreach($disks in $dataDisksCollection){
    foreach($disk in $disks.dataDisks){
        $snapshot = New-AzSnapshotConfig -SourceUri $disk.ManagedDisk.Id -Location $disks.location -CreateOption Copy 
        New-AzSnapshot -Snapshot $snapshot -SnapshotName $disk.Name -ResourceGroupName $snapshotRG
    }
}


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


foreach($dataDiskSnapshot in $dataDisksCollection){

    foreach($disk in $dataDiskSnapshot.dataDisks){

        $datadisksnapshotInfo = Get-AzSnapshot -ResourceGroupName $snapshotRG -Name $disk.Name

        $dataDisksSnapshotObject= New-AzDiskConfig -SkuName $disk.ManagedDisk.StorageAccountType -Location $datadisksnapshotInfo.Location  -CreateOption $datadisksnapshotInfo.CreationData.CreateOption -SourceResourceId $datadisksnapshotInfo.Id -DiskSizeGB $disk.DiskSizeGB

        $dataDiskCreate = New-AzDisk -Disk $dataDisksSnapshotObject -ResourceGroupName $dataDiskSnapshot.resourceGroup -DiskName "new$($datadisksnapshotInfo.Name)" -Verbose

        $newdataDisksCreated = [pscustomobject]@{
            vmName = $dataDiskSnapshot.VMName
            DiskSizeGB = $diskCdataDiskCreatereate.DiskSizeGB
            name = $dataDiskCreate.Name 
            id = $dataDiskCreate.Id
            resourceGroup = $dataDiskCreate.ResourceGroupName
            location = $dataDiskCreate.Location
        }


    }  
}




