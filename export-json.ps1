Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Load SQLite DLL manually from local file
$sqliteDllPath = "D:\Work\PhotoBooth\Data\System.Data.SQLite.dll"
if (-not (Test-Path $sqliteDllPath)) {
    try {
        Invoke-WebRequest -Uri "https://github.com/trankien27/print-fs/raw/refs/heads/main/System.Data.SQLite.dll" `
            -OutFile $sqliteDllPath -UseBasicParsing
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Cannot download SQLite DLL. Check internet connection or update URL.", "DLL Load Error")
        exit
    }
}
Add-Type -Path $sqliteDllPath

if (![System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe "-STA -WindowStyle Normal -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# SQLite Connection
$global:DbPath = "D:\Work\PhotoBooth\Data\Funstudio.db"
$connectionString = "Data Source=$global:DbPath;Version=3;"
$global:SQLiteConnection = New-Object -TypeName System.Data.SQLite.SQLiteConnection -ArgumentList $connectionString

function Open-SQLiteConnection {
    try {
        $global:SQLiteConnection.Open()
    } catch {
        $msg = "Cannot connect to database: $global:DbPath`nError: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($msg, "Database Error")
        throw
    }
}

function Close-SQLiteConnection {
    if ($global:SQLiteConnection.State -eq 'Open') {
        $global:SQLiteConnection.Close()
    }
}

function Show-LoginForm {
    $correctPasswords = @("funstud!o", "kien", "quoc", "vanh")

    $loginForm = New-Object System.Windows.Forms.Form
    $loginForm.Text = "Login"
    $loginForm.Size = New-Object System.Drawing.Size(400, 220)
    $loginForm.StartPosition = "CenterScreen"
    $loginForm.TopMost = $true
    $loginForm.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter password:"
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(350, 30)
    $loginForm.Controls.Add($label)

    $textbox = New-Object System.Windows.Forms.TextBox
    $textbox.Location = New-Object System.Drawing.Point(20, 60)
    $textbox.Size = New-Object System.Drawing.Size(340, 30)
    $textbox.UseSystemPasswordChar = $true
    $loginForm.Controls.Add($textbox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(70, 110)
    $okButton.Size = New-Object System.Drawing.Size(100, 40)
    $loginForm.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Exit"
    $cancelButton.Location = New-Object System.Drawing.Point(200, 110)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 40)
    $loginForm.Controls.Add($cancelButton)

    $okButton.Add_Click({
        if ($correctPasswords -contains $textbox.Text) {
            $loginForm.Tag = $true
            $loginForm.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Wrong password!", "Error")
            $textbox.Clear()
        }
    })

    $cancelButton.Add_Click({
        $loginForm.Tag = $false
        $loginForm.Close()
    })

    $loginForm.AcceptButton = $okButton
    $loginForm.CancelButton = $cancelButton

    [void]$loginForm.ShowDialog()
    return $loginForm.Tag -eq $true
}

