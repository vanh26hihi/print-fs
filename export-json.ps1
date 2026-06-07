Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Load SQLite DLL manually from local file
$sqliteDllPath = "D:\Work\PhotoBooth\Data\System.Data.SQLite.dll"
if (-not (Test-Path $sqliteDllPath)) {
    try {
        Invoke-WebRequest -Uri "https://github.com/trankien27/print-fs/raw/refs/heads/main/System.Data.SQLite.dll" `
            -OutFile $sqliteDllPath -UseBasicParsing
    } catch {
        [System.Windows.Forms.MessageBox]::Show("❌ Cannot download SQLite DLL. Check internet connection or update URL.", "DLL Load Error")
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
        $null = Invoke-RestMethod -Uri $apiUrl -Method POST -Body $json -ContentType "application/json"
        [System.Windows.Forms.MessageBox]::Show("✅ Print successfully!", "Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("❌ Send error: $($_.Exception.Message)", "Error")
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
            [System.Windows.Forms.MessageBox]::Show("Không tìm thấy transaction để $apiName!", "Error")
            return
        }

        $txtJson.Text = @"
===== $apiName REQUEST URL =====
$apiUrl

===== $apiName REQUEST BODY =====
$json

Đang gửi API $apiName...
"@

        Write-ApiLog "$apiName REQUEST_URL=$apiUrl"
        Write-ApiLog "$apiName REQUEST_BODY=$json"

        $response = Invoke-WebRequest `
            -Uri $apiUrl `
            -Method POST `
            -Body $json `
            -ContentType "application/json" `
            -UseBasicParsing

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

        [System.Windows.Forms.MessageBox]::Show("✅ $apiName thành công!`nResponse Code: $responseCode", "Success")
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
    $btnRemoveF1.Text = "Remove _f1"
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
        try {
            $body = $txtRetryJson.Text | ConvertFrom-Json -ErrorAction Stop

            if ($null -ne $body.listImages) {
                foreach ($image in @($body.listImages)) {
                    if ($null -ne $image.fileName) {
                        $image.fileName = ([string]$image.fileName) -replace '_f1(?=\.[^\\/.]+$)', ''
                    }
                }
            }

            $txtRetryJson.Text = $body | ConvertTo-Json -Depth 20
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "JSON is invalid: $($_.Exception.Message)",
                "Invalid JSON"
            )
        }
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

    $imagePath = "D:\Work\PhotoBooth\Image\$transactionId\$transactionId.png"

    if (-not (Test-Path $imagePath)) {
        [System.Windows.Forms.MessageBox]::Show("❌ Image not found:`n$imagePath", "Error")
        return
    }

    $imgForm = New-Object System.Windows.Forms.Form
    $imgForm.Text = "Preview - $transactionId"
    $imgForm.Size = New-Object System.Drawing.Size(600, 600)
    $imgForm.StartPosition = "CenterParent"
    $imgForm.TopMost = $true

    $pictureBox = New-Object System.Windows.Forms.PictureBox
    $pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $pictureBox.Image = [System.Drawing.Image]::FromFile($imagePath)

    $imgForm.Controls.Add($pictureBox)
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

    # listImages lấy từ Transactions.Images
    $listImages = @()
    $imagesRaw = Get-DbStringOrEmpty -reader $reader -name "Images"

    if (-not [string]::IsNullOrWhiteSpace($imagesRaw)) {
        try {
            $parsedImages = $imagesRaw | ConvertFrom-Json

            if ($null -ne $parsedImages) {
                foreach ($img in @($parsedImages)) {
                    $flipValue = 0
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
    # - ProcessImage: luôn để [] để tránh lỗi StickerMapper null khi stickerId = 0
    # - ProcessVideo / Export: lấy sticker thật nếu có, không tự thêm stickerId = 0
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

        # Theo yêu cầu: luôn true
        isVideo = $true

        # Không có thì để rỗng ""
        voucherCode = Get-DbStringOrEmpty -reader $reader -name "VoucherCode"

        purchaseDuration = Get-DbInt -reader $reader -name "PurchaseDuration" -defaultValue 0
        captureDuration = Get-DbInt -reader $reader -name "CaptureDuration" -defaultValue 0
        editDuration = Get-DbInt -reader $reader -name "EditDuration" -defaultValue 0
        printNumber = Get-DbInt -reader $reader -name "PrintNumber" -defaultValue 0
        layoutAmount = Get-DbDecimal -reader $reader -name "LayoutAmount" -defaultValue 0
        printAmount = Get-DbDecimal -reader $reader -name "PrintAmount" -defaultValue 0
        discount = Get-DbDecimal -reader $reader -name "Discount" -defaultValue 0
        deposit = Get-DbDecimal -reader $reader -name "Deposit" -defaultValue 0

        # Theo mẫu trước: không có thì "string"
        pinCode = Get-DbStringOrString -reader $reader -name "Pincode"

        refundAmount = Get-DbDecimal -reader $reader -name "RefundAmount" -defaultValue 0

        # Theo mẫu trước: không có thì "string"
        refundReason = Get-DbStringOrString -reader $reader -name "RefundReason"

        # IsConfirmPolicy = 1 thì true
        isConfirmPolicy = Get-DbBool -reader $reader -name "IsConfirmPolicy" -defaultValue $false

        # Theo mẫu: mặc định true
        isSelfBooth = $true

        listSticker = $listSticker
        listImages = $listImages

        # Theo yêu cầu: mặc định
        isAiFlow = $true
        promptTemplateId = 0
        pinCodeDownload = "string"
    }

    $reader.Close()

    return ($result | ConvertTo-Json -Depth 20)
}

function Load-Transactions {
    param (
        [string]$searchText = "",
        [string]$layoutFilter = "",
        [int]$page = 1
    )

    if ($page -lt 1) {
        $page = 1
    }

    $global:LoadedSearchText = $searchText
    $global:LoadedLayoutFilter = $layoutFilter
    $offset = ($page - 1) * $global:PageSize
    $cmd = $global:SQLiteConnection.CreateCommand()
    $query = "SELECT Id, RecordAt, LayoutId FROM Transactions WHERE 1=1"

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
            [string]$reader["LayoutId"]
        )
    }
    $reader.Close()

    $global:HasNextPage = $rows.Count -gt $global:PageSize
    $global:CurrentPage = $page

    $listView.BeginUpdate()
    $listView.Items.Clear()
    foreach ($row in @($rows | Select-Object -First $global:PageSize)) {
        $item = New-Object System.Windows.Forms.ListViewItem($row[0])
        $item.SubItems.Add($row[1])
        $item.SubItems.Add($row[2])
        $listView.Items.Add($item) | Out-Null
    }
    $listView.EndUpdate()

    $lblPage.Text = "Page $global:CurrentPage"
    $btnPrevious.Enabled = $global:CurrentPage -gt 1
    $btnNext.Enabled = $global:HasNextPage
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
# Form chính
# =========================
$global:PageSize = 20
$global:CurrentPage = 1
$global:HasNextPage = $false
$global:IsLoadingLayoutFilter = $false
$global:LoadedSearchText = ""
$global:LoadedLayoutFilter = "<All>"

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
$listView.Columns.Add("TransactionId", 430)
$listView.Columns.Add("Date", 220)
$listView.Columns.Add("LayoutId", 120)
$form.Controls.Add($listView)

$lblSelected = New-Object System.Windows.Forms.Label
$lblSelected.Text = "Selected TransactionId:"
$lblSelected.Location = New-Object System.Drawing.Point(390, 440)
$lblSelected.Size = New-Object System.Drawing.Size(620, 30)
$form.Controls.Add($lblSelected)

$btnPrevious = New-Object System.Windows.Forms.Button
$btnPrevious.Text = "Previous"
$btnPrevious.Location = New-Object System.Drawing.Point(20, 435)
$btnPrevious.Size = New-Object System.Drawing.Size(100, 35)
$btnPrevious.Enabled = $false
$form.Controls.Add($btnPrevious)

$lblPage = New-Object System.Windows.Forms.Label
$lblPage.Text = "Page 1"
$lblPage.Location = New-Object System.Drawing.Point(130, 440)
$lblPage.Size = New-Object System.Drawing.Size(100, 30)
$lblPage.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($lblPage)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = "Next"
$btnNext.Location = New-Object System.Drawing.Point(240, 435)
$btnNext.Size = New-Object System.Drawing.Size(100, 35)
$btnNext.Enabled = $false
$form.Controls.Add($btnNext)

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
$btnSearch.Enabled = $false
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
    Send-ToPrintAPI -transactionId $transactionId -layoutId $layoutId -numberOfImage $num
})

