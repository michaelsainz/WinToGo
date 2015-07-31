$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")
#. "$here\$sut"
Import-Module -Name .\WinToGo.psm1 -Force

Describe 'Initialize-WTGStick Tests' {
    
    $Disks = Get-Disk | Where-Object {$_.Size -gt 20Gb -and -not $_.IsBoot}
    $DriveLetters = 68..90 | ForEach-Object {"$([char]$_):"} | Where-Object {(New-Object System.IO.DriveInfo $_).DriveType -eq 'noRootdirectory'}
    $DriveIndex = 2
    
    It 'Testing parameterarized individual Disk' {
        
        $Result = Initialize-WTGStick -Disk $Disks[0] -ComputerName TEST
        $Result | Should Not BeNullOrEmpty
        $Result.DriveLetter | Should Not BeNullOrEmpty

    }
   
    It 'Testing parameterized multiple disks' {

        $Result = Initialize-WTGStick -Disk $Disks -ComputerName TEST
        $Result | Should Not BeNullOrEmpty
        $Result.DriveLetter | Should Not BeNullOrEmpty

    }

    It 'Testing with pipeline support of single disk' {
        
        $Result = $Disks[0] | Initialize-WTGStick -ComputerName TEST
        $Result | Should Not BeNullOrEmpty
        $Result.DriveLetter | Should Not BeNullOrEmpty

    }

    It 'Testing with pipeline support of multiple disks' {
        
        $Result = $Disks | Initialize-WTGStick -ComputerName TEST
        $Result | Should Not BeNullOrEmpty
        $Result.DriveLetter | Should Not BeNullOrEmpty

    }
}
Describe 'Write-WTGStick Tests' {
    BeforeEach {
        
        $Disks = Get-Disk | Where-Object {$_.Size -gt 20Gb -and -not $_.IsBoot}
        $ImagePath = "C:\Users\Administrator\Documents\install.wim"
        $Unattend = "C:\Users\Administrator\Documents\unattend.xml"
        $OSVolume = Initialize-WTGStick -Disk $Disks[0] -ComputerName TEST -BitLockerPIN 11223344
        $OSDriveLetter = $OSVolume.DriveLetter.ToString()

    }

    It 'Testing with OSDriveLetter as a String character in the parameter -DriveLetter' {
        
        $Result = Write-WTGStick -DriveLetter $OSDriveLetter -Image $ImagePath -ComputerName TEST -Unattend $Unattend
        $Result | Should BeNullOrEmpty

    }

    It 'Testing with OSVolume object in the parameter -DriveLetter' {
    
        $Result = Write-WTGStick -DriveLetter $OSVolume.DriveLetter -Image $ImagePath -ComputerName TEST -Unattend $Unattend
        $Result | Should BeNullOrEmpty

    }

    It 'Testing OSVolume as an object in the pipeline' {
    
        $Result = $OSVolume | Write-WTGStick -Image $ImagePath -ComputerName TEST -Unattend $Unattend
        $Result | Should BeNullOrEmpty
    
    }
}
