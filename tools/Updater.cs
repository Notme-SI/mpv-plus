using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("mpv+ Updates")]
[assembly: AssemblyVersion("1.1.3.0")]

internal static class UpdateData {
    internal static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 4194304 };
    internal const string Repository = "https://api.github.com/repos/Notme-SI/mpv-plus";
    internal static string Text(IDictionary<string, object> data, string key) {
        object value; return data != null && data.TryGetValue(key, out value) ? Convert.ToString(value) : "";
    }
    internal static Dictionary<string, object> Parse(string text) { return Json.Deserialize<Dictionary<string, object>>(text); }
    internal static Version VersionOf(string text) {
        Version version;
        if (!Regex.IsMatch(text ?? "", @"^v?\d+\.\d+\.\d+$") || !Version.TryParse(text.TrimStart('v'), out version)) throw new InvalidDataException("Invalid release version");
        return version;
    }
    internal static Dictionary<string, object> SetupAsset(Dictionary<string, object> release) {
        VersionOf(Text(release, "tag_name"));
        if (Text(release, "draft").Equals("True", StringComparison.OrdinalIgnoreCase) || Text(release, "prerelease").Equals("True", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Expected a stable release");
        string version = Text(release, "tag_name").TrimStart('v');
        Dictionary<string, object> found = null;
        foreach (object item in (IEnumerable)release["assets"]) {
            var asset = item as Dictionary<string, object>;
            if (Text(asset, "name") != "mpv+-" + version + "-Setup.exe") continue;
            if (found != null) throw new InvalidDataException("Ambiguous installer asset");
            found = asset;
        }
        if (found == null) throw new InvalidDataException("Installer is missing from the release");
        Uri url;
        if (!Uri.TryCreate(Text(found, "browser_download_url"), UriKind.Absolute, out url) || url.Scheme != "https" || url.Host != "github.com" || !url.AbsolutePath.StartsWith("/Notme-SI/mpv-plus/releases/download/", StringComparison.Ordinal)) throw new InvalidDataException("Unexpected installer download address");
        if (!Regex.IsMatch(Text(found, "digest"), "^sha256:[a-f0-9]{64}$")) throw new InvalidDataException("Installer has no SHA-256 checksum");
        return found;
    }
    internal static string Quote(string value) {
        var result = new StringBuilder("\""); int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes); slashes = 0; result.Append(c);
        }
        return result.Append('\\', slashes * 2).Append('"').ToString();
    }
    internal static void VerifyHash(string path, string digest) {
        using (var sha = SHA256.Create()) using (var file = File.OpenRead(path)) {
            string hash = BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
            if ("sha256:" + hash != digest) throw new InvalidDataException("Installer checksum mismatch");
        }
    }
}

internal sealed class UpdateProgress : Control {
    internal int Value;
    internal bool Active;
    private int position;
    private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer { Interval = 30 };
    internal UpdateProgress() {
        DoubleBuffered = true; Height = 4;
        timer.Tick += delegate { position = (position + 8) % Math.Max(1, Width + 160); if (Active && Value < 0) Invalidate(); };
        timer.Start();
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(Color.FromArgb(49, 49, 61));
        using (var brush = new SolidBrush(Color.FromArgb(165, 139, 250))) {
            if (Active && Value < 0) e.Graphics.FillRectangle(brush, position - 160, 0, 160, Height);
            else e.Graphics.FillRectangle(brush, 0, 0, Width * Math.Max(0, Math.Min(100, Value)) / 100, Height);
        }
    }
    protected override void Dispose(bool disposing) { if (disposing) timer.Dispose(); base.Dispose(disposing); }
}

internal sealed class UpdateButton : Button {
    private bool hover;
    internal UpdateButton() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true); }
    protected override void OnMouseEnter(EventArgs e) { hover=true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover=false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(Enabled ? (hover ? ControlPaint.Light(BackColor, .12f) : BackColor) : Color.FromArgb(40,40,50));
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, Enabled ? ForeColor : Color.FromArgb(121,121,140), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        if(Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle,-4,-4));
    }
}

