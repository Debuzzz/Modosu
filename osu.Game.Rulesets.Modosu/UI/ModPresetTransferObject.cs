
namespace osu.Game.Rulesets.Modosu.UI
{
    // A clean class used purely for saving/loading to JSON
    public class ModPresetTransferObject
    {
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string ModsJson { get; set; } = string.Empty;

        /// <summary>
        /// The ruleset this preset belongs to. Empty for files written before this field existed (all modosu).
        /// </summary>
        public string RulesetShortName { get; set; } = string.Empty;
    }
}