function Write-ApiLog {
    param(
        [string]$message
    )

    try {
        $logDir = "D:\Work\PhotoBooth\Logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $logPath = Join-Path $logDir "process-api.log"
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch {
    }
}

function Show-WaitForm {
    param(
        [string]$text
    )

    # The API call blocks the UI thread, so show a small window before sending
    $waitForm = New-Object System.Windows.Forms.Form
    $waitForm.Text = "Please wait"
    $waitForm.Size = New-Object System.Drawing.Size(460, 150)
    $waitForm.StartPosition = "CenterScreen"
    $waitForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $waitForm.ControlBox = $false
    $waitForm.TopMost = $true
    $waitForm.ShowInTaskbar = $false
    $waitForm.Font = New-Object System.Drawing.Font("Segoe UI", 11)

    $lblWait = New-Object System.Windows.Forms.Label
    $lblWait.Text = $text
    $lblWait.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lblWait.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $waitForm.Controls.Add($lblWait)

    $waitForm.Show()
    $waitForm.Refresh()
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    return $waitForm
}

function Close-WaitForm {
    param(
        $waitForm
    )

    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    if ($null -ne $waitForm) {
        $waitForm.Close()
        $waitForm.Dispose()
    }
}

function Send-ToPrintAPI {
    param (
        [string]$transactionId,
        [string]$layoutId,
        [int]$numberOfImage = 1,
        [string]$apiUrl = "http://localhost:8088/api/print/printimage"
    )

    try {
        $body = @{
            transactionId = $transactionId
            layoutId      = $layoutId
            numberOfImage = $numberOfImage
        }

        $json = $body | ConvertTo-Json -Depth 3
        $waitForm = Show-WaitForm -text "Sending to printer...`r`nPlease wait."
        try {
            $null = Invoke-RestMethod -Uri $apiUrl -Method POST -Body $json -ContentType "application/json"
        } finally {
            Close-WaitForm -waitForm $waitForm
        }
        [System.Windows.Forms.MessageBox]::Show("Print successfully!", "Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Send error: $($_.Exception.Message)", "Error")
    }
}

function Send-ToProcessAPI {
    param (
        [string]$transactionId,
        [string]$apiUrl,
        [string]$apiName,
        [string]$requestJson = ""
    )

    $json = $null

    try {
        if ([string]::IsNullOrWhiteSpace($requestJson)) {
            $json = Get-TransactionJson -transactionId $transactionId -apiName $apiName
        } else {
            # Edited retry JSON is sent directly and is never written to SQLite.
            $null = $requestJson | ConvertFrom-Json -ErrorAction Stop
            $json = $requestJson
        }

        if (-not $json) {
            [System.Windows.Forms.MessageBox]::Show("Transaction not found for $apiName!", "Error")
            return
        }

        $txtJson.Text = @"
===== $apiName REQUEST URL =====
$apiUrl

===== $apiName REQUEST BODY =====
$json

Sending API $apiName...
"@

        Write-ApiLog "$apiName REQUEST_URL=$apiUrl"
        Write-ApiLog "$apiName REQUEST_BODY=$json"

        $txtJson.Refresh()
        $waitForm = Show-WaitForm -text "Sending $apiName...`r`nBE is generating, this can take a while. Please wait."
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-WebRequest `
                -Uri $apiUrl `
                -Method POST `
                -Body $json `
                -ContentType "application/json" `
                -UseBasicParsing
        } finally {
            $stopwatch.Stop()
            Close-WaitForm -waitForm $waitForm
            Write-ApiLog "$apiName DURATION=$([int]$stopwatch.Elapsed.TotalSeconds)s"
        }

        $responseCode = [int]$response.StatusCode
        $responseBody = $response.Content

        if ([string]::IsNullOrWhiteSpace($responseBody)) {
            $responseBody = "Empty response"
        }

        $logText = @"
===== $apiName REQUEST URL =====
$apiUrl

===== $apiName REQUEST BODY =====
$json

===== $apiName RESPONSE CODE =====
$responseCode

===== $apiName RESPONSE BODY =====
$responseBody
"@

        $txtJson.Text = $logText

        Write-ApiLog "$apiName RESPONSE_CODE=$responseCode"
        Write-ApiLog "$apiName RESPONSE_BODY=$responseBody"

        [System.Windows.Forms.MessageBox]::Show("$apiName completed successfully!`nResponse Code: $responseCode`nTime: $([int]$stopwatch.Elapsed.TotalSeconds)s", "Success")
    }
    catch {
        $responseCode = "Unknown"
        $responseBody = $_.Exception.Message

        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $responseBody = $_.ErrorDetails.Message
        }

        try {
            if ($_.Exception.Response -ne $null) {
                $responseCode = [int]$_.Exception.Response.StatusCode

                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream -ne $null) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $body = $reader.ReadToEnd()

                    if (-not [string]::IsNullOrWhiteSpace($body)) {
                        $responseBody = $body
                    }

                    $reader.Close()
                }
            }
        } catch {
        }

        $logText = @"
===== $apiName REQUEST URL =====
$apiUrl

===== $apiName REQUEST BODY =====
$json

===== $apiName RESPONSE CODE =====
$responseCode

===== $apiName RESPONSE BODY =====
$responseBody
"@

        $txtJson.Text = $logText

        Write-ApiLog "$apiName ERROR_REQUEST_URL=$apiUrl"
        Write-ApiLog "$apiName ERROR_REQUEST_BODY=$json"
        Write-ApiLog "$apiName ERROR_RESPONSE_CODE=$responseCode"
        Write-ApiLog "$apiName ERROR_RESPONSE_BODY=$responseBody"

        Show-ProcessRetryPopup `
            -transactionId $transactionId `
            -apiUrl $apiUrl `
            -apiName $apiName `
            -json $json `
            -responseCode $responseCode `
            -responseBody $responseBody
    }
}

function Remove-ImageFilterSuffix {
    param(
        [string]$json
    )

    # Use the original photo: drop everything after the first "_" (134393938321887466_f35.png -> 134393938321887466.png)
    $pattern = '_[^\\/]*(?=\.[^\\/.]+$)'

    try {
        $body = $json | ConvertFrom-Json -ErrorAction Stop

        if ($null -ne $body.listImages) {
            foreach ($image in @($body.listImages)) {
                if ($null -ne $image -and $null -ne $image.fileName) {
                    $image.fileName = ([string]$image.fileName) -replace $pattern, ''
                }
            }
        }

        # Selfbooth: listImages of each frame in photoPackageDetails
        if ($null -ne $body.photoPackageDetails) {
            foreach ($detail in @($body.photoPackageDetails)) {
                foreach ($image in @($detail.listImages)) {
                    if ($null -ne $image -and $null -ne $image.fileName) {
                        $image.fileName = ([string]$image.fileName) -replace $pattern, ''
                    }
                }
            }
        }

        return ($body | ConvertTo-Json -Depth 20)
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "JSON is invalid: $($_.Exception.Message)",
            "Invalid JSON"
        )
        return $json
    }
}

function Show-ProcessRetryPopup {
    param(
        [string]$transactionId,
        [string]$apiUrl,
        [string]$apiName,
        [string]$json,
        [string]$responseCode,
        [string]$responseBody
    )

    $retryForm = New-Object System.Windows.Forms.Form
    $retryForm.Text = "$apiName failed - Edit JSON and retry"
    $retryForm.Size = New-Object System.Drawing.Size(900, 720)
    $retryForm.StartPosition = "CenterParent"
    $retryForm.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $retryForm.TopMost = $false
    $retryForm.ShowInTaskbar = $false

    $lblError = New-Object System.Windows.Forms.Label
    $lblError.Text = "Response code: $responseCode`r`n$responseBody"
    $lblError.Location = New-Object System.Drawing.Point(15, 15)
    $lblError.Size = New-Object System.Drawing.Size(850, 85)
    $lblError.AutoEllipsis = $true
    $retryForm.Controls.Add($lblError)

    $txtRetryJson = New-Object System.Windows.Forms.TextBox
    $txtRetryJson.Location = New-Object System.Drawing.Point(15, 110)
    $txtRetryJson.Size = New-Object System.Drawing.Size(850, 500)
    $txtRetryJson.Multiline = $true
    $txtRetryJson.ScrollBars = "Both"
    $txtRetryJson.WordWrap = $false
    $txtRetryJson.AcceptsTab = $true
    $txtRetryJson.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtRetryJson.Text = $json
    $retryForm.Controls.Add($txtRetryJson)

    $btnRemoveF1 = New-Object System.Windows.Forms.Button
    $btnRemoveF1.Text = "Remove filter"
    $btnRemoveF1.Location = New-Object System.Drawing.Point(15, 625)
    $btnRemoveF1.Size = New-Object System.Drawing.Size(140, 38)
    $retryForm.Controls.Add($btnRemoveF1)

    $btnRetry = New-Object System.Windows.Forms.Button
    $btnRetry.Text = "Send again"
    $btnRetry.Location = New-Object System.Drawing.Point(575, 625)
    $btnRetry.Size = New-Object System.Drawing.Size(140, 38)
    $retryForm.Controls.Add($btnRetry)

    $btnCloseRetry = New-Object System.Windows.Forms.Button
    $btnCloseRetry.Text = "Close"
    $btnCloseRetry.Location = New-Object System.Drawing.Point(725, 625)
    $btnCloseRetry.Size = New-Object System.Drawing.Size(140, 38)
    $retryForm.Controls.Add($btnCloseRetry)

    $btnRemoveF1.Add_Click({
        $txtRetryJson.Text = Remove-ImageFilterSuffix -json $txtRetryJson.Text
    })

    $btnRetry.Add_Click({
        try {
            $null = $txtRetryJson.Text | ConvertFrom-Json -ErrorAction Stop
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "JSON is invalid: $($_.Exception.Message)",
                "Invalid JSON"
            )
            return
        }

        $editedJson = $txtRetryJson.Text
        $retryForm.Close()
        Send-ToProcessAPI `
            -transactionId $transactionId `
            -apiUrl $apiUrl `
            -apiName $apiName `
            -requestJson $editedJson
    })

    $btnCloseRetry.Add_Click({
        $retryForm.Close()
    })

    [void]$retryForm.ShowDialog($form)
}

function Send-ToProcessImageAPI {
    param(
        [string]$transactionId
    )

    Send-ToProcessAPI `
        -transactionId $transactionId `
        -apiUrl "http://localhost:8088/api/file/processimage" `
        -apiName "ProcessImage"
}

function Send-ToProcessVideoAPI {
    param(
        [string]$transactionId
    )

    Send-ToProcessAPI `
        -transactionId $transactionId `
        -apiUrl "http://localhost:8088/api/file/processvideo" `
        -apiName "ProcessVideo"
}

function Show-ImagePopup {
    param(
        [string]$transactionId
    )

    # Frame 1 = {id}.png, selfbooth frame n = {id}_n.png
    $folder = "D:\Work\PhotoBooth\Image\$transactionId"
    $imagePaths = @()
    if (Test-Path $folder) {
        $pattern = "^" + [regex]::Escape($transactionId) + "(?:_(\d+))?\.png$"
        $imagePaths = @(Get-ChildItem -Path $folder -Filter "*.png" -File |
            Where-Object { $_.Name -match $pattern } |
            Sort-Object { if ($_.Name -match $pattern -and $Matches[1]) { [int]$Matches[1] } else { 1 } } |
            ForEach-Object { $_.FullName })
    }

    if ($imagePaths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Image not found:`n$folder\$transactionId.png", "Error")
        return
    }

    $imgForm = New-Object System.Windows.Forms.Form
    $imgForm.Text = "Preview - $transactionId ($($imagePaths.Count) image)"
    $imgForm.Size = New-Object System.Drawing.Size([Math]::Min(1400, 120 + 420 * $imagePaths.Count), 700)
    $imgForm.StartPosition = "CenterParent"
    $imgForm.TopMost = $true

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panel.AutoScroll = $true
    $imgForm.Controls.Add($panel)

    foreach ($imagePath in $imagePaths) {
        $box = New-Object System.Windows.Forms.Panel
        $box.Size = New-Object System.Drawing.Size(400, 620)

        $pictureBox = New-Object System.Windows.Forms.PictureBox
        $pictureBox.Location = New-Object System.Drawing.Point(0, 0)
        $pictureBox.Size = New-Object System.Drawing.Size(400, 585)
        $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

        # Load a copy so the file is not locked while the popup is open
        $stream = [System.IO.File]::OpenRead($imagePath)
        try {
            $img = [System.Drawing.Image]::FromStream($stream)
            $pictureBox.Image = New-Object System.Drawing.Bitmap($img)
            $img.Dispose()
        } finally {
            $stream.Close()
        }
        $box.Controls.Add($pictureBox)

        $lblName = New-Object System.Windows.Forms.Label
        $lblName.Text = [System.IO.Path]::GetFileName($imagePath)
        $lblName.Location = New-Object System.Drawing.Point(0, 590)
        $lblName.Size = New-Object System.Drawing.Size(400, 25)
        $lblName.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $box.Controls.Add($lblName)

        $panel.Controls.Add($box)
    }

    [void]$imgForm.ShowDialog()
}

function Get-TransactionJson {
    param(
        [string]$transactionId,
        [string]$apiName = "Export"
    )

    function Get-DbValue {
        param($reader, [string]$name, $defaultValue = $null)

        try {
            $index = $reader.GetOrdinal($name)
            $value = $reader.GetValue($index)

            if ($value -eq [DBNull]::Value -or $null -eq $value) {
                return $defaultValue
            }

            return $value
        } catch {
            return $defaultValue
        }
    }

    function Get-DbInt {
        param($reader, [string]$name, [int]$defaultValue = 0)

        $value = Get-DbValue -reader $reader -name $name -defaultValue $defaultValue

        try {
            if ($null -eq $value -or $value -eq '') {
                return $defaultValue
            }

            return [int]$value
        } catch {
            return $defaultValue
        }
    }

    function Get-DbDecimal {
        param($reader, [string]$name, [decimal]$defaultValue = 0)

        $value = Get-DbValue -reader $reader -name $name -defaultValue $defaultValue

        try {
            if ($null -eq $value -or $value -eq '') {
                return $defaultValue
            }

            return [decimal]$value
        } catch {
            return $defaultValue
        }
    }

    function Get-DbStringOrEmpty {
        param($reader, [string]$name)

        $value = Get-DbValue -reader $reader -name $name -defaultValue ""

        if ($null -eq $value -or $value -eq [DBNull]::Value) {
            return ""
        }

        return [string]$value
    }

    function Get-DbStringOrString {
        param($reader, [string]$name)

        $value = Get-DbValue -reader $reader -name $name -defaultValue "string"

        if ($null -eq $value -or $value -eq [DBNull]::Value) {
            return "string"
        }

        $text = [string]$value

        if ([string]::IsNullOrWhiteSpace($text)) {
            return "string"
        }

        return $text
    }

    function Get-DbBool {
        param($reader, [string]$name, [bool]$defaultValue = $false)

        $value = Get-DbValue -reader $reader -name $name -defaultValue $defaultValue

        if ($null -eq $value -or $value -eq [DBNull]::Value -or $value -eq '') {
            return $defaultValue
        }

        try {
            if ($value -is [bool]) {
                return $value
            }

            if ($value -is [string]) {
                $v = $value.ToLower().Trim()
                return ($v -eq 'true' -or $v -eq '1')
            }

            return ([int]$value -eq 1)
        } catch {
            return $defaultValue
        }
    }

    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT * FROM Transactions WHERE Id = @id LIMIT 1"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null

    $reader = $cmd.ExecuteReader()

    if (-not $reader.Read()) {
        $reader.Close()
        return $null
    }

    $themeId = Get-DbInt -reader $reader -name "ThemeId" -defaultValue 0
    $layoutId = Get-DbInt -reader $reader -name "LayoutId" -defaultValue 0

    # themeDetailId = LayoutThemes.Id theo ThemeId + LayoutId
    $themeDetailId = 0
    try {
        $themeDetailCmd = $global:SQLiteConnection.CreateCommand()
        $themeDetailCmd.CommandText = @"
SELECT Id
FROM LayoutThemes
WHERE ThemeId = @themeId
  AND LayoutId = @layoutId
LIMIT 1
"@

        $themeDetailCmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@themeId", $themeId))) | Out-Null
        $themeDetailCmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@layoutId", $layoutId))) | Out-Null

        $themeDetailValue = $themeDetailCmd.ExecuteScalar()

        if ($null -ne $themeDetailValue -and $themeDetailValue -ne [DBNull]::Value) {
            $themeDetailId = [int]$themeDetailValue
        }
    } catch {
        $themeDetailId = 0
    }

    # listImages comes from Transactions.Images
    $listImages = @()
    $imagesRaw = Get-DbStringOrEmpty -reader $reader -name "Images"

    if (-not [string]::IsNullOrWhiteSpace($imagesRaw)) {
        try {
            $parsedImages = $imagesRaw | ConvertFrom-Json

            if ($null -ne $parsedImages) {
                foreach ($img in @($parsedImages)) {
                    # flip null = no flip; BE FlipType: 0 = Horizontal (mirror), 1 = Vertical
                    $flipValue = $null
                    if ($img.PSObject.Properties.Name -contains "flip") {
                        if ($null -ne $img.flip -and $img.flip -ne '') {
                            $flipValue = [int]$img.flip
                        }
                    }

                    $listImages += [ordered]@{
                        fileName = if ($null -ne $img.fileName -and -not [string]::IsNullOrWhiteSpace([string]$img.fileName)) { [string]$img.fileName } else { "string" }
                        rotate = if ($null -ne $img.rotate -and $img.rotate -ne '') { [decimal]$img.rotate } else { 0.0 }
                        flip = $flipValue
                        isDigitalBackground = if ($null -ne $img.isDigitalBackground) { [bool]$img.isDigitalBackground } else { $false }
                        digitalBackgroundId = if ($null -ne $img.digitalBackgroundId -and $img.digitalBackgroundId -ne '') { [int]$img.digitalBackgroundId } else { 0 }
                    }
                }
            }
        } catch {
            $listImages = @()
        }
    }

    # listSticker:
    # - ProcessImage: always [] to avoid StickerMapper null when stickerId = 0
    # - ProcessVideo / Export: use real stickers only; do not add stickerId = 0
    $listSticker = @()

    if ($apiName -ne "ProcessImage") {
        try {
            $stickerCmd = $global:SQLiteConnection.CreateCommand()
            $stickerCmd.CommandText = @"
SELECT StickerId, Width, Height, AxisX, AxisY
FROM TransactionStickers
WHERE TransactionId = @id
"@
            $stickerCmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null

            $stickerReader = $stickerCmd.ExecuteReader()

            while ($stickerReader.Read()) {
                $stickerId = Get-DbInt -reader $stickerReader -name "StickerId" -defaultValue 0

                if ($stickerId -gt 0) {
                    $listSticker += [ordered]@{
                        rotate = 0
                        stickerId = $stickerId
                        width = Get-DbInt -reader $stickerReader -name "Width" -defaultValue 0
                        height = Get-DbInt -reader $stickerReader -name "Height" -defaultValue 0
                        axisX = Get-DbInt -reader $stickerReader -name "AxisX" -defaultValue 0
                        axisY = Get-DbInt -reader $stickerReader -name "AxisY" -defaultValue 0
                    }
                }
            }

            $stickerReader.Close()
        } catch {
            $listSticker = @()
        }
    }

    $result = [ordered]@{
        code = Get-DbStringOrString -reader $reader -name "Code"
        PaymentMethod = Get-DbInt -reader $reader -name "PaymentMethod" -defaultValue 0
        frameId = Get-DbInt -reader $reader -name "FrameId" -defaultValue 0
        layoutId = $layoutId
        themeId = $themeId
        backgroundId = Get-DbInt -reader $reader -name "BackgroundId" -defaultValue 0
        filterId = Get-DbInt -reader $reader -name "FilterId" -defaultValue 0
        transactionId = Get-DbStringOrEmpty -reader $reader -name "Id"
        themeDetailId = $themeDetailId
        captureMode = Get-DbInt -reader $reader -name "CaptureMode" -defaultValue 0

        # SQLite may return INTEGER columns as Int64; normalize numerically.
        isFile = ((Get-DbInt -reader $reader -name "IsFile" -defaultValue 0) -ne 0)

        # Required default: true
        isVideo = $true

        # Use an empty string when missing.
        voucherCode = Get-DbStringOrEmpty -reader $reader -name "VoucherCode"

        purchaseDuration = Get-DbInt -reader $reader -name "PurchaseDuration" -defaultValue 0
        captureDuration = Get-DbInt -reader $reader -name "CaptureDuration" -defaultValue 0
        editDuration = Get-DbInt -reader $reader -name "EditDuration" -defaultValue 0
        printNumber = Get-DbInt -reader $reader -name "PrintNumber" -defaultValue 0
        layoutAmount = Get-DbDecimal -reader $reader -name "LayoutAmount" -defaultValue 0
        printAmount = Get-DbDecimal -reader $reader -name "PrintAmount" -defaultValue 0
        discount = Get-DbDecimal -reader $reader -name "Discount" -defaultValue 0
        deposit = Get-DbDecimal -reader $reader -name "Deposit" -defaultValue 0

        # Use "string" when missing.
        pinCode = Get-DbStringOrString -reader $reader -name "Pincode"

        refundAmount = Get-DbDecimal -reader $reader -name "RefundAmount" -defaultValue 0

        # Use "string" when missing.
        refundReason = Get-DbStringOrString -reader $reader -name "RefundReason"

        # IsConfirmPolicy = 1 means true.
        isConfirmPolicy = Get-DbBool -reader $reader -name "IsConfirmPolicy" -defaultValue $false

        # Required default: true.
        isSelfBooth = $true

        listSticker = $listSticker
        listImages = $listImages

        # Required defaults.
        isAiFlow = $true
        promptTemplateId = 0
        pinCodeDownload = "string"
    }

    $reader.Close()

    return ($result | ConvertTo-Json -Depth 20)
}

# =========================
# Selfbooth (photo package flow)
# =========================
function Test-SQLiteTable {
    param(
        [string]$tableName
    )

    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = @name"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@name", $tableName))) | Out-Null
    return ([int64]$cmd.ExecuteScalar() -gt 0)
}

