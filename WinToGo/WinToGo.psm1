Function Initialize-WTGStick {
    [CmdLetBinding()]
    Param (
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        $Disk,

        [Parameter(
            Mandatory=$true,
			ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        [String]$ComputerName,

        [Parameter(
            Mandatory=$false,
			ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        [String]$BitLockerPIN)
    Begin {
		$DebugPreference = 'Continue'
		Write-Debug -Message 'Entered Initialize-WTGStick function'
        $DriveLetters = 68..90 | ForEach-Object {"$([char]$_):"} | Where-Object {(New-Object System.IO.DriveInfo $_).DriveType -eq 'noRootdirectory'}
        $DriveIndex = 2
        $ConfirmPreference = 'Low'
    }
    Process {
        Foreach ($Item in $Disk) {
                        
            $SystemDriveLetter = $DriveLetters[$DriveIndex-1][0]
            $OSDriveLetter = $DriveLetters[$DriveIndex][0]
			Write-Debug -Message "Current value of SystemDriveLetter is: $SystemDriveLetter"
            Write-Debug -Message "Current value of OSDriveLetter is: $OSDriveLetter"
			Write-Debug -Message "Current disk number: $($Item.Number)"

			If (-not $BitLockerPIN) {
				Write-Verbose -Message "Generating BitLocker PIN"
                Write-Debug -Message "Generating BitLocker PIN"
                [String]$BitLockerPIN = (Get-Random -Minimum 10000000 -Maximum 99999999)
				Write-Debug -Message "BitLocker PIN is: $BitLockerPIN"
            }
            
			Write-Verbose -Message "Preparing the Windows To Go Stick"
            Write-Debug -Message "Clearing the disk"
            Clear-Disk –InputObject $Item -RemoveData -Confirm:$false
            Start-Sleep -Seconds 1

            Write-Debug -Message "Initializing the disk"
            Initialize-Disk –InputObject $Item -PartitionStyle MBR -Confirm:$false
        
            Write-Debug -Message "Defining the SystemPartion variable"
            $SystemPartition = New-Partition –InputObject $Item -Size 350MB -IsActive

            Write-Debug -Message "Defining the OSPartition variable"
            $OSPartition = New-Partition –InputObject $Item -UseMaximumSize
        
            Write-Debug -Message "Formatting the SystemPartition volume"
            Format-Volume -NewFileSystemLabel "UFD-System" -FileSystem FAT32 -Partition $SystemPartition -Confirm:$false | Out-Null
            Start-Sleep -Seconds 1

            Write-Debug -Message "Formatting the OSPartition volume ${OSDriveLetter}:"
            Format-Volume -NewFileSystemLabel "UFD-Windows" -FileSystem NTFS -Partition $OSPartition -Confirm:$false | Out-Null
            Start-Sleep -Seconds 1

            Write-Debug -Message "Setting the partition properties"
            Set-Partition -InputObject $SystemPartition -NewDriveLetter $SystemDriveLetter
            Set-Partition -InputObject $OSPartition -NewDriveLetter $OSDriveLetter
            Set-Partition -InputObject $OSPartition -NoDefaultDriveLetter $TRUE
                               
            If ($BitLockerPIN) {
				Write-Verbose -Message "Enabling BitLocker Drive Encryption"
                Write-Debug -Message "Converting BitLocker PIN to secure string. BitLocker PIN is: $BitlockerPIN"
                $spwd = ConvertTo-SecureString -String $BitLockerPIN -AsplainText –Force
            
                Write-Debug -Message "Enabling BitLocker on the volume ${OSDriveLetter}:"
                Enable-BitLocker -MountPoint ${OSDriveLetter}: -PasswordProtector $spwd -EncryptionMethod Aes256 -SkipHardwareTest -UsedSpaceOnly -Confirm:$False | Out-Null
            
                Write-Debug -Message "Adding recovery key protector to ${OSDriveLetter}:"
                Add-BitLockerKeyProtector -MountPoint ${OSDriveLetter}: -RecoveryPasswordProtector -Confirm:$False -WarningAction SilentlyContinue | Out-Null
            
                Write-Debug -Message "Defining the BDEVolume variable."
                $BDEVolume = Get-BitLockerVolume -MountPoint ${OSDriveLetter}
                            
                $BDEVolume.KeyProtector.RecoveryPassword | Out-File -FilePath "$env:SystemDrive\RecoveryKey_$ComputerName.txt" -Confirm:$false | Out-Null
                $BitLockerPIN | Out-File -FilePath "$env:SystemDrive\RecoveryKey_$ComputerName.txt" -Confirm:$false -Append | Out-Null
            
            }
            $DriveIndex = $DriveIndex + 2
            $OSVolume = Get-Volume -Partition $OSPartition
			Write-Verbose -Message "Finished initializing the Windows To Go Stick"
            Write-Debug -Message "Finished initializing the disk. Returning to pipeline."
            $OSVolume
        }
        
    }
    End {
		Write-Debug -Message 'Exiting Initialize-WTGStick function'
	}
}
Function Write-WTGStick {
    [CmdLetBinding()]
    Param (
        [Parameter(
			Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String]$DriveLetter,

        [Parameter(
			Mandatory=$true, 
            ValueFromPipeline=$false,
            ValueFromPipelineByPropertyName=$false)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        $Image,

        [Parameter(
			Mandatory=$true,
			ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        $ComputerName,

        [Parameter(
			Mandatory=$true,
			ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        $Unattend)
    Begin {
        $DebugPreference = 'Continue'
		Write-Debug -Message 'Entered Write-WTGStick function'

		Write-Debug -Message 'Defining the XML variable for the unattend file'
        $Xml = New-Object -TypeName XML
        Write-Debug "Current value of Unattend is: $Unattend"
        $Xml.Load($Unattend)
    } 
    Process {
		Write-Verbose -Message 'Writing the Windows Image File to the Windows To Go Stick'
        Write-Debug -Message "Writing $Image to volume ${DriveLetter}:"
        Expand-WindowsImage -ImagePath $Image -ApplyPath ${DriveLetter}:\ -Index 1 -LogPath "$env:SystemRoot\Temp\WTG-Dism-$ComputerName.log" | Out-Null

        Write-Debug -Message "Modifying the Unattend.xml file to change the workstation name to $ComputerName"
        $Xml.unattend.settings.component | Where-Object { $_.Name -eq "Microsoft-Windows-Shell-Setup" } | ForEach-Object { 
            if($_.ComputerName) {
                $_.ComputerName = "$ComputerName"
            }
        }
        Write-Debug -Message 'Saving the Unattend file to the WTG stick'
        $Xml.Save("${DriveLetter}:\Windows\System32\Sysprep\unattend.xml")
    }
    End {
		Write-Debug -Message 'Exiting Write-WTGStick function'
	}
}
function Join-WTGDomain {
    [CmdletBinding()]
    Param (
        [Parameter(
			Mandatory=$true,
            ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        [String]$Domain,

        [Parameter(
			Mandatory=$true,
            ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        [String]$Unattend,

        [Parameter(
			Mandatory=$true,
			ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        [String]$ComputerName,

        [Parameter(
			Mandatory=$true,
			ValueFromPipeline=$false,
			ValueFromPipelineByPropertyName=$false)]
        [String]$DriveLetter
    )

    Begin {
        $DebugPreference = 'Continue'
		Write-Debug -Message 'Entered Join-WTGDomain function'
		
		Write-Debug -Message 'Defining the XML variable for the unattend file'
        $Xml = New-Object -TypeName XML
        Write-Debug "Current value of Unattend is: $Unattend"
        $Xml.Load($Unattend)
    }
    Process {
        Write-Verbose -Message "Joining the Windows To Go Stick to the domain $Domain"
        Write-Debug -Message "Modifying Unattend.xml file to join the $Domain domain"
        $JoinXML = $Xml.unattend.settings.component | Where-Object { $_.Name -eq "Microsoft-Windows-UnattendedJoin" }
        $JoinXML.Identification.JoinDomain = "$Domain"

        Write-Debug -Message "Preparing to Domain Join $ComputerName to $Domain"
        Start-Process -FilePath "$env:SystemRoot\System32\djoin.exe" -ArgumentList "/PROVISION /DOMAIN $Domain /SAVEFILE ${DriveLetter}:\Windows\ODJ.bin /MACHINE $ComputerName" -Wait -WindowStyle Hidden
        Write-Debug -Message "Executing Domain Join for Offline Domain Join"
        Start-Process -FilePath "$env:SystemRoot\System32\djoin.exe" -ArgumentList "/REQUESTODJ /LOADFILE ${DriveLetter}:\Windows\ODJ.bin /WINDOWSPATH ${DriveLetter}:\Windows" -Wait -WindowStyle Hidden

        Write-Debug -Message "Saving the Unattend file to the stick at ${DriveLetter}:\Windows\System32\Sysprep"
        $Xml.Save("${DriveLetter}:\Windows\System32\Sysprep\unattend.xml")
		Write-Verbose -Message 'Successfully wrote domain information to the Windows To Go Stick'
    }
    End {
		Write-Debug -Message 'Exiting Join-WTGDomain function'
    }
}
