using System;
using System.Threading.Tasks;
using osu.Framework.Allocation;
using osu.Game.Beatmaps;
using osu.Game.Online.API;
using osu.Game.Rulesets.Modosu.Configuration;

namespace osu.Game.Rulesets.Modosu.Database
{
    public partial class BackgroundCollectionImportProcessor : BackgroundEmbeddedImportProcessor
    {
        [Resolved]
        private IAPIProvider api { get; set; } = null!;

        [Resolved]
        private BeatmapManager beatmapManager { get; set; } = null!;

        public BackgroundCollectionImportProcessor()
            : base("osu.Game.Rulesets.Modosu.example_collections.json", "collections",
                   c => c.Get<bool>(ModosuRulesetSetting.CollectionsImported),
                   c => c.SetValue(ModosuRulesetSetting.CollectionsImported, true))
        {
        }

        protected override Task Import(string json, Action<Action> schedule)
            => new CollectionImportProcessor(realm, notifications, api, beatmapManager, schedule).Import(json);
    }
}