function Test-SelfBoothTransaction {
    param(
        [string]$transactionId
    )

    if (-not $global:HasPackageTable) {
        return $false
    }

    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM TransactionPhotoPackageLayoutThemes WHERE TransactionId = @id"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null
    return ([int64]$cmd.ExecuteScalar() -gt 0)
}

function Get-SelfBoothFrames {
    param(
        [string]$transactionId
    )

    # 1 row per layout (BE groups 2 strips of the same 2x6 layout into 1 row, NumberOfPrint = total)
    $rows = @()
    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = @"
SELECT IFNULL(p.PhotoPackageId, 0) AS PhotoPackageId, IFNULL(p.LayoutId, 0) AS LayoutId,
       IFNULL(p.ThemeId, 0) AS ThemeId, IFNULL(p.NumberOfPrint, 0) AS NumberOfPrint,
       IFNULL(l.FrameId, 0) AS FrameId, IFNULL(l.Code, '') AS Code,
       IFNULL(l.Width, 0) AS Width, IFNULL(l.Height, 0) AS Height,
       (SELECT lt.Id FROM LayoutThemes lt WHERE lt.LayoutId = p.LayoutId AND lt.ThemeId = p.ThemeId LIMIT 1) AS ThemeDetailId,
       (SELECT COUNT(*) FROM LayoutPictures lp WHERE lp.LayoutId = p.LayoutId) AS PictureCount
FROM TransactionPhotoPackageLayoutThemes p
LEFT JOIN Layouts l ON l.Id = p.LayoutId
WHERE p.TransactionId = @id
ORDER BY p.Id
"@
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $width = [int]$reader["Width"]
        $height = [int]$reader["Height"]
        $rows += [pscustomobject]@{
            PhotoPackageId = [int]$reader["PhotoPackageId"]
            LayoutId = [int]$reader["LayoutId"]
            ThemeId = [int]$reader["ThemeId"]
            NumberOfPrint = [int]$reader["NumberOfPrint"]
            FrameId = [int]$reader["FrameId"]
            Code = [string]$reader["Code"]
            Width = $width
            Height = $height
            ThemeDetailId = if ($reader["ThemeDetailId"] -ne [DBNull]::Value) { [int]$reader["ThemeDetailId"] } else { 0 }
            PictureCount = [int]$reader["PictureCount"]
            Is2x6 = ([int]$reader["FrameId"] -eq 1)
            Landscape = ($width -gt $height)
            Files = New-Object System.Collections.ArrayList
        }
    }
    $reader.Close()

    if ($rows.Count -eq 0) {
        return @()
    }

    # Output files already generated by BE: {id}_QR.png = frame 1, {id}_n_QR.png = frame n
    $files = @()
    $folder = "D:\Work\PhotoBooth\Image\$transactionId"
    if (Test-Path $folder) {
        $pattern = "^" + [regex]::Escape($transactionId) + "(?:_(\d+))?_QR\.png$"
        foreach ($file in Get-ChildItem -Path $folder -Filter "*_QR.png" -File) {
            $match = [regex]::Match($file.Name, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (-not $match.Success) {
                continue
            }

            $outputIndex = if ($match.Groups[1].Success) { [int]$match.Groups[1].Value } else { 1 }
            $stream = [System.IO.File]::OpenRead($file.FullName)
            try {
                $img = [System.Drawing.Image]::FromStream($stream, $false, $false)
                $w = $img.Width
                $h = $img.Height
                $img.Dispose()
            } finally {
                $stream.Close()
            }

            $files += [pscustomobject]@{
                OutputIndex = $outputIndex
                Name = $file.Name
                Width = $w
                Height = $h
                Is2x6 = (([Math]::Min($w, $h) / [double][Math]::Max($w, $h)) -lt 0.45)
                Landscape = ($w -gt $h)
            }
        }
    }

    # Match each file to the layout with the same frame type / orientation and the closest size
    $frames = @()
    foreach ($file in @($files | Sort-Object OutputIndex)) {
        $candidates = @($rows | Where-Object { $_.Is2x6 -eq $file.Is2x6 -and ($_.Width -eq 0 -or $_.Landscape -eq $file.Landscape) })
        if ($candidates.Count -eq 0) {
            $candidates = @($rows | Where-Object { $_.Is2x6 -eq $file.Is2x6 })
        }
        if ($candidates.Count -eq 0) {
            continue
        }

        $row = $candidates | Sort-Object { [Math]::Abs($_.Width - $file.Width) + [Math]::Abs($_.Height - $file.Height) } | Select-Object -First 1
        $frame = [pscustomobject]@{
            Index = $file.OutputIndex - 1
            FileName = $file.Name
            Row = $row
            NumberOfPrint = 0
        }
        [void]$row.Files.Add($frame)
        $frames += $frame
    }

    # Layout without generated file: 2x6 = 2 strips, others = 1 frame
    $nextIndex = if ($frames.Count -gt 0) { ($frames | Measure-Object -Property Index -Maximum).Maximum + 1 } else { 0 }
    foreach ($row in $rows) {
        if ($row.Files.Count -gt 0) {
            continue
        }

        $count = if ($row.Is2x6 -and $row.NumberOfPrint -ge 2) { 2 } else { 1 }
        for ($i = 0; $i -lt $count; $i++) {
            $frame = [pscustomobject]@{
                Index = $nextIndex
                FileName = ""
                Row = $row
                NumberOfPrint = 0
            }
            [void]$row.Files.Add($frame)
            $frames += $frame
            $nextIndex++
        }
    }

    # Split NumberOfPrint of each layout over its frames (each 2x6 strip = 1 print)
    foreach ($row in $rows) {
        $count = $row.Files.Count
        if ($count -eq 0) {
            continue
        }

        $each = [int][Math]::Floor($row.NumberOfPrint / $count)
        $remain = $row.NumberOfPrint % $count
        for ($i = 0; $i -lt $count; $i++) {
            $row.Files[$i].NumberOfPrint = $each + $(if ($i -lt $remain) { 1 } else { 0 })
        }
    }

    return @($frames | Sort-Object Index)
}

function Get-SelfBoothFramesText {
    param(
        [string]$transactionId,
        $frames
    )

    $lines = @("Frames (from TransactionPhotoPackageLayoutThemes + generated files):")
    foreach ($frame in $frames) {
        $type = if ($frame.Row.Is2x6) { "2x6" } else { "4x6" }
        $file = if ($frame.FileName) { $frame.FileName } else { "(not generated yet)" }
        $lines += "#$($frame.Index + 1) index=$($frame.Index) | $type | layout $($frame.Row.LayoutId) $($frame.Row.Code) | $($frame.Row.PictureCount) photos | theme $($frame.Row.ThemeId) | print $($frame.NumberOfPrint) | $file"
    }

    $lines += ""
    $lines += "Raw photos in transaction folder:"
    $folder = "D:\Work\PhotoBooth\Image\$transactionId"
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -File |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg)$' -and -not $_.Name.StartsWith($transactionId) } |
            Sort-Object Name |
            ForEach-Object { $lines += $_.Name }
    }

    return ($lines -join "`r`n")
}

function Get-SelfBoothProcessJson {
    param(
        [string]$transactionId,
        [string]$apiName,
        $frames
    )

    $baseJson = Get-TransactionJson -transactionId $transactionId -apiName $apiName
    if (-not $baseJson) {
        return $null
    }

    $body = $baseJson | ConvertFrom-Json
    $listImages = @($body.listImages)
    $listSticker = @($body.listSticker)

    # DB only keeps listImages of frame 1 (Transactions.Images).
    # Other frames: fill up to the number of photos of the layout with raw photos not used yet,
    # then repeat the photos of frame 1. Check / edit listImages of each frame before sending.
    $folder = "D:\Work\PhotoBooth\Image\$transactionId"
    $filterSuffix = ""
    if ($listImages.Count -gt 0 -and [string]$listImages[0].fileName -match '^[^_\\/]+(_[^\\/]*)\.[^\\/.]+$') {
        $filterSuffix = $Matches[1]
    }

    $usedPhotos = New-Object System.Collections.Generic.HashSet[string]
    foreach ($image in $listImages) {
        [void]$usedPhotos.Add((([string]$image.fileName) -replace '_[^\\/]*(?=\.[^\\/.]+$)', ''))
    }

    $rawPhotos = @()
    if (Test-Path $folder) {
        $rawPhotos = @(Get-ChildItem -Path $folder -File |
            Where-Object { $_.Name -match '^\d+\.(png|jpg|jpeg)$' } |
            Sort-Object Name |
            ForEach-Object { $_.Name })
    }

    $details = @()
    $first = $true
    foreach ($frame in $frames) {
        if ($frame.NumberOfPrint -le 0) {
            continue
        }

        $need = $frame.Row.PictureCount
        if ($need -le 0) {
            $need = $listImages.Count
        }

        $frameImages = @()
        if ($first) {
            $frameImages = @($listImages)
        } else {
            foreach ($photo in $rawPhotos) {
                if ($frameImages.Count -ge $need) {
                    break
                }
                if ($usedPhotos.Contains($photo)) {
                    continue
                }

                [void]$usedPhotos.Add($photo)
                $fileName = $photo
                if ($filterSuffix) {
                    $filtered = [System.IO.Path]::GetFileNameWithoutExtension($photo) + $filterSuffix + [System.IO.Path]::GetExtension($photo)
                    if (Test-Path (Join-Path $folder $filtered)) {
                        $fileName = $filtered
                    }
                }

                $frameImages += [ordered]@{
                    fileName = $fileName
                    rotate = 0.0
                    flip = $null
                    isDigitalBackground = $false
                    digitalBackgroundId = 0
                }
            }
        }

        # Not enough photos: repeat the photos of frame 1
        $i = 0
        while ($frameImages.Count -lt $need -and $listImages.Count -gt 0) {
            $frameImages += $listImages[$i % $listImages.Count]
            $i++
        }

        # Stickers are only stored for frame 1; ProcessImage always sends [] (same as the old flow)
        $detailStickers = @()
        if ($apiName -eq "ProcessVideo" -and $first) {
            $detailStickers = $listSticker
        }

        $details += [ordered]@{
            PhotoPackageId = $frame.Row.PhotoPackageId
            frameId = $frame.Row.FrameId
            LayoutId = $frame.Row.LayoutId
            ThemeId = $frame.Row.ThemeId
            NumberOfPrint = $frame.NumberOfPrint
            themeDetailId = $frame.Row.ThemeDetailId
            filterId = $body.filterId
            listImages = $frameImages
            listSticker = $detailStickers
        }
        $first = $false
    }

    if ($details.Count -gt 0) {
        $body.frameId = $details[0].frameId
        $body.layoutId = $details[0].LayoutId
        $body.themeId = $details[0].ThemeId
        $body.themeDetailId = $details[0].themeDetailId
    }

    # BE sums NumberOfPrint of photoPackageDetails when printNumber = 0
    $body.printNumber = 0
    $body.isSelfBooth = $true
    $body | Add-Member -NotePropertyName photoPackageDetails -NotePropertyValue $details -Force

    return ($body | ConvertTo-Json -Depth 20)
}

