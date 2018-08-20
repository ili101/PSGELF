﻿<#
.Synopsis
   Sends an PSObject to Graylog via TCP.
.DESCRIPTION
   This function sends an PSObject to Graylog via TCP to a server supporting
   GELF. This function should be used if you do want to pipe input.
.PARAMETER GelfServer
   Hostname or IP address of the GELF server to send messages to.
.PARAMETER Port
   Port number used to communicate with the GELF server.
.PARAMETER Encrypt
   Use to use SSL/TLS encryption with the GELF server.
.PARAMETER GelfMessage
   Message payload to send (from New-PSGelfObject).
.EXAMPLE
   Get-WinEvent Setup | Send-PSGelfTCPFromObject -GelfServer graylog -Port 12201
#>
function Send-PSGelfTCPFromObject
{
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory)][String]$GelfServer,

        [Parameter(Mandatory)][Int]$Port,

        [Parameter()][Switch]$Encrypt,

        [Parameter(Mandatory,ValueFromPipeline)][PSCustomObject]$GelfMessage
    )

    Process
    {
        try {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { return $true }

            $TcpClient = New-Object System.Net.Sockets.TcpClient

            #I am using ConnectAsync because connect isnt supported in .net core
            $Connect = $TcpClient.ConnectAsync($GelfServer,$Port)
            if(!($Connect.Wait(500))) {
                Write-Error "The connection timed out."
                return
            }

            if ($Encrypt.IsPresent) {
                $SslStream = New-Object System.Net.Security.SslStream $TcpClient.GetStream(), $false, { return $true }, $null
                $SslStream.AuthenticateAsClient($GelfServer)
            }
            else {
                $TcpStream = $TcpClient.GetStream()
            }

            #Repair-PasGelfObject changes fields names so you can easily pipe Get-WinEvent to this function
            #It also adds and underscore to non default fields.
            $RepairedGelfMessage = Repair-PSGelfObject -GelfMessage $GelfMessage

            $ConvertedJSON = [System.Text.Encoding]::ASCII.GetBytes($($RepairedGelfMessage | ConvertTo-Json -Compress))

            #Graylog needs a NULL byte on the end of the data packet
            $ConvertedJSON = $ConvertedJSON + [Byte]0x00

            if ($Encrypt.IsPresent) {
                $SslStream.Write($ConvertedJSON, 0, $ConvertedJSON.Length)
                $SslStream.Close()
            }
            else {
                $TcpStream.Write($ConvertedJSON, 0, $ConvertedJSON.Length)
                $TcpStream.Close()
            }

            $TcpClient.Close()
        }
        Catch {
            $_
        }
    }
}