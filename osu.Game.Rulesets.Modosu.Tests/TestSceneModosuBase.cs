using osu.Framework.Allocation;
using osu.Framework.Platform;
using osu.Game.Configuration;
using osu.Game.Online.API;
using osu.Game.Rulesets.Modosu.Configuration;
using osu.Game.Tests.Visual;


namespace osu.Game.Rulesets.Modosu.Tests
{
    public abstract partial class TestSceneModosuBase : OsuTestScene
    {
        protected DummyAPIAccess dummyAPI => (DummyAPIAccess)API;

        protected ModosuRuleset ruleset = null!;
        protected LocalUserManager localUserManager = null!;
        protected ModosuRulesetConfigManager config = null!;

        [Resolved]
        private GameHost gameHost { get; set; } = null!;

        protected override bool UseFreshStoragePerRun => true;

        protected void CaptureScreenshot(string testName)
        {
            AddStep("screenshot", () =>
            {
                var fixtureName = GetType().Name.Replace("TestScene", "");
                ScreenshotHelper.Capture(gameHost, $"{fixtureName}_{testName}");
            });
            AddWaitStep("wait for screenshot", 1);
        }

        [BackgroundDependencyLoader]
        private void load(IAPIProvider api)
        {
            ruleset = new ModosuRuleset();
            Dependencies.Cache(Realm);

            // ModosuRulesetConfigManager must be constructed on the update thread (it loads from the realm in its ctor).
            // Under dotnet test the game host already caches one, so reuse it when present.
            Scheduler.Add(() =>
            {
                config = (ModosuRulesetConfigManager?)Dependencies.Get(typeof(ModosuRulesetConfigManager))
                      ?? new ModosuRulesetConfigManager(new SettingsStore(Realm), ruleset.RulesetInfo);
                Dependencies.Cache(localUserManager = new LocalUserManager(ruleset, Realm, config, api));
            });

            Realm.Write(r =>
            {
                if (r.Find<RulesetInfo>(ruleset.RulesetInfo.ShortName) == null)
                    r.Add(ruleset.RulesetInfo.Clone());
            });
        }
    }
}