function Get-SelfBoothPrintJson {
    param(
        [string]$transactionId,
        $frames
    )

    $isPrintingMatte = $false
    try {
        $cmd = $global:SQLiteConnection.CreateCommand()
        $cmd.CommandText = "SELECT IFNULL(IsPrintingMatte, 0) FROM Transactions WHERE Id = @id LIMIT 1"
        $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null
        $value = $cmd.ExecuteScalar()
        $isPrintingMatte = ($null -ne $value -and $value -ne [DBNull]::Value -and [string]$value -match '^(1|true)$')
    } catch {
        $isPrintingMatte = $false
    }

    # BE prints 2 strips of the same 2x6 layout on 1 sheet; numberOfPrint of the first strip = number of sheets
    $items = @()
    foreach ($frame in $frames) {
        if ($frame.NumberOfPrint -le 0) {
            continue
        }

        $items += [ordered]@{
            photoPackageId = $frame.Row.PhotoPackageId
            layoutId = $frame.Row.LayoutId
            themeId = $frame.Row.ThemeId
            numberOfPrint = $frame.NumberOfPrint
            index = $frame.Index
            isPrintingMatte = $isPrintingMatte
        }
    }

    $body = [ordered]@{
        transactionId = $transactionId
        layoutId = if ($items.Count -gt 0) { $items[0].layoutId } else { 0 }
        numberOfImage = 1
        isSelfBooth = $true
        photoPackageLayoutThemes = $items
    }

    return ($body | ConvertTo-Json -Depth 20)
}

