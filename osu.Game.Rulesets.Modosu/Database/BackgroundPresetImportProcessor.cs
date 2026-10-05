using System;
using System.Threading.Tasks;
using osu.Game.Rulesets.Modosu.Configuration;

namespace osu.Game.Rulesets.Modosu.Database
{
    public partial class BackgroundPresetImportProcessor : BackgroundEmbeddedImportProcessor
    {
        public BackgroundPresetImportProcessor()
            : base("osu.Game.Rulesets.Modosu.osu_mod_presets.json", "presets",
                   c => c.Get<bool>(ModosuRulesetSetting.PresetsImported),
                   c => c.SetValue(ModosuRulesetSetting.PresetsImported, true))
        {
        }

        protected override Task Import(string json, Action<Action> schedule)
            => new ModPresetImportProcessor(realm, notifications, schedule).Import(json);
    }
}
