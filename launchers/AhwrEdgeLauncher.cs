using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class AhwrEdgeLauncher
{
    [STAThread]
    private static int Main()
    {
#if STOP
        const string batchName = "Stop-AHWR-EDGE.bat";
#else
        const string batchName = "Start-AHWR-EDGE.bat";
#endif
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        string batchPath = Path.Combine(folder, batchName);

        if (!File.Exists(batchPath))
        {
            MessageBox.Show(batchName + " is missing. Keep the launcher in the extracted AHWR-EDGE folder.",
                "AHWR-EDGE", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = batchPath,
                WorkingDirectory = folder,
                UseShellExecute = true
            });
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show("Could not launch " + batchName + ":\n" + error.Message,
                "AHWR-EDGE", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
