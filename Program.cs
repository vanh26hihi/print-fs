using System;
using System.Collections.Generic;
using System.Data.SQLite;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Forms;

namespace FunstudioTransactionExporter
{
    internal static class Program
    {
        [STAThread]
        static void Main()
        {
            ApplicationConfiguration.Initialize();
            Application.Run(new MainForm());
        }
    }

    public class MainForm : Form
    {
        private TextBox txtDbPath;
        private Button btnBrowseDb;
        private TextBox txtTransactionId;
        private Button btnLoad;
        private Button btnSaveJson;
        private RichTextBox txtJson;

        private ExportTransaction? currentData;

        public MainForm()
        {
            InitializeUI();
        }

        private void InitializeUI()
        {
            Text = "Funstudio DB -> Transaction JSON Export";
            Width = 1000;
            Height = 700;
            StartPosition = FormStartPosition.CenterScreen;

            Label lblDb = new Label
            {
                Text = "DB Path:",
                Left = 20,
                Top = 20,
                Width = 80
            };
            Controls.Add(lblDb);

            txtDbPath = new TextBox
            {
                Left = 100,
                Top = 16,
                Width = 700
            };
            Controls.Add(txtDbPath);

            btnBrowseDb = new Button
            {
                Text = "Browse",
                Left = 820,
                Top = 14,
                Width = 120
            };
            btnBrowseDb.Click += BtnBrowseDb_Click;
            Controls.Add(btnBrowseDb);

            Label lblTransactionId = new Label
            {
                Text = "TransactionId:",
                Left = 20,
                Top = 60,
                Width = 80
            };
            Controls.Add(lblTransactionId);

            txtTransactionId = new TextBox
            {
                Left = 100,
                Top = 56,
                Width = 400
            };
            Controls.Add(txtTransactionId);

            btnLoad = new Button
            {
                Text = "Load JSON",
                Left = 520,
                Top = 54,
                Width = 120
            };
            btnLoad.Click += BtnLoad_Click;
            Controls.Add(btnLoad);

            btnSaveJson = new Button
            {
                Text = "Save JSON",
                Left = 660,
                Top = 54,
                Width = 120
            };
            btnSaveJson.Click += BtnSaveJson_Click;
            Controls.Add(btnSaveJson);

            txtJson = new RichTextBox
            {
                Left = 20,
                Top = 100,
                Width = 920,
                Height = 520,
                Font = new System.Drawing.Font("Consolas", 10),
                WordWrap = false
            };
            Controls.Add(txtJson);
        }

        private void BtnBrowseDb_Click(object? sender, EventArgs e)
        {
            using OpenFileDialog ofd = new OpenFileDialog();
            ofd.Filter = "SQLite DB (*.db;*.sqlite)|*.db;*.sqlite|All files (*.*)|*.*";
            ofd.Title = "Chọn file Funstudio.db";

            if (ofd.ShowDialog() == DialogResult.OK)
            {
                txtDbPath.Text = ofd.FileName;
            }
        }

        private void BtnLoad_Click(object? sender, EventArgs e)
        {
            try
            {
                string dbPath = txtDbPath.Text.Trim();
                string transactionId = txtTransactionId.Text.Trim();

                if (string.IsNullOrWhiteSpace(dbPath) || !File.Exists(dbPath))
                {
                    MessageBox.Show("Vui lòng chọn file DB hợp lệ.");
                    return;
                }

                if (string.IsNullOrWhiteSpace(transactionId))
                {
                    MessageBox.Show("Vui lòng nhập TransactionId.");
                    return;
                }

                currentData = LoadTransaction(dbPath, transactionId);

                if (currentData == null)
                {
                    MessageBox.Show("Không tìm thấy transaction.");
                    txtJson.Clear();
                    return;
                }

                var options = new JsonSerializerOptions
                {
                    WriteIndented = true,
                    DefaultIgnoreCondition = JsonIgnoreCondition.Never
                };

                string json = JsonSerializer.Serialize(currentData, options);
                txtJson.Text = json;
            }
            catch (Exception ex)
            {
                MessageBox.Show("Lỗi:\n" + ex.Message);
            }
        }

        private void BtnSaveJson_Click(object? sender, EventArgs e)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(txtJson.Text))
                {
                    MessageBox.Show("Chưa có JSON để lưu.");
                    return;
                }

