Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Load SQLite DLL manually from local file
$sqliteDllPath = "D:\\Work\\PhotoBooth\\Data\\System.Data.SQLite.dll"
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
    $correctPasswords = @("funstud!o", "kien", "chien", "vanh")

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

function Write-ProcessVideoLog {
    param(
        [string]$message
    )

    try {
        $logDir = "D:\Work\PhotoBooth\Logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $logPath = Join-Path $logDir "process-video-api.log"
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch {
        # Không chặn flow nếu ghi log lỗi
    }
}

function Send-ToProcessVideoAPI {
    param (
        [string]$transactionId,
        [string]$apiUrl = "http://localhost:8088/api/File/ProcessVideo"
    )

    try {
        $json = Get-TransactionJson -transactionId $transactionId

        if (-not $json) {
            [System.Windows.Forms.MessageBox]::Show("Không tìm thấy transaction để ProcessVideo!", "Error")
            return
        }

        $txtJson.Text = "===== REQUEST ProcessVideo =====`r`n$json`r`n`r`nĐang gửi API: $apiUrl ..."
        Write-ProcessVideoLog "REQUEST transactionId=$transactionId url=$apiUrl body=$json"

        $response = Invoke-WebRequest -Uri $apiUrl -Method POST -Body $json -ContentType "application/json" -UseBasicParsing
        $responseText = $response.Content

        if ([string]::IsNullOrWhiteSpace($responseText)) {
            $responseText = "HTTP $($response.StatusCode) $($response.StatusDescription) - Empty response"
        }

        $logText = "===== REQUEST ProcessVideo =====`r`n$json`r`n`r`n===== RESPONSE ProcessVideo =====`r`n$responseText"
        $txtJson.Text = $logText
        Write-ProcessVideoLog "RESPONSE transactionId=$transactionId status=$($response.StatusCode) body=$responseText"

        [System.Windows.Forms.MessageBox]::Show("✅ ProcessVideo thành công!`nHTTP $($response.StatusCode)`nLog: D:\Work\PhotoBooth\Logs\process-video-api.log", "Success")
    } catch {
        $errorText = $_.Exception.Message

        try {
            if ($_.Exception.Response -ne $null) {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream -ne $null) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $body = $reader.ReadToEnd()
                    if (-not [string]::IsNullOrWhiteSpace($body)) {
                        $errorText = "$errorText`r`n$body"
                    }
                }
            }
        } catch {
            # Bỏ qua lỗi đọc response body
        }

        $txtJson.Text = "===== PROCESS VIDEO ERROR =====`r`n$errorText"
        Write-ProcessVideoLog "ERROR transactionId=$transactionId error=$errorText"
        [System.Windows.Forms.MessageBox]::Show("❌ ProcessVideo lỗi:`n$errorText", "Error")
    }
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
        [string]$transactionId
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
            if ($null -eq $value -or $value -eq '') { return $defaultValue }
            return [int]$value
        } catch {
            return $defaultValue
        }
    }

    function Get-DbDecimal {
        param($reader, [string]$name, [decimal]$defaultValue = 0)
        $value = Get-DbValue -reader $reader -name $name -defaultValue $defaultValue
        try {
            if ($null -eq $value -or $value -eq '') { return $defaultValue }
            return [decimal]$value
        } catch {
            return $defaultValue
        }
    }

    function Get-DbString {
        param($reader, [string]$name, [string]$defaultValue = '')
        $value = Get-DbValue -reader $reader -name $name -defaultValue $defaultValue
        if ($null -eq $value -or $value -eq [DBNull]::Value) { return $defaultValue }
        return [string]$value
    }

    function Get-DbBool {
        param($reader, [string]$name, [bool]$defaultValue = $false)
        $value = Get-DbValue -reader $reader -name $name -defaultValue $defaultValue
        if ($null -eq $value -or $value -eq [DBNull]::Value -or $value -eq '') { return $defaultValue }
        try {
            if ($value -is [bool]) { return $value }
            if ($value -is [string]) {
                return ($value.ToLower() -eq 'true' -or $value -eq '1')
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

    # ===== listImages: lấy từ cột Transactions.Images và ép về đúng format API =====
    $listImages = @()
    $imagesRaw = Get-DbString -reader $reader -name "Images" -defaultValue "[]"
    if (-not [string]::IsNullOrWhiteSpace($imagesRaw)) {
        try {
            $parsedImages = $imagesRaw | ConvertFrom-Json
            if ($null -ne $parsedImages) {
                foreach ($img in @($parsedImages)) {
                    $listImages += [ordered]@{
                        fileName = if ($null -ne $img.fileName) { [string]$img.fileName } else { "" }
                        rotate = if ($null -ne $img.rotate) { [decimal]$img.rotate } else { 0 }
                        flip = if ($null -ne $img.flip) { [int]$img.flip } else { 0 }
                        isDigitalBackground = if ($null -ne $img.isDigitalBackground) { [bool]$img.isDigitalBackground } else { $false }
                        digitalBackgroundId = if ($null -ne $img.digitalBackgroundId) { [int]$img.digitalBackgroundId } else { 0 }
                    }
                }
            }
        } catch {
            $listImages = @()
        }
    }

    # ===== listSticker: lấy từ bảng TransactionStickers =====
    $listSticker = @()
    try {
        $stickerCmd = $global:SQLiteConnection.CreateCommand()
        $stickerCmd.CommandText = "SELECT StickerId, Width, Height, AxisX, AxisY FROM TransactionStickers WHERE TransactionId = @id"
        $stickerCmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null
        $stickerReader = $stickerCmd.ExecuteReader()
        while ($stickerReader.Read()) {
            $listSticker += [ordered]@{
                rotate = 0
                stickerId = Get-DbInt -reader $stickerReader -name "StickerId" -defaultValue 0
                width = Get-DbInt -reader $stickerReader -name "Width" -defaultValue 0
                height = Get-DbInt -reader $stickerReader -name "Height" -defaultValue 0
                axisX = Get-DbInt -reader $stickerReader -name "AxisX" -defaultValue 0
                axisY = Get-DbInt -reader $stickerReader -name "AxisY" -defaultValue 0
            }
        }
        $stickerReader.Close()
    } catch {
        $listSticker = @()
    }

    # ===== isAiFlow: true nếu có PromptTemplateId hoặc có bản ghi trong GoogleAIQueues =====
    $isAiFlow = $false
    $promptTemplateId = Get-DbInt -reader $reader -name "PromptTemplateId" -defaultValue 0
    if ($promptTemplateId -gt 0) {
        $isAiFlow = $true
    } else {
        try {
            $aiCmd = $global:SQLiteConnection.CreateCommand()
            $aiCmd.CommandText = "SELECT COUNT(1) FROM GoogleAIQueues WHERE TransactionId = @id"
            $aiCmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null
            $isAiFlow = ([int]$aiCmd.ExecuteScalar() -gt 0)
        } catch {
            $isAiFlow = $false
        }
    }

    $result = [ordered]@{
        code = Get-DbString -reader $reader -name "Code" -defaultValue ""
        PaymentMethod = Get-DbInt -reader $reader -name "PaymentMethod" -defaultValue 0
        frameId = Get-DbInt -reader $reader -name "FrameId" -defaultValue 0
        layoutId = Get-DbInt -reader $reader -name "LayoutId" -defaultValue 0
        themeId = Get-DbInt -reader $reader -name "ThemeId" -defaultValue 0
        backgroundId = Get-DbInt -reader $reader -name "BackgroundId" -defaultValue 0
        filterId = Get-DbInt -reader $reader -name "FilterId" -defaultValue 0
        transactionId = Get-DbString -reader $reader -name "Id" -defaultValue $transactionId
        themeDetailId = 0
        captureMode = Get-DbInt -reader $reader -name "CaptureMode" -defaultValue 0
        isFile = ((Get-DbBool -reader $reader -name "IsFile" -defaultValue $false) -or (@($listImages).Count -gt 0))
        isVideo = ((Get-DbInt -reader $reader -name "NumberOfGenVideo" -defaultValue 0) -gt 0)
        voucherCode = Get-DbString -reader $reader -name "VoucherCode" -defaultValue ""
        purchaseDuration = Get-DbInt -reader $reader -name "PurchaseDuration" -defaultValue 0
        captureDuration = Get-DbInt -reader $reader -name "CaptureDuration" -defaultValue 0
        editDuration = Get-DbInt -reader $reader -name "EditDuration" -defaultValue 0
        printNumber = Get-DbInt -reader $reader -name "PrintNumber" -defaultValue 0
        layoutAmount = Get-DbDecimal -reader $reader -name "LayoutAmount" -defaultValue 0
        printAmount = Get-DbDecimal -reader $reader -name "PrintAmount" -defaultValue 0
        discount = Get-DbDecimal -reader $reader -name "Discount" -defaultValue 0
        deposit = Get-DbDecimal -reader $reader -name "Deposit" -defaultValue 0
        pinCode = Get-DbString -reader $reader -name "Pincode" -defaultValue ""
        refundAmount = Get-DbDecimal -reader $reader -name "RefundAmount" -defaultValue 0
        refundReason = Get-DbString -reader $reader -name "RefundReason" -defaultValue ""
        isConfirmPolicy = Get-DbBool -reader $reader -name "IsConfirmPolicy" -defaultValue $false
        isSelfBooth = ((Get-DbInt -reader $reader -name "Type" -defaultValue 0) -eq 1)
        listSticker = $listSticker
        listImages = $listImages
        isAiFlow = $isAiFlow
        promptTemplateId = $promptTemplateId
        pinCodeDownload = Get-DbString -reader $reader -name "Pincode" -defaultValue ""
    }

    $reader.Close()

    return ($result | ConvertTo-Json -Depth 20)
}

function Export-TransactionJson {
    param(
        [string]$transactionId
    )

    try {
        $json = Get-TransactionJson -transactionId $transactionId

        if (-not $json) {
            [System.Windows.Forms.MessageBox]::Show("Không tìm thấy transaction!", "Error")
            return
        }

        $txtJson.Text = $json

        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "JSON files (*.json)|*.json"
        $saveDialog.FileName = "$transactionId.json"
        $saveDialog.Title = "Save Transaction JSON"

        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $json | Out-File -FilePath $saveDialog.FileName -Encoding utf8
            [System.Windows.Forms.MessageBox]::Show("✅ Export JSON thành công!`n$($saveDialog.FileName)", "Success")
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("❌ Export JSON lỗi: $($_.Exception.Message)", "Error")
    }
}

function Load-Transactions {
    param (
        [string]$searchText = "",
        [string]$layoutFilter = ""
    )

    $listView.Items.Clear()
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

    $query += " ORDER BY RecordAt DESC LIMIT 200"
    $cmd.CommandText = $query

    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $id = $reader["Id"]
        $date = ([datetime]$reader["RecordAt"]).ToString("yyyy-MM-dd HH:mm")
        $layout = $reader["LayoutId"]

        $item = New-Object System.Windows.Forms.ListViewItem($id)
        $item.SubItems.Add($date)
        $item.SubItems.Add($layout)
        $listView.Items.Add($item)
    }
    $reader.Close()
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

    $cboLayoutFilter.SelectedIndex = 0
}

# =========================
# Form chính
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Transactions Viewer"
$form.Size = New-Object System.Drawing.Size(1000, 780)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(20, 20)
$listView.Size = New-Object System.Drawing.Size(940, 400)
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Columns.Add("TransactionId", 390)
$listView.Columns.Add("Date", 220)
$listView.Columns.Add("LayoutId", 120)
$form.Controls.Add($listView)

$lblSelected = New-Object System.Windows.Forms.Label
$lblSelected.Text = "Selected TransactionId:"
$lblSelected.Location = New-Object System.Drawing.Point(20, 440)
$lblSelected.Size = New-Object System.Drawing.Size(700, 30)
$form.Controls.Add($lblSelected)

$txtNumPrint = New-Object System.Windows.Forms.TextBox
$txtNumPrint.Location = New-Object System.Drawing.Point(340, 480)
$txtNumPrint.Size = New-Object System.Drawing.Size(80, 30)
$txtNumPrint.Text = "1"
$form.Controls.Add($txtNumPrint)

$btnPrintNow = New-Object System.Windows.Forms.Button
$btnPrintNow.Text = "Print"
$btnPrintNow.Location = New-Object System.Drawing.Point(430, 480)
$btnPrintNow.Size = New-Object System.Drawing.Size(120, 40)
$form.Controls.Add($btnPrintNow)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(20, 530)
$txtSearch.Size = New-Object System.Drawing.Size(300, 30)
$form.Controls.Add($txtSearch)

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = "Search"
$btnSearch.Location = New-Object System.Drawing.Point(340, 530)
$btnSearch.Size = New-Object System.Drawing.Size(100, 35)
$form.Controls.Add($btnSearch)

$cboLayoutFilter = New-Object System.Windows.Forms.ComboBox
$cboLayoutFilter.Location = New-Object System.Drawing.Point(460, 530)
$cboLayoutFilter.Size = New-Object System.Drawing.Size(200, 30)
$cboLayoutFilter.DropDownStyle = "DropDownList"
$form.Controls.Add($cboLayoutFilter)

$btnViewImage = New-Object System.Windows.Forms.Button
$btnViewImage.Text = "View Image"
$btnViewImage.Location = New-Object System.Drawing.Point(570, 480)
$btnViewImage.Size = New-Object System.Drawing.Size(120, 40)
$form.Controls.Add($btnViewImage)

$btnExportJson = New-Object System.Windows.Forms.Button
$btnExportJson.Text = "Export JSON"
$btnExportJson.Location = New-Object System.Drawing.Point(710, 480)
$btnExportJson.Size = New-Object System.Drawing.Size(130, 40)
$form.Controls.Add($btnExportJson)

$btnCopyJson = New-Object System.Windows.Forms.Button
$btnCopyJson.Text = "Copy JSON"
$btnCopyJson.Location = New-Object System.Drawing.Point(850, 480)
$btnCopyJson.Size = New-Object System.Drawing.Size(110, 40)
$form.Controls.Add($btnCopyJson)

$btnProcessVideo = New-Object System.Windows.Forms.Button
$btnProcessVideo.Text = "Process Video"
$btnProcessVideo.Location = New-Object System.Drawing.Point(710, 530)
$btnProcessVideo.Size = New-Object System.Drawing.Size(250, 35)
$form.Controls.Add($btnProcessVideo)

$txtJson = New-Object System.Windows.Forms.TextBox
$txtJson.Location = New-Object System.Drawing.Point(20, 580)
$txtJson.Size = New-Object System.Drawing.Size(940, 150)
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

$btnExportJson.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn transaction trước!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    Export-TransactionJson -transactionId $transactionId
})

$btnCopyJson.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn transaction trước!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    $json = Get-TransactionJson -transactionId $transactionId

    if (-not $json) {
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy transaction!", "Error")
        return
    }

    $txtJson.Text = $json
    [System.Windows.Forms.Clipboard]::SetText($json)
    [System.Windows.Forms.MessageBox]::Show("✅ Đã copy JSON!", "Success")
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
    Load-Transactions -searchText $txtSearch.Text.Trim() -layoutFilter $cboLayoutFilter.SelectedItem
})

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Load-Transactions -searchText $txtSearch.Text.Trim() -layoutFilter $cboLayoutFilter.SelectedItem
    }
})

$cboLayoutFilter.Add_SelectedIndexChanged({
    Load-Transactions -searchText $txtSearch.Text.Trim() -layoutFilter $cboLayoutFilter.SelectedItem
})

if (Show-LoginForm) {
    Open-SQLiteConnection
    Load-Transactions
    Load-LayoutFilter
    $form.TopMost = $true
    [void]$form.ShowDialog()
    Close-SQLiteConnection
} else {
    [System.Windows.Forms.MessageBox]::Show("You exited or entered the wrong password!", "Exit")
}