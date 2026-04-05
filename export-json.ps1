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
    $correctPasswords = @("funstud!o", "kien", "quoc", "vanh")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Login"
    $form.Size = New-Object System.Drawing.Size(400, 220)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter password:"
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(350, 30)
    $form.Controls.Add($label)

    $textbox = New-Object System.Windows.Forms.TextBox
    $textbox.Location = New-Object System.Drawing.Point(20, 60)
    $textbox.Size = New-Object System.Drawing.Size(340, 30)
    $textbox.UseSystemPasswordChar = $true
    $form.Controls.Add($textbox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(70, 110)
    $okButton.Size = New-Object System.Drawing.Size(100, 40)
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Exit"
    $cancelButton.Location = New-Object System.Drawing.Point(200, 110)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 40)
    $form.Controls.Add($cancelButton)

    $okButton.Add_Click({
        if ($correctPasswords -contains $textbox.Text) {
            $form.Tag = $true
            $form.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Wrong password!", "Error")
            $textbox.Clear()
        }
    })

    $cancelButton.Add_Click({
        $form.Tag = $false
        $form.Close()
    })

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    [void]$form.ShowDialog()
    return $form.Tag -eq $true
}

# Gọi API in lại
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

function Export-TransactionJson {
    param(
        [string]$transactionId
    )

    try {
        $cmd = $global:SQLiteConnection.CreateCommand()
        $cmd.CommandText = "SELECT * FROM Transactions WHERE Id = @id LIMIT 1"
        $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@id", $transactionId))) | Out-Null

        $reader = $cmd.ExecuteReader()

        if (-not $reader.Read()) {
            $reader.Close()
            [System.Windows.Forms.MessageBox]::Show("Không tìm thấy transaction!", "Error")
            return
        }

        $result = [ordered]@{}

        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $name = $reader.GetName($i)
            $value = $reader.GetValue($i)

            if ($value -eq [DBNull]::Value) {
                $result[$name] = $null
                continue
            }

            if ($name -eq "Images" -or $name -eq "LayoutParameters") {
                try {
                    $result[$name] = $value.ToString() | ConvertFrom-Json
                } catch {
                    $result[$name] = $value.ToString()
                }
            }
            else {
                $result[$name] = $value
            }
        }

        $reader.Close()

        $json = $result | ConvertTo-Json -Depth 20

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

# Load danh sách giao dịch từ DB
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

# Load danh sách LayoutId duy nhất
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
$form.Size = New-Object System.Drawing.Size(980, 650)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)

$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(20, 20)
$listView.Size = New-Object System.Drawing.Size(920, 400)
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Columns.Add("TransactionId", 380)
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

# Search TransactionId
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(20, 530)
$txtSearch.Size = New-Object System.Drawing.Size(300, 30)
$form.Controls.Add($txtSearch)

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = "Search"
$btnSearch.Location = New-Object System.Drawing.Point(340, 530)
$btnSearch.Size = New-Object System.Drawing.Size(100, 35)
$form.Controls.Add($btnSearch)

# Filter LayoutId
$cboLayoutFilter = New-Object System.Windows.Forms.ComboBox
$cboLayoutFilter.Location = New-Object System.Drawing.Point(460, 530)
$cboLayoutFilter.Size = New-Object System.Drawing.Size(200, 30)
$cboLayoutFilter.DropDownStyle = "DropDownList"
$form.Controls.Add($cboLayoutFilter)

# Nút View Image
$btnViewImage = New-Object System.Windows.Forms.Button
$btnViewImage.Text = "View Image"
$btnViewImage.Location = New-Object System.Drawing.Point(570, 480)
$btnViewImage.Size = New-Object System.Drawing.Size(120, 40)
$form.Controls.Add($btnViewImage)

# Nút Export JSON
$btnExportJson = New-Object System.Windows.Forms.Button
$btnExportJson.Text = "Export JSON"
$btnExportJson.Location = New-Object System.Drawing.Point(710, 480)
$btnExportJson.Size = New-Object System.Drawing.Size(130, 40)
$form.Controls.Add($btnExportJson)

# Event View Image
$btnViewImage.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a transaction first!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    Show-ImagePopup -transactionId $transactionId
})

# Event Print
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

# Event Export JSON
$btnExportJson.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn transaction trước!", "Missing data")
        return
    }

    $transactionId = $listView.SelectedItems[0].Text
    Export-TransactionJson -transactionId $transactionId
})

# Event chọn item
$listView.Add_SelectedIndexChanged({
    if ($listView.SelectedItems.Count -gt 0) {
        $selected = $listView.SelectedItems[0]
        $lblSelected.Text = "Selected TransactionId: " + $selected.Text
    }
})

# Event Search button
$btnSearch.Add_Click({
    Load-Transactions -searchText $txtSearch.Text.Trim() -layoutFilter $cboLayoutFilter.SelectedItem
})

# Enter để search luôn
$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Load-Transactions -searchText $txtSearch.Text.Trim() -layoutFilter $cboLayoutFilter.SelectedItem
    }
})

# Event filter layout
$cboLayoutFilter.Add_SelectedIndexChanged({
    Load-Transactions -searchText $txtSearch.Text.Trim() -layoutFilter $cboLayoutFilter.SelectedItem
})

# Chạy chương trình
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