# PsHoneyPort
PowerShell script to listen on TCP ports and log to Event Log when connections are made.

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
