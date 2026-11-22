using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("EcoFlow Widget")]
[assembly: AssemblyDescription("EcoFlow Widget desktop launcher")]
[assembly: AssemblyProduct("EcoFlow Widget")]
[assembly: AssemblyCompany("Personal tools")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(directory, "widget.ps1");
        bool hidden = Array.Exists(args, delegate(string arg) {
            return string.Equals(arg, "--hidden", StringComparison.OrdinalIgnoreCase);
        });
        if (!File.Exists(script))
        {
            MessageBox.Show("Не найден widget.ps1. Оставь запускатель в папке с виджетом.",
                            "EcoFlow Widget", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
        try
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                                         @"System32\WindowsPowerShell\v1.0\powershell.exe");
            info.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \""
                             + script + "\"" + (hidden ? " -StartHidden" : "");
            info.WorkingDirectory = directory;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.WindowStyle = ProcessWindowStyle.Hidden;
            using (Process process = Process.Start(info)) { }
            return 0;
        }
        catch
        {
            MessageBox.Show("Не удалось запустить виджет. Проверь, что папка доступна.",
                            "EcoFlow Widget", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
