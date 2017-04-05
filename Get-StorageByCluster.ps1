 <# 
Get-storageInfoByCluster

.Description
    Get cluster LUN info
	russ 05/04/2017
    
.Example
    ./Get-StorageByCluster.ps1
     Script will prompt to select a cluster
 
.Creadits
    I can't remember where I first saw the storage code, I have been using it for years..
#>



# Get Cluster info and populate $vms  
$Cluster = Get-Cluster  
$countCL = 0  
Write-Output " "  
Write-Output "Clusters: "  
Write-Output " "  
	foreach($oC in $Cluster){  
       Write-Output "[$countCL] $oc"  
       $countCL = $countCL+1  
       }  
$choice = Read-Host "Which Cluster do you want to review?"  
Write-Output " "  
Write-host "please wait for script to finish, it may take a while...." -ForegroundColor Yellow
$clusName = get-cluster $cluster[$choice]


# Save to path with unique name
$datacenter = get-cluster $clusName | get-datacenter 
$filepath = "C:\PowerCLI\Output\"
if (!(Test-path $filepath)){ New-Item -Path $filepath -ItemType Directory}
else { Write-host "ok, path exists"} 
$filename = "ClusterStorage"
$initalTime = Get-Date
$date = Get-Date ($initalTime) -uformat %Y%m%d
$time = Get-Date ($initalTime) -uformat %H%M
Write-Host "---------------------------------------------------------" -ForegroundColor DarkYellow
Write-Host "Output will be saved to:"  				       -ForegroundColor Yellow
Write-Host $filepath$datacenter$clusName-$filename-$date$time".csv"    -ForegroundColor White
Write-Host "---------------------------------------------------------" -ForegroundColor DarkYellow

$clusName | Select Name

$rndNum = Get-Random -Maximum 99999
$LunInfoDef = @"
	public string ClusterName;
	public string CanonicalName;
	public string UsedBy;
	public string SizeMB;
"@
$LunInfoDef = "public struct LunInfo" + $rndNum + "{`n" + $LunInfoDef

$esxServers = Get-Cluster $clusName | Get-VMHost | Sort-Object -Property Name
$esxServers | %{
	$LunInfoDef += ("`n`tpublic string " + ($_.Name.Split(".")[0]) + ";")
}
$LunInfoDef += "`n}"

Add-Type -Language CsharpVersion3 -TypeDefinition $LunInfoDef

$scsiTab = @{}
$esxServers | %{
	$esxImpl = $_

# Get SCSI LUNs
	$esxImpl | Get-ScsiLun | where {$_.LunType -eq "Disk"} | %{

		$key = $esxImpl.Name.Split(".")[0] + "-" + $_.CanonicalName.Split(".")[1]
		if(!$scsiTab.ContainsKey($key)){

			$scsiTab[$key] = $_.CanonicalName,"",$_.CapacityMB
		}
	}

# Get the VMFS datastores
	$esxImpl | Get-Datastore | where {$_.Type -eq "VMFS"} | Get-View | %{
		$dsName = $_.Name
		$_.Info.Vmfs.Extent | %{
			$key = $esxImpl.Name.Split(".")[0] + "-" + $_.DiskName.Split(".")[1]
			$scsiTab[$key] = $scsiTab[$key][0], $dsName, $scsiTab[$key][2]
		}
	}
}

# Get the RDM disks
Get-Cluster $clusName | Get-VM | Get-View | %{
	$vm = $_
	$vm.Config.Hardware.Device | where {$_.gettype().Name -eq "VirtualDisk"} | %{
		if("physicalMode","virtualmode" -contains $_.Backing.CompatibilityMode){
			$disk = $_.Backing.LunUuid.Substring(10,32)
			$key = (Get-View $vm.Runtime.Host).Name.Split(".")[0] + "-" + $disk
			$scsiTab[$key][1] = $vm.Name + "/" + $_.DeviceInfo.Label
		}
	}
}

$scsiTab.GetEnumerator() | Group-Object -Property {$_.Key.Split("-")[1]} | %{
	$lun = New-Object ("LunInfo" + $rndNum)
	$lun.ClusterName = $clusName
	$_.Group | %{
		$esxName = $_.Key.Split("-")[0]
		$lun.$esxName = "ok"
		if(!$lun.CanonicalName){$lun.CanonicalName = $_.Value[0]}
		if(!$lun.UsedBy){$lun.UsedBy = $_.Value[1]}
		if(!$lun.SizeMB){$lun.SizeMB = $_.Value[2]}

	}
	$lun
} | Export-Csv $filepath$filename"-"$datacenter$cluster"-"$date$time".csv" -NoType

Invoke-Item $filepath$filename"-"$datacenter$cluster"-"$date$time".csv"
