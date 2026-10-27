# Geliştirme yardımcısı: uygulamayı belirli bir sayfada açıp YALNIZCA kendi penceresinin görüntüsünü alır.
#   powershell -File tool\shot.ps1 -Section achievements -Out $env:TEMP\a.png
param([string]$Section = 'boost', [string]$Out = "$env:TEMP\playhub.png")
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Drawing; using System.Drawing.Imaging;
public static class Cap {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  public static void Shot(IntPtr h, string path) {
    RECT r; GetWindowRect(h, out r);
    var bmp = new Bitmap(r.R-r.L, r.B-r.T); var g = Graphics.FromImage(bmp); IntPtr dc = g.GetHdc();
    PrintWindow(h, dc, 2); g.ReleaseHdc(dc); bmp.Save(path, ImageFormat.Png);
  }
}
"@ -ReferencedAssemblies System.Drawing
Get-Process play_hub -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
$exe = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\windows\x64\runner\Release\play_hub.exe'
$proc = Start-Process $exe -ArgumentList "--section=$Section" -PassThru
Start-Sleep 7
[Cap]::Shot((Get-Process -Id $proc.Id).MainWindowHandle, $Out)
Write-Host $Out
