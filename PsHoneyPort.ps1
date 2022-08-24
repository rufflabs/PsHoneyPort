<#
.SYNOPSIS
    Listen on TCP ports and log event logs when a connection is made.

.DESCRIPTION
    Creates TCP listeners on the specified ports that accept a TCP
    client connection. Once a connection is made, logs an Event ID
    5002 that a connection was made, and the IP it was made from.

    Also creates a TCP listener on localhost:5500 used to tell the
    script to stop the listeners. This is done by connecting to that
    port from localhost, which can be done by launching the script
    with -Stop.

    On first launch, registers Event Source PsHoneyPort to the Windows
    Event Log service. Launch script with -Unregister to remove.

    Use the -Task switch when running via a Scheduled Task to launch 
    the listener script in a new PowerShell process in the background.

.PARAMETER Ports
    Comma seperated list of TCP ports to listen on.

.PARAMETER Unregister
    Removes the Event Source from the Event Log service.

.PARAMETER Stop
    Opens a TCP client connection to localhost:5500, which triggers
    the script running the various listeners to close down all the
    currently open ports, and remove relevant firewall rules.

.PARAMETER Task
    Specify that the script should be re-launched as a background
    task in a seperate PowerShell process.

.EXAMPLE
    Launch listeners on ports 21 and 22.

        PS C:\> .\PsHoneyPort.ps1 -Ports 21, 22

.EXAMPLE
    Launch as a task.

        PS C:\> .\PsHoneyPort.ps1 -Task -Ports 21, 22

.EXAMPLE
    Stop any running listeners.

        PS C:\> .\PsHoneyPort.ps1 -Stop

.EXAMPLE
    Unregister the Event Source from Event Logs if not used anymore.

        PS C:\> .\PsHoneyPort.ps1 -Unregister

#>
[CmdletBinding(DefaultParameterSetName = 'Listen')]
param(
    [parameter(Mandatory = $true,
        ParameterSetName = 'Listen')] 
    [int32[]]$Ports,
    [parameter(ParameterSetName = 'Unregister')]
    [switch]$Unregister,
    [parameter(ParameterSetName = 'Stop')]
    [switch]$Stop,
    [parameter(ParameterSetName = 'Listen')]
    [switch]$Task
)

$EventSource = "PsHoneyPort" # Report as this Source in Event Logs
$EventLog = "Application"    # The Event Log to write to.
$ControlPort = 5500          # Connection to this port stops all listeners.
$EventIdMessage = 5001       # Event ID for general messages.
$EventIdConnect = 5002       # Event ID for successful connections.
$EventIdStopped = 5003       # Event ID for when a listener is shutdown. 

$ListenerJobDefinition = {
    <#
    .SYNOPSIS
        Listens on a TCP Port and logs to Event Log when a connection is made.
    #>
    param(
        [int32]$Port,
        [string]$EventSource,
        [string]$EventLog,
        [int32]$EventIdMessage,
        [int32]$EventIdConnect,
        [int32]$EventIdStopped
    )

    begin {
        $Listener = New-Object System.Net.Sockets.TcpListener (New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $Port))

        # Check for existing firewall rule, if it doesn't exist create one allowing this port in.
        if($null -eq (Get-NetFirewallRule -Name "PsHoneyPortRule$($Port)" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name "PsHoneyPortRule$($Port)"  -DisplayName "PsHoneyPort Rule for Port $($Port)" -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow -Profile Domain | Out-Null

            $Message = "Created Firewall Rule: PsHoneyPortRule$($Port)"
            Write-EventLog -Message $Message -Source $EventSource -LogName $EventLog -EventId $EventIdMessage -EntryType Information
        }
    }
    
    process {
        try {
            $Message = "Starting PsHoneyPort Listener on port $($Port)."
            Write-EventLog -Message $Message -Source $EventSource -LogName $EventLog -EventId $EventIdMessage -EntryType Information
            
            # Enter loop, each connection that is made will stop the listener, and re-start the loop.
            while($true) {
                $Listener.Start()

                # AcceptTcpClient() is blocking until a connection is made.
                $Client = $Listener.AcceptTcpClient()
                $SourceIP = $Client.Client.RemoteEndPoint.ToString().Split(':')[0]
    
                # Check if Source IP is localhost, if it is, this is a signal to shutdown the listener.
                if($SourceIP -eq '127.0.0.1') {
                    $Message = "Received connection from localhost to port $($Port), shutting down listener."
                    Write-EventLog -Message $Message  -Source $EventSource -LogName $EventLog -EventId $EventIdStopped -EntryType Information

                    $Client.Close()
                    $Listener.Stop()

                    break
                }
                
                # Log details of the incoming connection to the Event Log.
                $Message = "SourceIP=$($SourceIP);DestinationPort=$($Port);Message=Received incomming connection from $($SourceIP) to port $($Port)."
                Write-EventLog -Message $Message  -Source $EventSource -LogName $EventLog -EventId $EventIdConnect -EntryType Information
    
                $Client.Close()
                $Listener.Stop()
            }
        }catch{
            # There was an error starting the listener, likely this port is already in use.
            $Message = "Error starting listener on port $($Port)"
            Write-EventLog -Message $Message  -Source $EventSource -LogName $EventLog -EventId $EventIdStopped -EntryType Information
        }
    }

    end {
        # After a listener is shutdown, or if there was an error starting the listener, remove the firewall rule so it doesn't linger.
        Remove-NetFirewallRule -Name "PsHoneyPortRule$($Port)"

        $Message = "Removed firewall rule PsHoneyPortRule$($Port)"
        Write-EventLog -Message $Message -Source $EventSource -LogName $EventLog -EventId $EventIdMessage -EntryType Information
    }
}