function Send-ToSelfBoothPrintAPI {
    param(
        [string]$requestJson,
        [string]$apiUrl = "http://localhost:8088/api/print/printimage"
    )

    try {
        $null = $requestJson | ConvertFrom-Json -ErrorAction Stop
        Write-ApiLog "SelfBoothPrint REQUEST_BODY=$requestJson"

        $waitForm = Show-WaitForm -text "Sending to printer...`r`nPlease wait."
        try {
            $response = Invoke-WebRequest `
                -Uri $apiUrl `
                -Method POST `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($requestJson)) `
                -ContentType "application/json" `
                -UseBasicParsing
        } finally {
            Close-WaitForm -waitForm $waitForm
        }

        Write-ApiLog "SelfBoothPrint RESPONSE_CODE=$([int]$response.StatusCode)"
        $txtJson.Text = "===== SelfBoothPrint REQUEST BODY =====`r`n$requestJson`r`n`r`n===== RESPONSE =====`r`n$($response.Content)"
        [System.Windows.Forms.MessageBox]::Show("Print successfully!", "Success")
    } catch {
        $responseBody = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $responseBody = $_.ErrorDetails.Message
        }

        Write-ApiLog "SelfBoothPrint ERROR=$responseBody"
        $txtJson.Text = "===== SelfBoothPrint REQUEST BODY =====`r`n$requestJson`r`n`r`n===== ERROR =====`r`n$responseBody"
        [System.Windows.Forms.MessageBox]::Show("Send error: $responseBody", "Error")
    }
}

function Get-LayoutPictureCount {
    param(
        [int]$layoutId
    )

    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM LayoutPictures WHERE LayoutId = @layoutId"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@layoutId", $layoutId))) | Out-Null
    return [int]$cmd.ExecuteScalar()
}

function Get-LayoutPreviewInfo {
    param(
        [int]$layoutId,
        [int]$themeDetailId
    )

    $info = @{
        Width = 0
        Height = 0
        Pictures = @()
        ThemePath = ""
    }

    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT IFNULL(Width, 0), IFNULL(Height, 0) FROM Layouts WHERE Id = @layoutId LIMIT 1"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@layoutId", $layoutId))) | Out-Null
    $reader = $cmd.ExecuteReader()
    if ($reader.Read()) {
        $info.Width = [int]$reader.GetValue(0)
        $info.Height = [int]$reader.GetValue(1)
    }
    $reader.Close()

    # Same order as BE (LayoutPictures ORDER BY OrderNo)
    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT IFNULL(AxisX, 0), IFNULL(AxisY, 0), IFNULL(Width, 0), IFNULL(Height, 0) FROM LayoutPictures WHERE LayoutId = @layoutId ORDER BY OrderNo, Id"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@layoutId", $layoutId))) | Out-Null
    $reader = $cmd.ExecuteReader()
    $pictures = @()
    while ($reader.Read()) {
        $pictures += ,@([int]$reader.GetValue(0), [int]$reader.GetValue(1), [int]$reader.GetValue(2), [int]$reader.GetValue(3))
    }
    $reader.Close()
    $info.Pictures = $pictures

    # Theme frame = FolderPhotoBooth + LayoutThemes.ImageUrl
    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT ImageUrl FROM LayoutThemes WHERE Id = @id LIMIT 1"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $themeDetailId))) | Out-Null
    $imageUrl = $cmd.ExecuteScalar()
    if ($null -ne $imageUrl -and $imageUrl -ne [DBNull]::Value -and -not [string]::IsNullOrWhiteSpace([string]$imageUrl)) {
        $info.ThemePath = "D:\Work\PhotoBooth" + ([string]$imageUrl -replace '/', '\')
    }

    return $info
}

function Get-PhotoBaseName {
    param(
        [string]$fileName
    )

    # 134393938321887466_f35.png -> 134393938321887466.png
    return ($fileName -replace '_[^\\/]*(?=\.[^\\/.]+$)', '')
}

function Get-RotatedBitmap {
    param(
        $source,
        [int]$rotate,
        $flip
    )

    # Same order as BE GetAndRotateImage: rotate, then flip (0 = Horizontal, 1 = Vertical, null = none)
    $bitmap = New-Object System.Drawing.Bitmap($source)
    switch ((($rotate % 360) + 360) % 360) {
        90 { $bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
        180 { $bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
        270 { $bitmap.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
    }
    if ($null -ne $flip -and "$flip" -ne "") {
        if ([int]$flip -eq 1) {
            $bitmap.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipY)
        } else {
            $bitmap.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
        }
    }
    return $bitmap
}

function Get-ScaledBitmapFromFile {
    param(
        [string]$path,
        [int]$maxSize
    )

    if (-not (Test-Path $path)) {
        return $null
    }

    # Read through a stream so the file is not locked
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $img = [System.Drawing.Image]::FromStream($stream, $false, $false)
        $ratio = [Math]::Min(1.0, $maxSize / [double][Math]::Max($img.Width, $img.Height))
        $bitmap = New-Object System.Drawing.Bitmap($img, [int][Math]::Max(1, $img.Width * $ratio), [int][Math]::Max(1, $img.Height * $ratio))
        $img.Dispose()
        return $bitmap
    } catch {
        return $null
    } finally {
        $stream.Close()
    }
}

function Set-RoundedRegion {
    param(
        $control,
        [int]$radius
    )

    # Rounded corners for WinForms controls (no CSS in WinForms)
    $diameter = [Math]::Min($radius * 2, [Math]::Min($control.Width, $control.Height))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $path.AddArc($control.Width - $diameter, 0, $diameter, $diameter, 270, 90)
    $path.AddArc($control.Width - $diameter, $control.Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc(0, $control.Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    $control.Region = New-Object System.Drawing.Region($path)
    $path.Dispose()
}

function New-FlatButton {
    param(
        [string]$text,
        [int]$x,
        [int]$y,
        [int]$width,
        [int]$height,
        $backColor,
        $foreColor,
        [float]$fontSize = 10,
        [int]$radius = 12
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Location = New-Object System.Drawing.Point($x, $y)
    $button.Size = New-Object System.Drawing.Size($width, $height)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $backColor
    $button.ForeColor = $foreColor
    $button.Font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-RoundedRegion -control $button -radius $radius
    return $button
}

function Show-PhotoPickerPopup {
    param(
        [string]$transactionId,
        [string]$json
    )

    $body = $json | ConvertFrom-Json
    $details = @($body.photoPackageDetails)
    if ($details.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("JSON không có photoPackageDetails!", "Lỗi")
        return $null
    }

    $folder = "D:\Work\PhotoBooth\Image\$transactionId"
    if (-not (Test-Path $folder)) {
        [System.Windows.Forms.MessageBox]::Show("Không thấy thư mục:`n$folder", "Lỗi")
        return $null
    }

    # Photos of the transaction, same naming as BE: {n}.png original, {n}_f1.png smooth, {n}_f{filterId}.png filter
    $allFiles = @(Get-ChildItem -Path $folder -File | Sort-Object Name | ForEach-Object { $_.Name })
    $originalFiles = @($allFiles | Where-Object { $_ -match '^\d+\.(png|jpg|jpeg)$' })
    $smoothFiles = @($allFiles | Where-Object { $_ -match '^\d+_f1\.(png|jpg|jpeg)$' })
    $filterFiles = @($allFiles | Where-Object { $_ -match '^\d+_f[^\\/]+\.(png|jpg|jpeg)$' -and $_ -notmatch '^\d+_f1\.(png|jpg|jpeg)$' })

    # Photo info already in the JSON (by original photo, any version)
    $imageInfo = @{}
    foreach ($image in @($body.listImages) + @($details | ForEach-Object { @($_.listImages) })) {
        if ($null -ne $image -and $null -ne $image.fileName) {
            $key = Get-PhotoBaseName -fileName ([string]$image.fileName)
            if (-not $imageInfo.ContainsKey($key)) {
                $imageInfo[$key] = $image
            }
        }
    }

    $state = @{
        Frames = New-Object System.Collections.ArrayList
        Frame = 0
        Slot = 0
        Result = $null
        Edits = @{}
        Photos = @{}
        Thumbs = New-Object System.Collections.ArrayList
        PreviewScale = 1.0
        Updating = $false
    }

    # Rotate / flip are kept per original photo (like the FE)
    foreach ($key in @($imageInfo.Keys)) {
        $old = $imageInfo[$key]
        $state.Edits[$key] = @{
            Rotate = if ($null -ne $old.rotate) { [int]$old.rotate } else { 0 }
            Flip = if ($null -ne $old.flip -and "$($old.flip)" -ne "") { [int]$old.flip } else { $null }
        }
    }

    $number = 1
    foreach ($detail in $details) {
        $preview = Get-LayoutPreviewInfo -layoutId ([int]$detail.LayoutId) -themeDetailId ([int]$detail.themeDetailId)
        $current = @(@($detail.listImages) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.fileName })
        $need = @($preview.Pictures).Count
        if ($need -le 0) {
            $need = [Math]::Max(1, $current.Count)
        }

        $slots = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $need; $i++) {
            [void]$slots.Add($(if ($i -lt $current.Count) { $current[$i] } else { "" }))
        }

        $type = if ([int]$detail.frameId -eq 1) { "2x6" } else { "4x6" }
        [void]$state.Frames.Add(@{
            Label = "Khung $number - $type - layout $($detail.LayoutId)"
            Slots = $slots
            Preview = $preview
            Theme = $null
        })
        $number++
    }

    # Colors like the FE screen
    $pink = [System.Drawing.Color]::FromArgb(240, 128, 150)
    $darkPink = [System.Drawing.Color]::FromArgb(150, 45, 80)
    $darkBg = [System.Drawing.Color]::FromArgb(36, 29, 35)
    $cardBg = [System.Drawing.Color]::FromArgb(58, 49, 56)
    $pillBg = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $pillActive = [System.Drawing.Color]::FromArgb(15, 15, 15)
    $softText = [System.Drawing.Color]::FromArgb(200, 190, 198)
    $white = [System.Drawing.Color]::White

    $pickerForm = New-Object System.Windows.Forms.Form
    $pickerForm.Text = "Chọn ảnh - $transactionId"
    $pickerForm.Size = New-Object System.Drawing.Size(1400, 930)
    $pickerForm.StartPosition = "CenterParent"
    $pickerForm.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $pickerForm.BackColor = $darkBg
    $pickerForm.ForeColor = $white
    $pickerForm.ShowInTaskbar = $false

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "CHỌN ẢNH"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold)
    $lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblTitle.Location = New-Object System.Drawing.Point(0, 5)
    $lblTitle.Size = New-Object System.Drawing.Size(1385, 55)
    $pickerForm.Controls.Add($lblTitle)

    $cboFrames = New-Object System.Windows.Forms.ComboBox
    $cboFrames.DropDownStyle = "DropDownList"
    $cboFrames.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cboFrames.BackColor = $cardBg
    $cboFrames.ForeColor = $white
    $cboFrames.Location = New-Object System.Drawing.Point(20, 70)
    $cboFrames.Size = New-Object System.Drawing.Size(420, 32)
    $cboFrames.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $pickerForm.Controls.Add($cboFrames)

    $previewBox = New-Object System.Windows.Forms.PictureBox
    $previewBox.Location = New-Object System.Drawing.Point(20, 112)
    $previewBox.Size = New-Object System.Drawing.Size(420, 640)
    $previewBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $previewBox.BackColor = $darkBg
    $previewBox.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pickerForm.Controls.Add($previewBox)

    $lblSlotInfo = New-Object System.Windows.Forms.Label
    $lblSlotInfo.Location = New-Object System.Drawing.Point(20, 760)
    $lblSlotInfo.Size = New-Object System.Drawing.Size(420, 25)
    $lblSlotInfo.ForeColor = $softText
    $pickerForm.Controls.Add($lblSlotInfo)

    $btnClearSlot = New-FlatButton -text "Xoá ô" -x 20 -y 795 -width 130 -height 40 -backColor $cardBg -foreColor $white
    $pickerForm.Controls.Add($btnClearSlot)

    $btnClearFrame = New-FlatButton -text "Xoá cả khung" -x 160 -y 795 -width 150 -height 40 -backColor $cardBg -foreColor $white
    $pickerForm.Controls.Add($btnClearFrame)

    # Pill tab bar like the FE: Ảnh filter / Ảnh mịn da / Ảnh gốc
    $tabBar = New-Object System.Windows.Forms.Panel
    $tabBar.Location = New-Object System.Drawing.Point(685, 70)
    $tabBar.Size = New-Object System.Drawing.Size(480, 46)
    $tabBar.BackColor = $pillBg
    Set-RoundedRegion -control $tabBar -radius 22
    $pickerForm.Controls.Add($tabBar)

    $photoArea = New-Object System.Windows.Forms.Panel
    $photoArea.Location = New-Object System.Drawing.Point(465, 130)
    $photoArea.Size = New-Object System.Drawing.Size(910, 620)
    $photoArea.BackColor = $darkBg
    $pickerForm.Controls.Add($photoArea)

    # Same order as the FE
    $tabDefs = @(
        @{ Title = "Ảnh filter ($($filterFiles.Count))"; Files = $filterFiles },
        @{ Title = "Ảnh mịn da ($($smoothFiles.Count))"; Files = $smoothFiles },
        @{ Title = "Ảnh gốc ($($originalFiles.Count))"; Files = $originalFiles }
    )
    $photoPanels = @()
    $tabButtons = @()
    for ($t = 0; $t -lt $tabDefs.Count; $t++) {
        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Dock = [System.Windows.Forms.DockStyle]::Fill
        $flow.AutoScroll = $true
        $flow.BackColor = $darkBg
        $flow.Visible = $false
        $flow.Tag = @{ Files = $tabDefs[$t].Files; Loaded = $false }
        $photoArea.Controls.Add($flow)
        $photoPanels += $flow

        $tabButton = New-FlatButton -text $tabDefs[$t].Title -x (4 + 158 * $t) -y 4 -width 154 -height 38 -backColor $pillBg -foreColor $white -fontSize 10.5 -radius 19
        $tabButton.Tag = $t
        $tabButton.FlatAppearance.MouseOverBackColor = $pillActive
        $tabButton.Add_Click({ Show-PickerTab -index ([int]$this.Tag) })
        $tabBar.Controls.Add($tabButton)
        $tabButtons += $tabButton
    }

    $btnFlipAll = New-FlatButton -text "Lật toàn bộ ảnh" -x 465 -y 760 -width 220 -height 42 -backColor $darkBg -foreColor $white -fontSize 13
    $btnFlipAll.FlatAppearance.MouseOverBackColor = $cardBg
    $pickerForm.Controls.Add($btnFlipAll)

    $lblHelp = New-Object System.Windows.Forms.Label
    $lblHelp.Text = "Bấm ảnh để gắn vào ô đang chọn, bấm lại để bỏ. Bấm vào ô trên khung để chọn ô."
    $lblHelp.Location = New-Object System.Drawing.Point(700, 772)
    $lblHelp.Size = New-Object System.Drawing.Size(675, 25)
    $lblHelp.ForeColor = $softText
    $pickerForm.Controls.Add($lblHelp)

    $btnApply = New-FlatButton -text "Áp dụng" -x 1060 -y 820 -width 150 -height 46 -backColor $white -foreColor ([System.Drawing.Color]::Black) -fontSize 13 -radius 14
    $pickerForm.Controls.Add($btnApply)

    $btnCancelPicker = New-FlatButton -text "Huỷ" -x 1225 -y 820 -width 150 -height 46 -backColor $cardBg -foreColor $white -fontSize 13 -radius 14
    $pickerForm.Controls.Add($btnCancelPicker)

    $toolTip = New-Object System.Windows.Forms.ToolTip

    function Get-PhotoEdit {
        param([string]$fileName)

        $key = Get-PhotoBaseName -fileName $fileName
        if (-not $state.Edits.ContainsKey($key)) {
            $state.Edits[$key] = @{ Rotate = 0; Flip = $null }
        }
        return $state.Edits[$key]
    }

    function Get-PreviewPhoto {
        param([string]$fileName)

        if (-not $state.Photos.ContainsKey($fileName)) {
            $state.Photos[$fileName] = Get-ScaledBitmapFromFile -path (Join-Path $folder $fileName) -maxSize 900
        }
        return $state.Photos[$fileName]
    }

    function Update-ThumbImage {
        param($thumb)

        $edit = Get-PhotoEdit -fileName $thumb.FileName
        $old = $thumb.Picture.Image
        $thumb.Picture.Image = Get-RotatedBitmap -source $thumb.Thumb -rotate $edit.Rotate -flip $edit.Flip
        if ($null -ne $old) {
            $old.Dispose()
        }
    }

    function Add-PickerThumbnails {
        param($panel)

        $panel.SuspendLayout()
        foreach ($fileName in $panel.Tag.Files) {
            # Rounded card like the FE; pink background = photo used in the current frame
            $box = New-Object System.Windows.Forms.Panel
            $box.Size = New-Object System.Drawing.Size(214, 196)
            $box.Margin = New-Object System.Windows.Forms.Padding(8)
            $box.BackColor = $cardBg
            $box.Tag = $fileName
            $box.Cursor = [System.Windows.Forms.Cursors]::Hand
            Set-RoundedRegion -control $box -radius 16

            $pictureBox = New-Object System.Windows.Forms.PictureBox
            $pictureBox.Location = New-Object System.Drawing.Point(7, 7)
            $pictureBox.Size = New-Object System.Drawing.Size(200, 140)
            $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
            $pictureBox.BackColor = $cardBg
            $pictureBox.Tag = $fileName
            $box.Controls.Add($pictureBox)

            # Slot number(s) of the photo in the current frame, round pink badge like the FE
            $badge = New-Object System.Windows.Forms.Label
            $badge.Location = New-Object System.Drawing.Point(6, 6)
            $badge.Size = New-Object System.Drawing.Size(30, 30)
            $badge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $badge.BackColor = $pink
            $badge.ForeColor = $white
            $badge.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
            $badge.Visible = $false
            $badge.Tag = $fileName
            $pictureBox.Controls.Add($badge)

            # Round pink rotate / flip buttons under the photo
            $btnRotate = New-FlatButton -text ([string][char]0x21BB) -x 66 -y 152 -width 36 -height 36 -backColor $pink -foreColor $white -fontSize 14 -radius 18
            $btnRotate.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 14, [System.Drawing.FontStyle]::Bold)
            $btnRotate.Tag = $fileName
            $box.Controls.Add($btnRotate)
            $toolTip.SetToolTip($btnRotate, "Xoay 90 độ")

            $btnFlip = New-FlatButton -text ([string][char]0x21C6) -x 112 -y 152 -width 36 -height 36 -backColor $pink -foreColor $white -fontSize 14 -radius 18
            $btnFlip.Font = New-Object System.Drawing.Font("Segoe UI Symbol", 14, [System.Drawing.FontStyle]::Bold)
            $btnFlip.Tag = $fileName
            $box.Controls.Add($btnFlip)
            $toolTip.SetToolTip($btnFlip, "Lật ảnh")

            $toolTip.SetToolTip($pictureBox, $fileName)

            foreach ($control in @($box, $pictureBox, $badge)) {
                $control.Add_Click({ Select-PickerPhoto -fileName ([string]$this.Tag) })
            }
            $btnRotate.Add_Click({ Set-PickerPhotoEdit -fileName ([string]$this.Tag) -rotate })
            $btnFlip.Add_Click({ Set-PickerPhotoEdit -fileName ([string]$this.Tag) -flip })

            $thumb = @{
                FileName = $fileName
                Box = $box
                Picture = $pictureBox
                Badge = $badge
                Buttons = @($btnRotate, $btnFlip)
                Thumb = Get-ScaledBitmapFromFile -path (Join-Path $folder $fileName) -maxSize 220
            }
            if ($null -ne $thumb.Thumb) {
                Update-ThumbImage -thumb $thumb
            }
            [void]$state.Thumbs.Add($thumb)
            $panel.Controls.Add($box)
        }
        $panel.ResumeLayout()
    }

    function Update-PickerPreview {
        $frame = $state.Frames[$state.Frame]
        $info = $frame.Preview
        $old = $previewBox.Image
        $previewBox.Image = $null
        if ($null -ne $old) {
            $old.Dispose()
        }

        if ($info.Width -le 0 -or $info.Height -le 0) {
            return
        }

        $scale = [Math]::Min(1.0, 900.0 / [Math]::Max($info.Width, $info.Height))
        $state.PreviewScale = $scale
        $canvasWidth = [int]($info.Width * $scale)
        $canvasHeight = [int]($info.Height * $scale)
        $canvas = New-Object System.Drawing.Bitmap($canvasWidth, $canvasHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $pictures = @($info.Pictures)
        for ($i = 0; $i -lt $pictures.Count; $i++) {
            $p = $pictures[$i]
            $rect = New-Object System.Drawing.RectangleF(($p[0] * $scale), ($p[1] * $scale), ($p[2] * $scale), ($p[3] * $scale))
            $fileName = if ($i -lt $frame.Slots.Count) { $frame.Slots[$i] } else { "" }
            $source = if ($fileName) { Get-PreviewPhoto -fileName $fileName } else { $null }

            if ($null -ne $source) {
                $edit = Get-PhotoEdit -fileName $fileName
                $photo = Get-RotatedBitmap -source $source -rotate $edit.Rotate -flip $edit.Flip
                # Fill the slot and crop the center (preview only, BE crops by layout ratio)
                $dstRatio = $rect.Width / $rect.Height
                $srcRatio = $photo.Width / [double]$photo.Height
                if ($srcRatio -gt $dstRatio) {
                    $srcHeight = $photo.Height
                    $srcWidth = $srcHeight * $dstRatio
                } else {
                    $srcWidth = $photo.Width
                    $srcHeight = $srcWidth / $dstRatio
                }
                $srcRect = New-Object System.Drawing.RectangleF((($photo.Width - $srcWidth) / 2), (($photo.Height - $srcHeight) / 2), $srcWidth, $srcHeight)
                $graphics.DrawImage($photo, $rect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
                $photo.Dispose()
            } else {
                $graphics.FillRectangle([System.Drawing.Brushes]::Gainsboro, $rect)
            }
        }

        # Theme frame on top
        if ($null -eq $frame.Theme -and $info.ThemePath) {
            $themeSource = Get-ScaledBitmapFromFile -path $info.ThemePath -maxSize 1200
            if ($null -ne $themeSource) {
                $frame.Theme = New-Object System.Drawing.Bitmap($themeSource, $canvasWidth, $canvasHeight)
                $themeSource.Dispose()
            }
        }
        if ($null -ne $frame.Theme) {
            $graphics.DrawImage($frame.Theme, 0, 0, $canvasWidth, $canvasHeight)
        }

        # Slot numbers and selected slot
        $badgeSize = [Math]::Max(22, [int]($canvasWidth / 14))
        $badgeFont = New-Object System.Drawing.Font("Segoe UI", [float]($badgeSize * 0.45), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $badgeBrush = New-Object System.Drawing.SolidBrush($pink)
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        for ($i = 0; $i -lt $pictures.Count; $i++) {
            $p = $pictures[$i]
            $x = [float]($p[0] * $scale + 8)
            $y = [float]($p[1] * $scale + 8)
            $graphics.FillEllipse($badgeBrush, $x, $y, [float]$badgeSize, [float]$badgeSize)
            $graphics.DrawString([string]($i + 1), $badgeFont, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF($x, $y, $badgeSize, $badgeSize)), $format)

            if ($i -eq $state.Slot) {
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, [float][Math]::Max(3, $canvasWidth / 120))
                $graphics.DrawRectangle($pen, [float]($p[0] * $scale), [float]($p[1] * $scale), [float]($p[2] * $scale), [float]($p[3] * $scale))
                $pen.Dispose()
            }
        }
        $format.Dispose()
        $badgeFont.Dispose()
        $badgeBrush.Dispose()
        $graphics.Dispose()

        $previewBox.Image = $canvas
    }

    function Update-Picker {
        $state.Updating = $true
        for ($f = 0; $f -lt $state.Frames.Count; $f++) {
            $frame = $state.Frames[$f]
            $filled = @($frame.Slots | Where-Object { $_ }).Count
            $text = "$($frame.Label) ($filled/$($frame.Slots.Count) ảnh)"
            if ($cboFrames.Items.Count -le $f) {
                [void]$cboFrames.Items.Add($text)
            } elseif ([string]$cboFrames.Items[$f] -ne $text) {
                $cboFrames.Items[$f] = $text
            }
        }
        if ($cboFrames.SelectedIndex -ne $state.Frame) {
            $cboFrames.SelectedIndex = $state.Frame
        }
        $state.Updating = $false

        $frame = $state.Frames[$state.Frame]
        $current = if ($frame.Slots[$state.Slot]) { $frame.Slots[$state.Slot] } else { "(trống)" }
        $lblSlotInfo.Text = "Ô đang chọn: $($state.Slot + 1) / $($frame.Slots.Count) - $current"

        # Slot numbers on the photos of the current frame
        foreach ($thumb in $state.Thumbs) {
            $numbers = @()
            for ($i = 0; $i -lt $frame.Slots.Count; $i++) {
                if ($frame.Slots[$i] -eq $thumb.FileName) {
                    $numbers += ($i + 1)
                }
            }
            $text = $numbers -join ","
            if ($thumb.Badge.Text -ne $text) {
                $thumb.Badge.Text = $text
                $thumb.Badge.Width = [Math]::Max(30, 14 + 10 * $text.Length)
                Set-RoundedRegion -control $thumb.Badge -radius 15
            }
            $thumb.Badge.Visible = $numbers.Count -gt 0
            # Selected card: pink frame, dark pink buttons so they stay visible
            $selected = $numbers.Count -gt 0
            $thumb.Box.BackColor = if ($selected) { $pink } else { $cardBg }
            foreach ($button in $thumb.Buttons) {
                $button.BackColor = if ($selected) { $darkPink } else { $pink }
            }
        }

        Update-PickerPreview
    }

    function Select-PickerPhoto {
        param([string]$fileName)

        $frame = $state.Frames[$state.Frame]
        if ($frame.Slots.Count -eq 0) {
            return
        }

        $index = $frame.Slots.IndexOf($fileName)
        if ($index -ge 0) {
            # Click again = remove the photo, like the FE
            $frame.Slots[$index] = ""
            $state.Slot = $index
        } else {
            $frame.Slots[$state.Slot] = $fileName
            # Go to the next empty slot
            for ($step = 1; $step -le $frame.Slots.Count; $step++) {
                $next = ($state.Slot + $step) % $frame.Slots.Count
                if (-not $frame.Slots[$next]) {
                    $state.Slot = $next
                    break
                }
            }
        }

        Update-Picker
    }

    function Set-PickerPhotoEdit {
        param(
            [string]$fileName,
            [switch]$rotate,
            [switch]$flip
        )

        $edit = Get-PhotoEdit -fileName $fileName
        if ($rotate) {
            $edit.Rotate = ($edit.Rotate + 90) % 360
        }
        if ($flip) {
            $edit.Flip = if ($null -eq $edit.Flip) { 0 } else { $null }
        }

        # Every version (original / filter / smooth) of the same photo
        $key = Get-PhotoBaseName -fileName $fileName
        foreach ($thumb in $state.Thumbs) {
            if ((Get-PhotoBaseName -fileName $thumb.FileName) -eq $key -and $null -ne $thumb.Thumb) {
                Update-ThumbImage -thumb $thumb
            }
        }
        Update-PickerPreview
    }

    function Show-PickerTab {
        param([int]$index)

        for ($t = 0; $t -lt $photoPanels.Count; $t++) {
            $active = $t -eq $index
            $photoPanels[$t].Visible = $active
            $tabButtons[$t].BackColor = if ($active) { $pillActive } else { $pillBg }
        }

        $flow = $photoPanels[$index]
        if (-not $flow.Tag.Loaded) {
            $pickerForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Add-PickerThumbnails -panel $flow
            $flow.Tag.Loaded = $true
            $pickerForm.Cursor = [System.Windows.Forms.Cursors]::Default
            Update-Picker
        }
    }

    $cboFrames.Add_SelectedIndexChanged({
        if (-not $state.Updating -and $cboFrames.SelectedIndex -ge 0 -and $cboFrames.SelectedIndex -ne $state.Frame) {
            $state.Frame = $cboFrames.SelectedIndex
            $state.Slot = [Math]::Max(0, $state.Frames[$state.Frame].Slots.IndexOf(""))
            Update-Picker
        }
    })

    # Click a slot on the frame preview to select it
    $previewBox.Add_MouseClick({
        param($sender, $e)

        $img = $previewBox.Image
        if ($null -eq $img) {
            return
        }

        $ratio = [Math]::Min($previewBox.ClientSize.Width / [double]$img.Width, $previewBox.ClientSize.Height / [double]$img.Height)
        $offsetX = ($previewBox.ClientSize.Width - $img.Width * $ratio) / 2
        $offsetY = ($previewBox.ClientSize.Height - $img.Height * $ratio) / 2
        $x = ($e.X - $offsetX) / $ratio / $state.PreviewScale
        $y = ($e.Y - $offsetY) / $ratio / $state.PreviewScale

        $pictures = @($state.Frames[$state.Frame].Preview.Pictures)
        for ($i = 0; $i -lt $pictures.Count; $i++) {
            $p = $pictures[$i]
            if ($x -ge $p[0] -and $x -le ($p[0] + $p[2]) -and $y -ge $p[1] -and $y -le ($p[1] + $p[3])) {
                $state.Slot = $i
                Update-Picker
                break
            }
        }
    })

    $btnClearSlot.Add_Click({
        $state.Frames[$state.Frame].Slots[$state.Slot] = ""
        Update-Picker
    })

    $btnClearFrame.Add_Click({
        $frame = $state.Frames[$state.Frame]
        for ($i = 0; $i -lt $frame.Slots.Count; $i++) {
            $frame.Slots[$i] = ""
        }
        $state.Slot = 0
        Update-Picker
    })

    # Flip all photos: if any photo is not flipped, flip all; otherwise un-flip all
    $btnFlipAll.Add_Click({
        $bases = @(@($state.Thumbs | ForEach-Object { Get-PhotoBaseName -fileName $_.FileName }) +
            @($state.Frames | ForEach-Object { @($_.Slots | Where-Object { $_ } | ForEach-Object { Get-PhotoBaseName -fileName $_ }) }) | Select-Object -Unique)
        $anyNotFlipped = @($bases | Where-Object { $null -eq (Get-PhotoEdit -fileName $_).Flip }).Count -gt 0
        foreach ($key in $bases) {
            (Get-PhotoEdit -fileName $key).Flip = if ($anyNotFlipped) { 0 } else { $null }
        }
        foreach ($thumb in $state.Thumbs) {
            if ($null -ne $thumb.Thumb) {
                Update-ThumbImage -thumb $thumb
            }
        }
        Update-PickerPreview
    })

    $btnApply.Add_Click({
        $missing = @($state.Frames | Where-Object { @($_.Slots | Where-Object { -not $_ }).Count -gt 0 } | ForEach-Object { $_.Label })
        if ($missing.Count -gt 0) {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                "Các khung còn ô trống:`n$($missing -join "`n")`n`nÔ trống sẽ để trắng trên ảnh. Vẫn áp dụng?",
                "Còn ô trống",
                [System.Windows.Forms.MessageBoxButtons]::YesNo)
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
        }

        for ($f = 0; $f -lt $details.Count; $f++) {
            $images = @()
            foreach ($fileName in @($state.Frames[$f].Slots | Where-Object { $_ })) {
                $edit = Get-PhotoEdit -fileName $fileName
                $old = $imageInfo[(Get-PhotoBaseName -fileName $fileName)]
                $images += [ordered]@{
                    fileName = $fileName
                    rotate = [decimal]$edit.Rotate
                    flip = $edit.Flip
                    isDigitalBackground = if ($null -ne $old -and $null -ne $old.isDigitalBackground) { [bool]$old.isDigitalBackground } else { $false }
                    digitalBackgroundId = if ($null -ne $old -and $null -ne $old.digitalBackgroundId) { [int]$old.digitalBackgroundId } else { 0 }
                }
            }
            $details[$f].listImages = $images
        }

        # Transaction photos = photos of frame 1 (same as the FE)
        $body.listImages = $details[0].listImages
        $body.photoPackageDetails = $details
        $state.Result = $body | ConvertTo-Json -Depth 20
        $pickerForm.Close()
    })

    $btnCancelPicker.Add_Click({
        $pickerForm.Close()
    })

    $pickerForm.Add_Shown({
        $state.Slot = [Math]::Max(0, $state.Frames[0].Slots.IndexOf(""))
        Update-Picker
        Show-PickerTab -index 0
        $pickerForm.ActiveControl = $previewBox
    })

    [void]$pickerForm.ShowDialog()

    # Release bitmaps
    foreach ($thumb in $state.Thumbs) {
        if ($null -ne $thumb.Thumb) { $thumb.Thumb.Dispose() }
        if ($null -ne $thumb.Picture.Image) { $thumb.Picture.Image.Dispose() }
    }
    foreach ($bitmap in @($state.Photos.Values)) {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
    }
    foreach ($frame in $state.Frames) {
        if ($null -ne $frame.Theme) { $frame.Theme.Dispose() }
    }
    if ($null -ne $previewBox.Image) { $previewBox.Image.Dispose() }
    $pickerForm.Dispose()

    return $state.Result
}

function Show-SelfBoothJsonPopup {
    param(
        [string]$transactionId,
        [string]$mode,
        [string]$json,
        [string]$infoText
    )

    $sbForm = New-Object System.Windows.Forms.Form
    $sbForm.Text = "Selfbooth $mode - $transactionId"
    $sbForm.Size = New-Object System.Drawing.Size(1250, 760)
    $sbForm.StartPosition = "CenterParent"
    $sbForm.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $sbForm.ShowInTaskbar = $false

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Location = New-Object System.Drawing.Point(15, 10)
    $lblHint.Size = New-Object System.Drawing.Size(1200, 45)
    if ($mode -eq "Print") {
        $lblHint.Text = "Check numberOfPrint of each frame. 2 strips of the same 2x6 layout are printed on 1 sheet (numberOfPrint of the first strip = number of sheets)."
    } else {
        $lblHint.Text = "DB only stores the photos of frame 1. Other frames are filled with unused raw photos, then the photos of frame 1, up to the number of photos of the layout. Edit listImages of each frame if needed (raw photos are listed on the right)."
    }
    $sbForm.Controls.Add($lblHint)

    $txtSbJson = New-Object System.Windows.Forms.TextBox
    $txtSbJson.Location = New-Object System.Drawing.Point(15, 60)
    $txtSbJson.Size = New-Object System.Drawing.Size(760, 590)
    $txtSbJson.Multiline = $true
    $txtSbJson.ScrollBars = "Both"
    $txtSbJson.WordWrap = $false
    $txtSbJson.AcceptsTab = $true
    $txtSbJson.Font = New-Object System.Drawing.Font("Consolas", 10)
    $txtSbJson.Text = $json
    $sbForm.Controls.Add($txtSbJson)

    $txtSbInfo = New-Object System.Windows.Forms.TextBox
    $txtSbInfo.Location = New-Object System.Drawing.Point(785, 60)
    $txtSbInfo.Size = New-Object System.Drawing.Size(435, 590)
    $txtSbInfo.Multiline = $true
    $txtSbInfo.ScrollBars = "Both"
    $txtSbInfo.WordWrap = $false
    $txtSbInfo.ReadOnly = $true
    $txtSbInfo.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtSbInfo.Text = $infoText
    $sbForm.Controls.Add($txtSbInfo)

    if ($mode -ne "Print") {
        $btnSbRemoveFilter = New-Object System.Windows.Forms.Button
        $btnSbRemoveFilter.Text = "Remove filter"
        $btnSbRemoveFilter.Location = New-Object System.Drawing.Point(15, 665)
        $btnSbRemoveFilter.Size = New-Object System.Drawing.Size(140, 38)
        $sbForm.Controls.Add($btnSbRemoveFilter)

        $btnSbRemoveFilter.Add_Click({
            $txtSbJson.Text = Remove-ImageFilterSuffix -json $txtSbJson.Text
        })

        $btnSbChoosePhotos = New-Object System.Windows.Forms.Button
        $btnSbChoosePhotos.Text = "Choose photos"
        $btnSbChoosePhotos.Location = New-Object System.Drawing.Point(165, 665)
        $btnSbChoosePhotos.Size = New-Object System.Drawing.Size(160, 38)
        $sbForm.Controls.Add($btnSbChoosePhotos)

        $btnSbChoosePhotos.Add_Click({
            try {
                $null = $txtSbJson.Text | ConvertFrom-Json -ErrorAction Stop
            } catch {
                [System.Windows.Forms.MessageBox]::Show("JSON is invalid: $($_.Exception.Message)", "Invalid JSON")
                return
            }

            $newJson = Show-PhotoPickerPopup -transactionId $transactionId -json $txtSbJson.Text
            if ($newJson) {
                $txtSbJson.Text = $newJson
            }
        })
    }

    $btnSbSend = New-Object System.Windows.Forms.Button
    $btnSbSend.Text = "Send"
    $btnSbSend.Location = New-Object System.Drawing.Point(925, 665)
    $btnSbSend.Size = New-Object System.Drawing.Size(140, 38)
    $sbForm.Controls.Add($btnSbSend)

    $btnSbClose = New-Object System.Windows.Forms.Button
    $btnSbClose.Text = "Close"
    $btnSbClose.Location = New-Object System.Drawing.Point(1080, 665)
    $btnSbClose.Size = New-Object System.Drawing.Size(140, 38)
    $sbForm.Controls.Add($btnSbClose)

    $btnSbSend.Add_Click({
        try {
            $null = $txtSbJson.Text | ConvertFrom-Json -ErrorAction Stop
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "JSON is invalid: $($_.Exception.Message)",
                "Invalid JSON"
            )
            return
        }

        $editedJson = $txtSbJson.Text
        $sbForm.Close()

        switch ($mode) {
            "ProcessImage" {
                Send-ToProcessAPI `
                    -transactionId $transactionId `
                    -apiUrl "http://localhost:8088/api/file/processimage" `
                    -apiName "ProcessImage" `
                    -requestJson $editedJson
            }
            "ProcessVideo" {
                Send-ToProcessAPI `
                    -transactionId $transactionId `
                    -apiUrl "http://localhost:8088/api/file/processvideo" `
                    -apiName "ProcessVideo" `
                    -requestJson $editedJson
            }
            "Print" {
                Send-ToSelfBoothPrintAPI -requestJson $editedJson
            }
        }
    })

    $btnSbClose.Add_Click({
        $sbForm.Close()
    })

    [void]$sbForm.ShowDialog($form)
}

function Start-SelfBoothAction {
    param(
        [string]$transactionId,
        [string]$mode
    )

    $frames = Get-SelfBoothFrames -transactionId $transactionId
    if ($frames.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No photo package rows for this transaction!", "Error")
        return
    }

    if ($mode -eq "Print") {
        $json = Get-SelfBoothPrintJson -transactionId $transactionId -frames $frames
    } else {
        $json = Get-SelfBoothProcessJson -transactionId $transactionId -apiName $mode -frames $frames
    }

    if (-not $json) {
        [System.Windows.Forms.MessageBox]::Show("Transaction not found!", "Error")
        return
    }

    $infoText = Get-SelfBoothFramesText -transactionId $transactionId -frames $frames
    Show-SelfBoothJsonPopup -transactionId $transactionId -mode $mode -json $json -infoText $infoText
}

function Load-Transactions {
    param (
        [string]$searchText = "",
        [string]$layoutFilter = "",
        [int]$page = 1,
        [bool]$refreshCount = $false
    )

    if ($refreshCount -or $global:TotalPages -lt 1) {
        $countCmd = $global:SQLiteConnection.CreateCommand()
        $countQuery = "SELECT COUNT(*) FROM Transactions WHERE 1=1"

        if ($searchText) {
            $countQuery += " AND Id LIKE @search"
            $countCmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@search", "%$searchText%"))) | Out-Null
        }

        if ($layoutFilter -and $layoutFilter -ne "<All>") {
            $countQuery += " AND LayoutId = @layout"
            $countCmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@layout", $layoutFilter))) | Out-Null
        }

        $countCmd.CommandText = $countQuery
        $global:TotalRows = [int64]$countCmd.ExecuteScalar()
        $global:TotalPages = [Math]::Max(
            1,
            [int][Math]::Ceiling($global:TotalRows / [double]$global:PageSize)
        )
    }

    if ($page -lt 1) {
        $page = 1
    }
    if ($page -gt $global:TotalPages) {
        $page = $global:TotalPages
    }

    $global:LoadedSearchText = $searchText
    $global:LoadedLayoutFilter = $layoutFilter
    $offset = ($page - 1) * $global:PageSize
    $cmd = $global:SQLiteConnection.CreateCommand()
    $packageColumn = if ($global:HasPackageTable) {
        "(SELECT COUNT(*) FROM TransactionPhotoPackageLayoutThemes p WHERE p.TransactionId = Transactions.Id)"
    } else {
        "0"
    }
    $query = "SELECT Id, RecordAt, LayoutId, $packageColumn AS PackageRows FROM Transactions WHERE 1=1"

    if ($searchText) {
        $query += " AND Id LIKE @search"
        $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@search", "%$searchText%"))) | Out-Null
    }

    if ($layoutFilter -and $layoutFilter -ne "<All>") {
        $query += " AND LayoutId = @layout"
        $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@layout", $layoutFilter))) | Out-Null
    }

    $query += " ORDER BY RecordAt DESC LIMIT @limit OFFSET @offset"
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@limit", ($global:PageSize + 1)))) | Out-Null
    $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@offset", $offset))) | Out-Null
    $cmd.CommandText = $query

    $rows = @()
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $rows += ,@(
            [string]$reader["Id"],
            ([datetime]$reader["RecordAt"]).ToString("yyyy-MM-dd HH:mm"),
            [string]$reader["LayoutId"],
            $(if ([int64]$reader["PackageRows"] -gt 0) { "Selfbooth ($($reader["PackageRows"]) layout)" } else { "" })
        )
    }
    $reader.Close()

    $global:HasNextPage = $page -lt $global:TotalPages
    $global:CurrentPage = $page

    $listView.BeginUpdate()
    $listView.Items.Clear()
    foreach ($row in @($rows | Select-Object -First $global:PageSize)) {
        $item = New-Object System.Windows.Forms.ListViewItem($row[0])
        [void]$item.SubItems.Add($row[1])
        [void]$item.SubItems.Add($row[2])
        [void]$item.SubItems.Add($row[3])
        $listView.Items.Add($item) | Out-Null
    }
    $listView.EndUpdate()

    $lblPage.Text = "Page $global:CurrentPage / $global:TotalPages"
    $numPage.Maximum = [decimal]$global:TotalPages
    $numPage.Value = [decimal]$global:CurrentPage
    $btnPrevious.Enabled = $global:CurrentPage -gt 1
    $btnNext.Enabled = $global:HasNextPage
    $btnGoPage.Enabled = $global:TotalPages -gt 1
}

function Load-LayoutFilter {
    $cboLayoutFilter.Items.Clear()
    $cboLayoutFilter.Items.Add("<All>")

    $cmd = $global:SQLiteConnection.CreateCommand()
    $cmd.CommandText = "SELECT DISTINCT LayoutId FROM Transactions ORDER BY LayoutId"

    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $cboLayoutFilter.Items.Add($reader["LayoutId"])
    }
    $reader.Close()

    $global:IsLoadingLayoutFilter = $true
    $cboLayoutFilter.SelectedIndex = 0
    $global:IsLoadingLayoutFilter = $false
}

# =========================
# Main form
# =========================
$global:PageSize = 20
$global:CurrentPage = 1
$global:HasNextPage = $false
$global:IsLoadingLayoutFilter = $false
$global:LoadedSearchText = ""
$global:LoadedLayoutFilter = "<All>"
$global:TotalRows = 0
$global:TotalPages = 0
$global:HasPackageTable = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = "Transactions Viewer"
$form.Size = New-Object System.Drawing.Size(1050, 820)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(20, 20)
$listView.Size = New-Object System.Drawing.Size(990, 400)
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Columns.Add("TransactionId", 400)
$listView.Columns.Add("Date", 190)
$listView.Columns.Add("LayoutId", 100)
$listView.Columns.Add("Flow", 270)
$form.Controls.Add($listView)

$lblSelected = New-Object System.Windows.Forms.Label
$lblSelected.Text = "Selected TransactionId:"
$lblSelected.Location = New-Object System.Drawing.Point(500, 440)
$lblSelected.Size = New-Object System.Drawing.Size(510, 30)
$form.Controls.Add($lblSelected)

$btnPrevious = New-Object System.Windows.Forms.Button
$btnPrevious.Text = "Previous"
$btnPrevious.Location = New-Object System.Drawing.Point(20, 435)
$btnPrevious.Size = New-Object System.Drawing.Size(90, 35)
$btnPrevious.Enabled = $false
$form.Controls.Add($btnPrevious)

$lblPage = New-Object System.Windows.Forms.Label
$lblPage.Text = "Page 1 / 1"
$lblPage.Location = New-Object System.Drawing.Point(115, 440)
$lblPage.Size = New-Object System.Drawing.Size(120, 30)
$lblPage.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($lblPage)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = "Next"
$btnNext.Location = New-Object System.Drawing.Point(240, 435)
$btnNext.Size = New-Object System.Drawing.Size(75, 35)
$btnNext.Enabled = $false
$form.Controls.Add($btnNext)

$numPage = New-Object System.Windows.Forms.NumericUpDown
$numPage.Location = New-Object System.Drawing.Point(325, 437)
$numPage.Size = New-Object System.Drawing.Size(70, 35)
$numPage.Minimum = 1
$numPage.Maximum = 1
$numPage.Value = 1
$numPage.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
$form.Controls.Add($numPage)

$btnGoPage = New-Object System.Windows.Forms.Button
$btnGoPage.Text = "Go"
$btnGoPage.Location = New-Object System.Drawing.Point(405, 435)
$btnGoPage.Size = New-Object System.Drawing.Size(65, 35)
$btnGoPage.Enabled = $false
$form.Controls.Add($btnGoPage)

$txtNumPrint = New-Object System.Windows.Forms.TextBox
$txtNumPrint.Location = New-Object System.Drawing.Point(20, 480)
$txtNumPrint.Size = New-Object System.Drawing.Size(80, 35)
$txtNumPrint.Text = "1"
$form.Controls.Add($txtNumPrint)

$btnPrintNow = New-Object System.Windows.Forms.Button
$btnPrintNow.Text = "Print"
$btnPrintNow.Location = New-Object System.Drawing.Point(110, 480)
$btnPrintNow.Size = New-Object System.Drawing.Size(100, 40)
$form.Controls.Add($btnPrintNow)

$btnViewImage = New-Object System.Windows.Forms.Button
$btnViewImage.Text = "View Image"
$btnViewImage.Location = New-Object System.Drawing.Point(220, 480)
$btnViewImage.Size = New-Object System.Drawing.Size(120, 40)
$form.Controls.Add($btnViewImage)

$btnCopyJson = New-Object System.Windows.Forms.Button
$btnCopyJson.Text = "Copy JSON"
$btnCopyJson.Location = New-Object System.Drawing.Point(350, 480)
$btnCopyJson.Size = New-Object System.Drawing.Size(120, 40)
$form.Controls.Add($btnCopyJson)

$btnProcessImage = New-Object System.Windows.Forms.Button
$btnProcessImage.Text = "Process Image"
$btnProcessImage.Location = New-Object System.Drawing.Point(480, 480)
$btnProcessImage.Size = New-Object System.Drawing.Size(170, 40)
$form.Controls.Add($btnProcessImage)

$btnProcessVideo = New-Object System.Windows.Forms.Button
$btnProcessVideo.Text = "Process Video"
$btnProcessVideo.Location = New-Object System.Drawing.Point(660, 480)
$btnProcessVideo.Size = New-Object System.Drawing.Size(170, 40)
$form.Controls.Add($btnProcessVideo)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(20, 535)
$txtSearch.Size = New-Object System.Drawing.Size(300, 35)
$form.Controls.Add($txtSearch)

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = "Search"
$btnSearch.Location = New-Object System.Drawing.Point(340, 535)
$btnSearch.Size = New-Object System.Drawing.Size(100, 35)
$form.Controls.Add($btnSearch)

$cboLayoutFilter = New-Object System.Windows.Forms.ComboBox
$cboLayoutFilter.Location = New-Object System.Drawing.Point(460, 535)
$cboLayoutFilter.Size = New-Object System.Drawing.Size(200, 35)
$cboLayoutFilter.DropDownStyle = "DropDownList"
$form.Controls.Add($cboLayoutFilter)

$txtJson = New-Object System.Windows.Forms.TextBox
$txtJson.Location = New-Object System.Drawing.Point(20, 590)
$txtJson.Size = New-Object System.Drawing.Size(990, 180)
$txtJson.Multiline = $true
$txtJson.ScrollBars = "Both"
$txtJson.WordWrap = $false
$txtJson.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Regular)
$form.Controls.Add($txtJson)

$btnViewImage.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a transaction first!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    Show-ImagePopup -transactionId $transactionId
})

$btnPrintNow.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a transaction!", "Missing data")
        return
    }

    $num = 1
    if ([int]::TryParse($txtNumPrint.Text, [ref]$num) -eq $false -or $num -le 0) {
        [System.Windows.Forms.MessageBox]::Show("Invalid number of prints", "Error")
        return
    }

    $selected = $listView.SelectedItems[0]
    $transactionId = $selected.Text
    $layoutId = $selected.SubItems[2].Text

    # Selfbooth: print every frame of the photo package (number of prints is edited in the popup)
    if (Test-SelfBoothTransaction -transactionId $transactionId) {
        Start-SelfBoothAction -transactionId $transactionId -mode "Print"
        return
    }

    Send-ToPrintAPI -transactionId $transactionId -layoutId $layoutId -numberOfImage $num
})

$btnCopyJson.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a transaction first!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    $json = Get-TransactionJson -transactionId $transactionId -apiName "Export"

    if (-not $json) {
        [System.Windows.Forms.MessageBox]::Show("Transaction not found!", "Error")
        return
    }

    $txtJson.Text = $json
    [System.Windows.Forms.Clipboard]::SetText($json)
    [System.Windows.Forms.MessageBox]::Show("JSON copied!", "Success")
})

$btnProcessImage.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a transaction first!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    if (Test-SelfBoothTransaction -transactionId $transactionId) {
        Start-SelfBoothAction -transactionId $transactionId -mode "ProcessImage"
        return
    }

    Send-ToProcessImageAPI -transactionId $transactionId
})

$btnProcessVideo.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a transaction first!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    if (Test-SelfBoothTransaction -transactionId $transactionId) {
        Start-SelfBoothAction -transactionId $transactionId -mode "ProcessVideo"
        return
    }

    Send-ToProcessVideoAPI -transactionId $transactionId
})

$listView.Add_SelectedIndexChanged({
    if ($listView.SelectedItems.Count -gt 0) {
        $selected = $listView.SelectedItems[0]
        $lblSelected.Text = "Selected TransactionId: " + $selected.Text
    }
})

$btnSearch.Add_Click({
    $searchText = $txtSearch.Text.Trim()

    Load-Transactions `
        -searchText $searchText `
        -layoutFilter $cboLayoutFilter.SelectedItem `
        -page 1 `
        -refreshCount $true
})

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $btnSearch.PerformClick()
    }
})

$cboLayoutFilter.Add_SelectedIndexChanged({
    if (-not $global:IsLoadingLayoutFilter) {
        Load-Transactions `
            -searchText $global:LoadedSearchText `
            -layoutFilter $cboLayoutFilter.SelectedItem `
            -page 1 `
            -refreshCount $true
    }
})

$btnPrevious.Add_Click({
    if ($global:CurrentPage -gt 1) {
        Load-Transactions `
            -searchText $global:LoadedSearchText `
            -layoutFilter $global:LoadedLayoutFilter `
            -page ($global:CurrentPage - 1)
    }
})

$btnNext.Add_Click({
    if ($global:HasNextPage) {
        Load-Transactions `
            -searchText $global:LoadedSearchText `
            -layoutFilter $global:LoadedLayoutFilter `
            -page ($global:CurrentPage + 1)
    }
})

$btnGoPage.Add_Click({
    $targetPage = [int]$numPage.Value
    if ($targetPage -ne $global:CurrentPage) {
        Load-Transactions `
            -searchText $global:LoadedSearchText `
            -layoutFilter $global:LoadedLayoutFilter `
            -page $targetPage
    }
})

if (Show-LoginForm) {
    Open-SQLiteConnection
    $global:HasPackageTable = Test-SQLiteTable -tableName "TransactionPhotoPackageLayoutThemes"
    Load-LayoutFilter
    Load-Transactions -page 1 -refreshCount $true
    $form.TopMost = $false
    [void]$form.ShowDialog()
    Close-SQLiteConnection
} else {
    [System.Windows.Forms.MessageBox]::Show("You exited or entered the wrong password!", "Exit")
}