internal sealed class UpdateWindow : Form {
    private readonly string root, config, work, log;
    private readonly bool english;
    private readonly int playerPid;
    private readonly Color surface = Color.FromArgb(29, 29, 37), muted = Color.FromArgb(163, 163, 181), accent = Color.FromArgb(165, 139, 250);
    private readonly Label subtitle = new Label(), status = new Label(), hint = new Label(), playerInfo = new Label();
    private readonly Button playerTab = new UpdateButton(), componentsTab = new UpdateButton(), check = new UpdateButton(), install = new UpdateButton(), close = new UpdateButton(), details = new UpdateButton();
    private readonly Panel content = new Panel(), playerPanel = new Panel();
    private readonly DataGridView rows = new DataGridView();
    private readonly RichTextBox notes = new RichTextBox();
    private readonly UpdateProgress progress = new UpdateProgress();
    private readonly System.Windows.Forms.Timer poll = new System.Windows.Forms.Timer { Interval = 400 };
    private Process backend;
    private volatile bool cancelled;
    private bool busy, installing, components, restart;
    private string version;
    private volatile string progressFile;
    private Dictionary<string, object> release, asset;
    private int available;

    internal UpdateWindow(string directory, int pid, bool en, bool componentView) {
        root = Path.GetFullPath(directory); config = Path.Combine(root, "portable_config"); playerPid = pid; english = en;
        if (!File.Exists(Path.Combine(root,"mpv+.exe"))) throw new FileNotFoundException(T("Не найдена полная сборка mpv+. Перенесите всю папку плеера.", "The full mpv+ package is missing. Move the entire player folder."));
        work = Path.Combine(Path.GetTempPath(), "mpv-plus-update-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(work);
        string logs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "mpv-plus"); Directory.CreateDirectory(logs); log = Path.Combine(logs, "update.log");
        var manifest = UpdateData.Parse(File.ReadAllText(Path.Combine(config, "maintenance/manifest.json"), Encoding.UTF8));
        version = UpdateData.Text(manifest, "buildVersion"); UpdateData.VersionOf(version);
        Text = T("mpv+ — Обновления", "mpv+ — Updates"); BackColor = Color.FromArgb(21, 21, 28); ForeColor = Color.FromArgb(239, 239, 246);
        Font = new Font("Segoe UI", 10); AutoScaleMode = AutoScaleMode.Dpi; AutoScaleDimensions = new SizeF(96, 96);
        ClientSize = new Size(820, 700); MinimumSize = new Size(740, 620); StartPosition = FormStartPosition.CenterScreen;
        try { Icon = new Icon(Path.Combine(config, "assets/mpv-monochrome.ico")); } catch { }
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(28, 24, 28, 22), ColumnCount = 1, RowCount = 5 };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 86)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 86)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        Controls.Add(layout);
        var heading = new Panel { Dock = DockStyle.Fill };
        var title = new Label { Text = T("Обновления", "Updates"), Font = new Font("Segoe UI Semibold", 24), AutoSize = true, Location = new Point(0, -3) };
        subtitle.Text = T("mpv+ ", "mpv+ ") + version + T("  ·  Плеер и компоненты в одном месте", "  ·  Your player and components in one place"); subtitle.ForeColor = muted; subtitle.AutoSize = true; subtitle.Location = new Point(2, 48);
        heading.Controls.Add(title); heading.Controls.Add(subtitle); layout.Controls.Add(heading, 0, 0);
        var tabs = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        StyleButton(playerTab, T("Плеер mpv+", "mpv+ player"), 150); StyleButton(componentsTab, T("Компоненты", "Components"), 150);
        tabs.Controls.Add(playerTab); tabs.Controls.Add(componentsTab); layout.Controls.Add(tabs, 0, 1);
        content.Dock = DockStyle.Fill; content.BackColor = surface; content.Padding = new Padding(18); layout.Controls.Add(content, 0, 2);
        playerPanel.Dock = DockStyle.Fill;
        playerInfo.Dock = DockStyle.Top; playerInfo.Height = 46; playerInfo.Font = new Font("Segoe UI Semibold", 12); playerInfo.Text = T("Установлена версия ", "Installed version ") + version;
        notes.Dock = DockStyle.Fill; notes.ReadOnly = true; notes.BorderStyle = BorderStyle.None; notes.BackColor = surface; notes.ForeColor = muted; notes.Font = new Font("Segoe UI", 10); notes.DetectUrls = false;
        notes.Text = T("Проверим новый выпуск mpv+ на GitHub.\n\nОбновление всего плеера включает интерфейс, скрипты и компоненты сборки. Личные настройки сохраняются.", "Check GitHub for a new mpv+ release.\n\nA player update includes the interface, scripts and bundled components. Your personal settings are preserved.");
        playerPanel.Controls.Add(notes); playerPanel.Controls.Add(playerInfo);
        rows.Dock = DockStyle.Fill; rows.BackgroundColor = surface; rows.BorderStyle = BorderStyle.None; rows.ReadOnly = true; rows.AllowUserToAddRows = false; rows.AllowUserToDeleteRows = false; rows.AllowUserToResizeRows = false; rows.RowHeadersVisible = false;
        rows.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill; rows.SelectionMode = DataGridViewSelectionMode.FullRowSelect; rows.MultiSelect = false; rows.EnableHeadersVisualStyles = false; rows.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal; rows.GridColor = Color.FromArgb(47, 47, 59);
        rows.ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle { BackColor = surface, ForeColor = muted, Font = new Font("Segoe UI", 9), Padding = new Padding(0, 7, 0, 7), SelectionBackColor = surface };
        rows.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None; rows.ColumnHeadersHeight = 38;
        rows.DefaultCellStyle = new DataGridViewCellStyle { BackColor = surface, ForeColor = ForeColor, SelectionBackColor = Color.FromArgb(45, 42, 61), SelectionForeColor = ForeColor, Padding = new Padding(0, 7, 0, 7) };
        rows.RowTemplate.Height = 31; rows.Columns.Add("name", T("Компонент", "Component")); rows.Columns.Add("status", T("Состояние", "Status")); rows.Columns[0].FillWeight = 35; rows.Columns[1].FillWeight = 65;
        var statePanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(0, 15, 0, 0) };
        status.Location = new Point(0, 15); status.Size = new Size(740, 23); status.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;
        hint.Location = new Point(0, 41); hint.Size = new Size(740, 20); hint.ForeColor = muted; hint.Font = new Font("Segoe UI", 9); hint.Anchor = status.Anchor; hint.AutoEllipsis = true;
        hint.Text = T("Плеер закроется только при установке. Настройки сохранятся.", "The player closes only when installing. Your settings are preserved.");
        progress.Dock = DockStyle.Bottom; statePanel.Controls.Add(status); statePanel.Controls.Add(hint); statePanel.Controls.Add(progress); layout.Controls.Add(statePanel, 0, 3);
        var actions = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, RowCount = 1, Padding = new Padding(0, 7, 0, 0) };
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); actions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 142)); actions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 186)); actions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 105));
        StyleButton(details, T("Журнал", "View log"), 105); StyleButton(check, T("Проверить", "Check again"), 134); StyleButton(install, T("Установить", "Install update"), 178); StyleButton(close, T("Закрыть", "Close"), 97);
        details.ForeColor = muted; install.BackColor = Color.FromArgb(126, 88, 214); install.ForeColor = Color.White;
        actions.Controls.Add(details, 0, 0); actions.Controls.Add(check, 1, 0); actions.Controls.Add(install, 2, 0); actions.Controls.Add(close, 3, 0); layout.Controls.Add(actions, 0, 4);
        details.Click += delegate { if (File.Exists(log)) Process.Start(new ProcessStartInfo("notepad.exe", UpdateData.Quote(log)) { UseShellExecute = false }); };
        check.Click += delegate { CheckUpdates(); }; install.Click += delegate { InstallUpdates(); }; close.Click += delegate { if (busy && !installing) CancelCheck(); else if (!busy) Close(); };
        playerTab.Click += delegate { if (components) { SelectView(false); CheckUpdates(); } }; componentsTab.Click += delegate { if (!components) { SelectView(true); CheckUpdates(); } };
        FormClosing += delegate(object sender, FormClosingEventArgs e) { if (busy) { e.Cancel = true; if (!installing) CancelCheck(); } };
        poll.Tick += delegate { ReadProgress(); }; poll.Start();
        components = componentView; SelectView(componentView); Shown += delegate { CheckUpdates(); };
    }
    private string T(string ru, string en) { return english ? en : ru; }
    private void CancelCheck() { cancelled=true; try { var child=backend; if(child!=null && !child.HasExited) child.Kill(); } catch(InvalidOperationException) { } }
    private void StyleButton(Button button, string text, int width) {
        button.Text = text; button.Size = new Size(width, 35); button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderSize = 0; button.BackColor = surface; button.ForeColor = ForeColor; button.Cursor = Cursors.Hand; button.Margin = new Padding(0, 0, 8, 0); button.UseVisualStyleBackColor = false;
    }
    private void UI(Action action) { if (!IsDisposed && IsHandleCreated) BeginInvoke(action); }
    private void SelectView(bool value) {
        if (busy) return; components = value; content.Controls.Clear(); content.Controls.Add(value ? (Control)rows : playerPanel);
        playerTab.ForeColor = value ? muted : accent; componentsTab.ForeColor = value ? accent : muted;
        status.Text = T("Готово к проверке", "Ready to check"); install.Enabled = false;
    }
    private void SetBusy(bool value, bool isInstall) {
        busy = value; installing = isInstall; check.Enabled = !value; playerTab.Enabled = !value; componentsTab.Enabled = !value; install.Enabled = !value && (components ? available > 0 : asset != null);
        close.Enabled = !isInstall; close.Text = value ? T("Отмена", "Cancel") : T("Закрыть", "Close"); progress.Active = value; progress.Value = value ? -1 : 100; progress.Invalidate();
    }
    private void Run(Action action, Action done, bool isInstall) {
        cancelled = false; SetBusy(true, isInstall);
        ThreadPool.QueueUserWorkItem(delegate {
            Exception error = null;
            try { action(); if (cancelled) throw new OperationCanceledException(); } catch (Exception ex) { error = ex; try { File.AppendAllText(log, DateTime.Now.ToString("s") + " " + ex + Environment.NewLine); } catch { } }
            UI(delegate { SetBusy(false, false); progressFile = null; if (error == null) done(); else { status.Text = cancelled ? T("Проверка отменена", "Check cancelled") : T("Не удалось завершить обновление", "Could not complete the update"); hint.Text = cancelled ? "" : error.Message; hint.ForeColor = Color.FromArgb(245, 174, 151); progress.Value = 0; progress.Invalidate(); } });
        });
    }
    private void CheckUpdates() {
        if (busy) return; install.Enabled = false; available = 0; asset = null; status.Text = T("Проверяем обновления…", "Checking for updates…"); hint.ForeColor = muted; hint.Text = T("Получаем актуальные версии с GitHub", "Getting current versions from GitHub");
        if (components) {
            Run(delegate { RunBackend("Check"); }, delegate {
                var report = UpdateData.Parse(File.ReadAllText(Path.Combine(work, "report.json"), Encoding.UTF8)); rows.Rows.Clear();
                foreach (object item in (IEnumerable)report["components"]) {
                    var row = (Dictionary<string, object>)item; string state = UpdateData.Text(row, "status"); int index = rows.Rows.Add(UpdateData.Text(row, "name"), TranslateStatus(state));
                    rows.Rows[index].Cells[1].Style.ForeColor = state == "Актуально" ? Color.FromArgb(142, 206, 168) : state == "Есть обновление" ? accent : Color.FromArgb(231, 184, 126);
                }
                available = Convert.ToInt32(report["available"]); install.Enabled = available > 0; rows.ClearSelection();
                status.Text = available > 0 ? T("Доступно обновлений: ", "Updates available: ") + available : T("Все компоненты актуальны", "All components are up to date");
                if (UpdateData.Text(report, "failed").Equals("True", StringComparison.OrdinalIgnoreCase)) status.Text = T("Часть компонентов не удалось проверить", "Some components could not be checked");
                hint.Text = T("Локальные изменения защищены. Перед установкой проверяется совместимость.", "Local changes are protected. Compatibility is checked before installation.");
            }, false);
        } else {
            Run(delegate {
                var request = (HttpWebRequest)WebRequest.Create(UpdateData.Repository + "/releases/latest"); request.UserAgent = "mpv-plus-updater"; request.Timeout = 30000;
                using (var response = request.GetResponse()) using (var reader = new StreamReader(response.GetResponseStream())) release = UpdateData.Parse(reader.ReadToEnd());
                if (UpdateData.VersionOf(UpdateData.Text(release, "tag_name")) > UpdateData.VersionOf(version)) asset = UpdateData.SetupAsset(release);
            }, delegate {
                string latest = UpdateData.Text(release, "tag_name").TrimStart('v');
                playerInfo.Text = T("Установлена ", "Installed ") + version + T("   ·   На GitHub ", "   ·   On GitHub ") + latest;
                string body = UpdateData.Text(release, "body"); int separator = body.IndexOf("\n---", StringComparison.Ordinal); if (separator >= 0) body = body.Substring(0, separator);
                body = Regex.Replace(Regex.Replace(body, @"\[([^\]]+)\]\([^\)]+\)", "$1"), @"(?m)^#{1,6}\s*|\*\*|<[^>]+>|[\u2600-\u27BF\uFE0F]|[\uD800-\uDBFF][\uDC00-\uDFFF]", "").Trim();
                notes.Text = Regex.Replace(Regex.Replace(body, @"^Windows", T("Что нового", "What's new")), @"(?m)^-\s*", "\n• ").Trim();
                status.Text = asset == null ? T("Установлена актуальная версия mpv+", "mpv+ is up to date") : T("Доступна версия mpv+ ", "mpv+ update available: ") + latest;
                hint.Text = asset == null ? T("Можно отдельно проверить обновления компонентов.", "You can also check individual component updates.") : T("Загрузим проверенный установщик. Настройки сохранятся.", "Download a verified installer. Your settings will be preserved."); install.Enabled = asset != null;
            }, false);
        }
    }
    private string TranslateStatus(string state) {
        if (!english) return state;
        if (state == "Актуально") return "Up to date"; if (state == "Есть обновление") return "Update available";
        if (state.StartsWith("Локально изменён")) return "Local changes preserved"; return "Could not check";
    }
    private void RunBackend(string mode) {
        progressFile = Path.Combine(work, "progress.json"); if (File.Exists(progressFile)) File.Delete(progressFile);
        string script = Path.Combine(config, "maintenance/Update-MPV.ps1");
        var start = new ProcessStartInfo("powershell.exe", "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " + UpdateData.Quote(script) + " -Mode " + mode + " -ReportPath " + UpdateData.Quote(Path.Combine(work, "report.json")) + " -ProgressPath " + UpdateData.Quote(progressFile));
        start.UseShellExecute = false; start.CreateNoWindow = true; start.WindowStyle = ProcessWindowStyle.Hidden; start.RedirectStandardOutput = true; start.RedirectStandardError = true; start.StandardOutputEncoding = Encoding.UTF8; start.StandardErrorEncoding = Encoding.UTF8; start.WorkingDirectory = root;
        var output = new StringBuilder(); var sync = new object();
        using (var child = new Process { StartInfo = start }) {
            backend = child;
            DataReceivedEventHandler receive = delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) lock (sync) output.AppendLine(e.Data); };
            child.OutputDataReceived += receive; child.ErrorDataReceived += receive;
            child.Start(); child.BeginOutputReadLine(); child.BeginErrorReadLine();
            if (!child.WaitForExit(1200000)) { child.Kill(); throw new IOException(T("Превышено время ожидания. Подробности в журнале.", "The operation timed out. See the log for details.")); }
            child.WaitForExit(); lock (sync) File.WriteAllText(log, output.ToString(), Encoding.UTF8);
            backend = null;
            if (cancelled) throw new OperationCanceledException();
            if (child.ExitCode != 0 && !(mode == "Check" && File.Exists(Path.Combine(work,"report.json")))) throw new IOException(T("Откройте журнал, чтобы узнать причину. Установленные файлы защищены проверкой и откатом.", "Open the log for details. Validation and rollback protect installed files."));
        }
    }
    private void ReadProgress() {
        if (!busy || progressFile == null) return;
        try {
            var data = UpdateData.Parse(File.ReadAllText(progressFile, Encoding.UTF8)); string phase = UpdateData.Text(data, "stage"), component = UpdateData.Text(data, "component");
            string message = phase == "checking" ? T("Проверяем версии", "Checking versions") : phase == "preparing" ? T("Загружаем и подготавливаем", "Downloading and preparing") : phase == "validating" ? T("Проверяем совместимость и запуск", "Checking compatibility and startup") : phase == "installing" ? T("Устанавливаем обновления", "Installing updates") : phase == "complete" ? T("Готово", "Done") : "";
            if (message != "") status.Text = message + (component == "" ? "…" : ": " + component);
        } catch { }
    }
    private void ClosePlayer() {
        string expected = Path.GetFullPath(Path.Combine(root, "mpv+.exe"));
        foreach(string name in new[]{"mpv+","mpv"}) foreach(Process player in Process.GetProcessesByName(name)) using(player) {
            string actual;
            try { actual=Path.GetFullPath(player.MainModule.FileName); } catch { if(player.Id==playerPid) throw; else continue; }
            if(!String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase)) continue;
            if(!player.CloseMainWindow() || !player.WaitForExit(15000)) throw new IOException(T("Закройте обновляемую копию плеера и повторите установку.", "Close this player and try installing again."));
            restart=true;
        }
    }
    private void RestartPlayer() {
        if (!restart) return; restart = false;
        Process.Start(new ProcessStartInfo(Path.Combine(root, "mpv+.exe")) { WorkingDirectory = root, UseShellExecute = false });
    }
    private void InstallUpdates() {
        if (busy) return; hint.Text = T("Личные настройки сохраняются.", "Your personal settings are preserved.");
        if (components && available > 0) {
            status.Text = T("Подготавливаем установку…", "Preparing installation…");
            Run(delegate { try { ClosePlayer(); RunBackend("Update"); } finally { RestartPlayer(); } }, delegate {
                available=0; install.Enabled=false;
                foreach(DataGridViewRow row in rows.Rows) if(Convert.ToString(row.Cells[1].Value)==T("Есть обновление","Update available")) { row.Cells[1].Value=T("Обновлено","Updated"); row.Cells[1].Style.ForeColor=Color.FromArgb(142,206,168); }
                status.Text=T("Компоненты обновлены","Components updated"); hint.Text=T("Проверка совместимости пройдена. Можно продолжать просмотр.","Compatibility checks passed. You can continue watching.");
            }, true);
        } else if (!components && asset != null) {
            string installer = Path.Combine(work, "mpv+-Setup.exe");
            Run(delegate {
                UI(delegate { status.Text = T("Загружаем установщик…", "Downloading installer…"); });
                var request = (HttpWebRequest)WebRequest.Create(UpdateData.Text(asset, "browser_download_url")); request.UserAgent = "mpv-plus-updater"; request.Timeout = 180000; request.ReadWriteTimeout = 30000;
                using (var response = request.GetResponse()) using (var input = response.GetResponseStream()) using (var output = File.Create(installer)) {
                    if (response.ContentLength > 1073741824) throw new InvalidDataException("Installer is too large");
                    var buffer = new byte[65536]; long total = 0; int count;
                    while ((count = input.Read(buffer, 0, buffer.Length)) != 0) {
                        if (cancelled) throw new OperationCanceledException(); total += count; if (total > 1073741824) throw new InvalidDataException("Installer is too large"); output.Write(buffer, 0, count);
                        int percent = response.ContentLength > 0 ? (int)(total * 100 / response.ContentLength) : -1;
                        UI(delegate { progress.Value = percent; progress.Invalidate(); hint.Text = (total / 1048576) + T(" МБ загружено", " MB downloaded"); });
                    }
                }
                try { UpdateData.VerifyHash(installer, UpdateData.Text(asset, "digest")); }
                catch (InvalidDataException) { throw new InvalidDataException(T("Контрольная сумма установщика не совпала. Установка отменена.", "Installer checksum mismatch. Installation cancelled.")); }
                try { ClosePlayer(); } catch { RestartPlayer(); throw; }
            }, delegate {
                try { Process.Start(new ProcessStartInfo(installer, "/DIR=" + UpdateData.Quote(root) + " /NOCLOSEAPPLICATIONS /NORESTARTAPPLICATIONS") { UseShellExecute = true }); Close(); }
                catch (Exception ex) { RestartPlayer(); status.Text = T("Не удалось открыть установщик", "Could not open installer"); hint.Text = ex.Message; }
            }, true);
        }
    }
    protected override void Dispose(bool disposing) { if (disposing) poll.Dispose(); base.Dispose(disposing); }
}

