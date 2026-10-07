using System;
using System.Linq;
using osu.Game.Beatmaps;
using osu.Game.Configuration;
using osu.Game.Rulesets.Mods;
using osu.Game.Scoring;
using Realms;

namespace osu.Game.Rulesets.Modosu.Database
{
    /// <summary>Keep local data accessible when moving from the original practice identity.</summary>
    public static class LegacyPracticeDataMigration
    {
        public const string LegacyShortName = "mosu";

        public static string ResolveShortName(string name) => name == LegacyShortName ? ModosuRuleset.SHORT_NAME : name;

        public static SettingsStore? Prepare(SettingsStore? store, RulesetInfo ruleset)
        {
            if (store == null)
                return null;

            store.Realm.Write(realm =>
            {
                var legacy = realm.Find<RulesetInfo>(LegacyShortName);
                var settings = realm.All<RealmRulesetSetting>().Where(s => s.RulesetName == LegacyShortName).ToArray();
                if (legacy == null && settings.Length == 0)
                    return;
                if (legacy != null && legacy.OnlineID != -1)
                    throw new InvalidOperationException("Unexpected online identity in legacy practice data. Migration stopped.");

                var current = realm.Find<RulesetInfo>(ruleset.ShortName) ?? realm.Add(ruleset.Clone());
                if (current.OnlineID != -1)
                    throw new InvalidOperationException("Practice data must keep its custom offline identity.");

                // Leave legacy settings intact and never overwrite an existing Modosu setting.
                foreach (var setting in settings)
                {
                    if (!realm.All<RealmRulesetSetting>().Any(s => s.RulesetName == ruleset.ShortName && s.Variant == setting.Variant && s.Key == setting.Key))
                        realm.Add(new RealmRulesetSetting { RulesetName = ruleset.ShortName, Variant = setting.Variant, Key = setting.Key, Value = setting.Value });
                }

                if (legacy == null)
                    return;
                foreach (var score in realm.All<ScoreInfo>().Filter("Ruleset.ShortName == $0", LegacyShortName).ToArray())
                    score.Ruleset = current;
                foreach (var preset in realm.All<ModPreset>().Filter("Ruleset.ShortName == $0", LegacyShortName).ToArray())
                    preset.Ruleset = current;
                foreach (var beatmap in realm.All<BeatmapInfo>().Filter("Ruleset.ShortName == $0", LegacyShortName).ToArray())
                    beatmap.Ruleset = current;
                // Scores keep their IDs, hashes, users and attached replay files.
            });
            return store;
        }
    }
}