$btnCopyJson.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn transaction trước!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    $json = Get-TransactionJson -transactionId $transactionId -apiName "Export"

    if (-not $json) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy transaction!", "Error")
        return
    }

    $txtJson.Text = $json
    [System.Windows.Forms.Clipboard]::SetText($json)
    [System.Windows.Forms.MessageBox]::Show("✅ Đã copy JSON!", "Success")
})

$btnProcessImage.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn transaction trước!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    Send-ToProcessImageAPI -transactionId $transactionId
})

$btnProcessVideo.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn transaction trước!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
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
    if ([string]::IsNullOrWhiteSpace($searchText)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Enter a transaction ID before searching.",
            "Search"
        )
        return
    }

    Load-Transactions `
        -searchText $searchText `
        -layoutFilter $cboLayoutFilter.SelectedItem `
        -page 1
})

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $btnSearch.PerformClick()
    }
})

$txtSearch.Add_TextChanged({
    $btnSearch.Enabled = -not [string]::IsNullOrWhiteSpace($txtSearch.Text)
})

$cboLayoutFilter.Add_SelectedIndexChanged({
    if (-not $global:IsLoadingLayoutFilter) {
        Load-Transactions `
            -searchText $global:LoadedSearchText `
            -layoutFilter $cboLayoutFilter.SelectedItem `
            -page 1
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

if (Show-LoginForm) {
    Open-SQLiteConnection
    Load-LayoutFilter
    Load-Transactions -page 1
    $form.TopMost = $false
    [void]$form.ShowDialog()
    Close-SQLiteConnection
} else {
    [System.Windows.Forms.MessageBox]::Show("You exited or entered the wrong password!", "Exit")
}