function Test-Administrator  
{
    <#
    .SYNOPSIS
        Returns true if the current user has Administrator privileges, false otherwise.
    #>
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $CurrentUser).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Connect-TcpPort {
    <#
    .SYNOPSIS
        Creates a TCP connection to localhost on the specified port.

    .PARAMETER Port
        A single TCP port to initiate a connection to. 
    #>
    param(
        [int32]$Port
    )

    Write-Output "Stopping PsHoneyPortJob on port $($Port)."
    (New-Object System.Net.Sockets.TcpClient('127.0.0.1', $Port) -ErrorAction SilentlyContinue) | Out-Null
    
    # Small delay, otherwise it doesn't appear to successfully connect and shutdown all listening ports.
    Start-Sleep -Seconds 5
}

if($Unregister) {
    # Remove the Event Source registration
    Remove-EventLog -Source $EventSource
    Write-Output "Event Source $($EventSource) has been unregistered from Event Logs."
    exit
}

if($Stop) {
    # Connects to localhost:5500, triggering the script to terminate all listeners.
    Connect-TcpPort -Port 5500
    exit
}

if($Task) {
    # Run the script in the background, spawn another PowerShell instance
    # and run this script with the specified Ports.
    if(Test-Administrator) {
        $Arguments = @(
            "-ExecutionPolicy Bypass"
            "-Command `"$($MyInvocation.MyCommand.Path)`""
            "-Ports $($Ports -Join ', ')" # Must be a string, cannot pass object between PowerShell sessions.
        )
        Start-Process "powershell.exe" -ArgumentList $Arguments -WindowStyle Hidden
    }else{
        Write-Error -Message "Requires Administrator privileges.`nPlease run this script as Administrator."
    }
    exit
}

# Must be administrator to run.
if(Test-Administrator) {
    
    # Setup Event Source if needed
    if([System.Diagnostics.EventLog]::SourceExists($EventSource)){
        # If the Event Source is already registered, use the Event Log it's registered to.
        $EventLog = [System.Diagnostics.EventLog]::LogNameFromSourceName($EventSource,"localhost")
        Write-Output "Logging to $($EventLog) Event Log as Event Source $($EventSource)."
    }else{
        # Register the Event Source to the specified Event Log if it isn't already registered.
        New-EventLog -LogName $EventLog -Source $EventSource
        Write-Output "Registered Event Source ($($EventSource)) in Event Log ($($EventLog))"
    }

    # Spawn PowerShell Jobs for each Port specified, using the $ListenerJobDefinition above.
    # Pass all needed arguments to this job.
    foreach($Port in $Ports) {
        # Jobs are named specifically, so they can be stopped based on the port in the name.
        Start-Job -Name "PsHoneyPortJob-$($Port)" -ScriptBlock $ListenerJobDefinition -ArgumentList $Port,$EventSource,$EventLog,$EventIdMessage,$EventIdConnect,$EventIdStopped
    }

    try{
        $Message = "Starting PsHoneyPort Control Port Listener on port $($ControlPort)."
        Write-EventLog -Message $Message  -Source $EventSource -LogName $EventLog -EventId $EventIdMessage -EntryType Information

        # Start a listener on localhost:5500, any connections to this from localhost will cause the script to terminate all listeners.
        $Listener = New-Object System.Net.Sockets.TcpListener (New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $ControlPort))
        $Listener.Start()
        $Client = $Listener.AcceptTcpClient()
        $SourceIP = $Client.Client.RemoteEndPoint.ToString().Split(':')[0]

        if($SourceIP -eq '127.0.0.1') {
            # Connection from localhost, stop listening
            $Message = "Received connection from localhost to control port $($ControlPort), shutting down all listeners."
            Write-EventLog -Message $Message  -Source $EventSource -LogName $EventLog -EventId $EventIdStopped -EntryType Information
            $Client.Close()
            $Listener.Stop()
        }
    }catch{
        # There was an error starting the listener, likely the control port is in use. Change in variables at the top of the script if needed.
        $Message = "Unable to start control listener on port 5500. Stopping all jobs. Please adjust control port on this server."   
        Write-EventLog -Message $Message  -Source $EventSource -LogName $EventLog -EventId $EventIdStopped -EntryType Information
    }finally{
        # Stop all listening jobs. Either the control port couldn't be opened, or we have been told to stop.
        if($null -ne (Get-Job -Name "PsHoneyPortJob-*" -ErrorAction SilentlyContinue)) {
            Get-Job -Name "PsHoneyPortJob-*" | ForEach-Object {
                Connect-TcpPort -Port $_.Name.Split('-')[1]
            }
            Start-Sleep -Seconds 10 # Wait a bit for the jobs to fully stop before removing them.
            Get-Job -Name "PsHoneyPortJob-*" | Remove-Job
        }else{
            Write-Output "No PsHoneyPortJob's were found."
        }
    }
}else{
    Write-Error -Message "Requires Administrator privileges.`nPlease run this script as Administrator."
}