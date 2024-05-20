$sourceSubId = "573cd9db-cbff-4e99-a3f5-cbaa167f127a"
$destSubId = "24b83476-de3e-41dd-bda7-60189e83dcb9"

#Set context to source sub
Set-AzContext -Subscription $destSubId

$disks = Get-AzDisk

foreach($disk in $disks){
    Remove-AzDisk -Name $disk.Name -ResourceGroupName $disk.ResourceGroupName -Force -Verbose
}

$snapshots = Get-AzSnapshot

foreach($snapshot in $snapshots){
    Remove-AzSnapshot -Name $snapshot.Name -ResourceGroupName $snapshot.ResourceGroupName -Force -Verbose
}

$vms = Get-AzVM  

foreach($vm in $vms){
    Remove-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -force
}