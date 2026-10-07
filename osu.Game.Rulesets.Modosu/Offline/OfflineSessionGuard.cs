using System;
using System.Diagnostics;
using System.IO;
using osu.Framework.Allocation;
using osu.Framework.Graphics;
using osu.Framework.Logging;
using osu.Game.Online.API;

namespace osu.Game.Rulesets.Modosu.Offline
{
    public partial class OfflineSessionGuard : Component
    {
        private OfflineAccountGuard? guard;
        private IAPIProvider api = null!;

        [BackgroundDependencyLoader]
        private void load(IAPIProvider api)
        {
            this.api = api;
        }

        protected override void LoadComplete()
        {
            base.LoadComplete();
            guard = new OfflineAccountGuard(api, action => Schedule(action));
            Logger.Log("Modosu Offline loaded: account logged out. External firewall protection is required.");

            // A per-launch handshake confirms actual loading, rather than treating a copied DLL
            // as proof that the official client accepted it. It is not proof of firewall state.
            string? readyFile = Environment.GetEnvironmentVariable("MODOSU_OFFLINE_READY_FILE");
            string? session = Environment.GetEnvironmentVariable("MODOSU_OFFLINE_SESSION");
            if (string.IsNullOrEmpty(readyFile) || string.IsNullOrEmpty(session))
                return;

            try
            {
                File.WriteAllText(readyFile, session + "\n" + Process.GetCurrentProcess().Id);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Unable to confirm loading to the offline manager. Networking must stay blocked.");
            }
        }

        protected override void Dispose(bool isDisposing)
        {
            guard?.Dispose();
            base.Dispose(isDisposing);
        }
    }
}