internal static class MpvUpdater {
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
    [STAThread] public static int Main(string[] args) {
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false); SetProcessDPIAware();
        string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "../..")); bool english = false, components = false; int pid = 0;
        for (int i = 0; i < args.Length; i++) {
            if (args[i] == "--root" && i + 1 < args.Length) root = args[++i];
            else if (args[i] == "--pid" && i + 1 < args.Length) Int32.TryParse(args[++i], out pid);
            else if (args[i] == "--language" && i + 1 < args.Length) english = args[++i] == "en";
            else if (args[i] == "--view" && i + 1 < args.Length) components = args[++i] == "components";
        }
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        try {
            string key;
            using(var sha=SHA256.Create()) key=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(root).TrimEnd('\\','/').ToLowerInvariant()))).Replace("-","");
            using(var gate=new Mutex(false,"Local\\mpv-plus-updates-"+key)) {
                bool acquired;
                try { acquired=gate.WaitOne(0); } catch(AbandonedMutexException) { acquired=true; }
                if(!acquired) { MessageBox.Show(english ? "The update window for this player is already open." : "Окно обновлений этого плеера уже открыто.","mpv+",MessageBoxButtons.OK,MessageBoxIcon.Information); return 0; }
                try { Application.Run(new UpdateWindow(root, pid, english, components)); } finally { gate.ReleaseMutex(); }
            }
            return 0;
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, english ? "mpv+ — Updates" : "mpv+ — Обновления", MessageBoxButtons.OK, MessageBoxIcon.Error); return 1; }
    }
}
