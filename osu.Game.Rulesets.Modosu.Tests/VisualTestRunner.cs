using System;
using System.Linq;
using osu.Framework;
using osu.Framework.Platform;
using osu.Game.Tests;

namespace osu.Game.Rulesets.Modosu.Tests
{
    public static class VisualTestRunner
    {
        [STAThread]
        public static int Main(string[] args)
        {
            Environment.SetEnvironmentVariable("OSU_DISABLE_ERROR_REPORTING", "1");

            bool auto = args.Contains("--auto");
            string? filter = null;
            int filterIndex = Array.IndexOf(args, "--filter");
            if (filterIndex >= 0 && filterIndex + 1 < args.Length)
                filter = args[filterIndex + 1];

            // Framework caches (including fonts) must also stay outside the user's osu! data.
            using (DesktopGameHost host = Host.GetSuitableDesktopHost(@"modosu-offline-tests", new HostOptions { PortableInstallation = true }))
            {
                if (auto)
                    host.Run(new AutomatedVisualTestGame(filter));
                else
                    host.Run(new OsuTestBrowser());
                return Environment.ExitCode;
            }
        }
    }
}
