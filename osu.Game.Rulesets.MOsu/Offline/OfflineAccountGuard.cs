using System;
using osu.Framework.Bindables;
using osu.Game.Online.API;

namespace osu.Game.Rulesets.MOsu.Offline
{
    /// <summary>
    /// Defence in depth only: the Windows manager must block networking before loading this DLL.
    /// API callbacks can happen after a request has already started; this is not a network sandbox.
    /// </summary>
    public sealed class OfflineAccountGuard : IDisposable
    {
        private readonly IAPIProvider api;
        private readonly Action<Action> schedule;
        private readonly IBindable<APIState> state;
        private bool disposed;
        private bool loggingOut;

        public OfflineAccountGuard(IAPIProvider api, Action<Action> schedule)
        {
            this.api = api;
            this.schedule = schedule;
            state = api.State.GetBoundCopy();
            state.ValueChanged += onStateChanged;
            // Clear cached authentication even if the initial state is already Offline.
            logout();
        }

        private void onStateChanged(ValueChangedEvent<APIState> change)
        {
            if (change.NewValue != APIState.Offline)
                schedule(logout);
        }

        private void logout()
        {
            if (disposed || loggingOut)
                return;

            loggingOut = true;
            try { api.Logout(); }
            finally { loggingOut = false; }
        }

        public void Dispose()
        {
            disposed = true;
            state.ValueChanged -= onStateChanged;
            state.UnbindAll();
        }
    }
}