                using SaveFileDialog sfd = new SaveFileDialog();
                sfd.Filter = "JSON file (*.json)|*.json";
                sfd.FileName = $"{txtTransactionId.Text.Trim()}.json";

                if (sfd.ShowDialog() == DialogResult.OK)
                {
                    File.WriteAllText(sfd.FileName, txtJson.Text);
                    MessageBox.Show("Lưu JSON thành công.");
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Lỗi khi lưu file:\n" + ex.Message);
            }
        }

        private ExportTransaction? LoadTransaction(string dbPath, string transactionId)
        {
            string connectionString = $"Data Source={dbPath};Version=3;";

            using SQLiteConnection conn = new SQLiteConnection(connectionString);
            conn.Open();

            string sql = @"
SELECT 
    Id,
    RecordAt,
    Code,
    FrameId,
    LayoutId,
    ThemeId,
    FilterId,
    PrintNumber,
    LayoutAmount,
    PrintAmount,
    Discount,
    Deposit,
    CaptureMode,
    PurchaseDuration,
    CaptureDuration,
    EditDuration,
    RefundAmount,
    RefundReason,
    VoucherCode,
    IsFile,
    Images,
    ImageTheme,
    LayoutParameters,
    Status,
    CreatedTime,
    UpdatedTime,
    UploadTime,
    StatusText,
    NumberOfGenVideo,
    BackgroundId,
    PaymentMethod,
    Type,
    OrderInfo,
    OrderId,
    PhoneNumber,
    Pincode,
    IsConfirmPolicy
FROM Transactions
WHERE Id = @Id
LIMIT 1;
";

            using SQLiteCommand cmd = new SQLiteCommand(sql, conn);
            cmd.Parameters.AddWithValue("@Id", transactionId);

            using SQLiteDataReader reader = cmd.ExecuteReader();
            if (!reader.Read())
                return null;

            string? imagesRaw = reader["Images"]?.ToString();
            string? layoutParamsRaw = reader["LayoutParameters"]?.ToString();

            List<TransactionImage>? images = TryParseJson<List<TransactionImage>>(imagesRaw);
            LayoutParameters? layoutParameters = TryParseJson<LayoutParameters>(layoutParamsRaw);

            return new ExportTransaction
            {
                Id = GetString(reader, "Id"),
                RecordAt = GetString(reader, "RecordAt"),
                Code = GetString(reader, "Code"),
                FrameId = GetNullableInt(reader, "FrameId"),
                LayoutId = GetNullableInt(reader, "LayoutId"),
                ThemeId = GetNullableInt(reader, "ThemeId"),
                FilterId = GetNullableInt(reader, "FilterId"),
                PrintNumber = GetNullableInt(reader, "PrintNumber"),
                LayoutAmount = GetNullableDecimal(reader, "LayoutAmount"),
                PrintAmount = GetNullableDecimal(reader, "PrintAmount"),
                Discount = GetNullableDecimal(reader, "Discount"),
                Deposit = GetNullableDecimal(reader, "Deposit"),
                CaptureMode = GetNullableInt(reader, "CaptureMode"),
                PurchaseDuration = GetNullableInt(reader, "PurchaseDuration"),
                CaptureDuration = GetNullableInt(reader, "CaptureDuration"),
                EditDuration = GetNullableInt(reader, "EditDuration"),
                RefundAmount = GetNullableDecimal(reader, "RefundAmount"),
                RefundReason = GetString(reader, "RefundReason"),
                VoucherCode = GetString(reader, "VoucherCode"),
                IsFile = GetNullableInt(reader, "IsFile"),
                Images = images,
                ImageTheme = GetString(reader, "ImageTheme"),
                LayoutParameters = layoutParameters,
                Status = GetNullableInt(reader, "Status"),
                CreatedTime = GetString(reader, "CreatedTime"),
                UpdatedTime = GetString(reader, "UpdatedTime"),
                UploadTime = GetString(reader, "UploadTime"),
                StatusText = GetString(reader, "StatusText"),
                NumberOfGenVideo = GetNullableInt(reader, "NumberOfGenVideo"),
                BackgroundId = GetNullableInt(reader, "BackgroundId"),
                PaymentMethod = GetNullableInt(reader, "PaymentMethod"),
                Type = GetString(reader, "Type"),
                OrderInfo = GetString(reader, "OrderInfo"),
                OrderId = GetString(reader, "OrderId"),
                PhoneNumber = GetString(reader, "PhoneNumber"),
                Pincode = GetString(reader, "Pincode"),
                IsConfirmPolicy = GetNullableInt(reader, "IsConfirmPolicy")
            };
        }

        private static T? TryParseJson<T>(string? json)
        {
            if (string.IsNullOrWhiteSpace(json))
                return default;

            try
            {
                return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            }
            catch
            {
                return default;
            }
        }

        private static string? GetString(SQLiteDataReader reader, string columnName)
        {
            return reader[columnName] == DBNull.Value ? null : reader[columnName].ToString();
        }

        private static int? GetNullableInt(SQLiteDataReader reader, string columnName)
        {
            if (reader[columnName] == DBNull.Value) return null;
            return Convert.ToInt32(reader[columnName]);
        }

        private static decimal? GetNullableDecimal(SQLiteDataReader reader, string columnName)
        {
            if (reader[columnName] == DBNull.Value) return null;
            return Convert.ToDecimal(reader[columnName]);
        }
    }

    public class ExportTransaction
    {
        public string? Id { get; set; }
        public string? RecordAt { get; set; }
        public string? Code { get; set; }
        public int? FrameId { get; set; }
        public int? LayoutId { get; set; }
        public int? ThemeId { get; set; }
        public int? FilterId { get; set; }
        public int? PrintNumber { get; set; }
        public decimal? LayoutAmount { get; set; }
        public decimal? PrintAmount { get; set; }
        public decimal? Discount { get; set; }
        public decimal? Deposit { get; set; }
        public int? CaptureMode { get; set; }
        public int? PurchaseDuration { get; set; }
        public int? CaptureDuration { get; set; }
        public int? EditDuration { get; set; }
        public decimal? RefundAmount { get; set; }
        public string? RefundReason { get; set; }
        public string? VoucherCode { get; set; }
        public int? IsFile { get; set; }
        public List<TransactionImage>? Images { get; set; }
        public string? ImageTheme { get; set; }
        public LayoutParameters? LayoutParameters { get; set; }
        public int? Status { get; set; }
        public string? CreatedTime { get; set; }
        public string? UpdatedTime { get; set; }
        public string? UploadTime { get; set; }
        public string? StatusText { get; set; }
        public int? NumberOfGenVideo { get; set; }
        public int? BackgroundId { get; set; }
        public int? PaymentMethod { get; set; }
        public string? Type { get; set; }
        public string? OrderInfo { get; set; }
        public string? OrderId { get; set; }
        public string? PhoneNumber { get; set; }
        public string? Pincode { get; set; }
        public int? IsConfirmPolicy { get; set; }
    }

    public class TransactionImage
    {
        public string? fileName { get; set; }
        public double? rotate { get; set; }
        public int? flip { get; set; }
        public bool? isDigitalBackground { get; set; }
        public int? digitalBackgroundId { get; set; }
    }

    public class LayoutParameters
    {
        public int? id { get; set; }
        public int? frameId { get; set; }
        public string? code { get; set; }
        public string? name { get; set; }
        public string? image { get; set; }
        public string? imageTemplate { get; set; }
        public int? width { get; set; }
        public int? height { get; set; }
        public int? numberOfPicture { get; set; }
        public int? numberOfTakePicture { get; set; }
        public int? numberOfReTakePicture { get; set; }
        public decimal? price { get; set; }
        public List<LayoutPrice>? prices { get; set; }
        public int? ratio { get; set; }
        public int? ratioX { get; set; }
        public int? ratioY { get; set; }
        public List<LayoutPicture>? pictures { get; set; }
        public LayoutQRCode? QRCode { get; set; }
        public LayoutDate? layoutDate { get; set; }
    }

    public class LayoutPrice
    {
        public int? numberOfPicture { get; set; }
        public decimal? price { get; set; }
    }

    public class LayoutPicture
    {
        public int? id { get; set; }
        public int? width { get; set; }
        public int? height { get; set; }
        public int? x { get; set; }
        public int? y { get; set; }
        public int? orderNo { get; set; }
        public bool? isMiniPicture { get; set; }
        public int? pictureTarget { get; set; }
    }

    public class LayoutQRCode
    {
        public int? width { get; set; }
        public int? height { get; set; }
        public int? x { get; set; }
        public int? y { get; set; }
    }

    public class LayoutDate
    {
        public int? width { get; set; }
        public int? height { get; set; }
        public int? x { get; set; }
        public int? y { get; set; }
    }
}