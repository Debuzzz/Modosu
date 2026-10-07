using System;
using System.Threading.Tasks;
using osu.Framework.Allocation;
using osu.Framework.Graphics;
using osu.Framework.Graphics.Containers;
using osu.Framework.Graphics.Shapes;
using osu.Framework.Platform;
using osu.Game.Database;
using osu.Game.Graphics;
using osu.Game.Graphics.Sprites;
using osu.Game.Online.API;
using osu.Game.Rulesets.Modosu.Configuration;
using osu.Game.Rulesets.Modosu.Database;
using osu.Game.Rulesets.Modosu.Extensions;
using osu.Game.Rulesets.Modosu.Offline;
using osu.Game.Rulesets.Modosu.UI.LocalUser;
using osu.Game.Rulesets.Modosu.UI.Toolbar;
using osuTK;
using osuTK.Graphics;
using System.Linq;

namespace osu.Game.Rulesets.Modosu.UI
{
    public partial class ModosuIcon : CompositeDrawable
    {
        // CreateIcon() is called many times by core. Only the first instance should run injection.
        private static bool _injected;

        private readonly ModosuRuleset ruleset;

        [Resolved]
        private OsuGame game { get; set; } = null!;

        public ModosuIcon(ModosuRuleset ruleset)
        {
            this.ruleset = ruleset;
            Anchor = Anchor.Centre;
            Origin = Anchor.Centre;
            Size = new Vector2(32);
        }

        [BackgroundDependencyLoader]
        private void load()
        {
            InternalChildren = new Drawable[]
            {
                new Circle
                {
                    RelativeSizeAxes = Axes.Both,
                    Colour = Color4.White,
                },
                new OsuSpriteText
                {
                    Anchor = Anchor.Centre,
                    Origin = Anchor.Centre,
                    Colour = Color4.Black,
                    Text = "M",
                    Font = OsuFont.Default.With(size: 32)
                }
            };

            if (!_injected)
            {
                _injected = true;
                Schedule(LoadInjection);
            }
        }

        private void LoadInjection()
        {
            // Attach to the game, not the icon: icon instances are created/disposed repeatedly as the
            // ruleset selector re-renders (esp. on Android), which would kill a child-injected system
            // manager mid-poll. The game lives for the whole session.
            var manager = new ModosuSystemManager(ruleset);
            game.Add(new OfflineSessionGuard());
            game.Add(manager);
        }
    }

    /// <summary>
    /// Handles injection of overlays and toolbar buttons.
    /// All heavy work (Realm DB open, manager construction) runs off the game thread.
    /// </summary>
    internal partial class ModosuSystemManager : CompositeDrawable
    {
        [Resolved]
        private OsuGame game { get; set; } = null!;

        [Resolved]
        private GameHost host { get; set; } = null!;

        [Resolved]
        private RealmAccess realm { get; set; } = null!;
        [Resolved]
        private IAPIProvider api { get; set; } = null!;
        [Resolved]
        private IRulesetConfigCache configCache { get; set; } = null!;

        private readonly ModosuRuleset ruleset;

        public ModosuSystemManager(ModosuRuleset ruleset)
        {
            this.ruleset = ruleset;
            AlwaysPresent = true;
        }

        protected override void LoadComplete()
        {
            base.LoadComplete();
            Task.Run(Initialize);
        }

        private void Initialize()
        {
            // Heavy work off the game thread.
            var userManager = host.Dependencies.Get<LocalUserManager>();
            if (userManager == null)
            {
                var config = configCache.GetConfigFor(ruleset) as ModosuRulesetConfigManager ?? throw new InvalidOperationException("ModosuRulesetConfigManager not found");
                userManager = new LocalUserManager(ruleset, realm, config, api);
                host.Dependencies.Cache(userManager);
            }

            Schedule(StepUI);
        }

        private void StepUI()
        {
            var waveContainer = game.GetWaveOverlayPlacementContainer();
            var toolbarContainer = game.GetToolbarContainer();

            if (waveContainer == null || toolbarContainer == null)
            {
                Schedule(StepUI);
                return;
            }

            if (host.Dependencies.Get<BackgroundPresetImportProcessor>() == null)
            {
                var presetImporter = new BackgroundPresetImportProcessor();
                host.Dependencies.Cache(presetImporter);
                game.Add(presetImporter);
            }

            if (host.Dependencies.Get<BackgroundCollectionImportProcessor>() == null)
            {
                var collectionImporter = new BackgroundCollectionImportProcessor();
                host.Dependencies.Cache(collectionImporter);
                game.Add(collectionImporter);
            }

            // Pre-load overlay on bg thread.
            var overlay = host.Dependencies.Get<LocalUserProfileOverlay>();
            if (overlay == null)
            {
                overlay = waveContainer.Children.OfType<LocalUserProfileOverlay>().FirstOrDefault();
            }
            if (overlay == null)
            {
                overlay = new LocalUserProfileOverlay();
                LoadComponentAsync(overlay, o =>
                {
                    waveContainer.Add(o);
                    host.Dependencies.Cache(o);
                });
            }
            else
            {
                host.Dependencies.Cache(overlay);
            }

            // Add button immediately.
            if (!toolbarContainer.Children.OfType<ToolbarLocalUserButton>().Any())
                toolbarContainer.Add(new ToolbarLocalUserButton());
        }
    }
}
