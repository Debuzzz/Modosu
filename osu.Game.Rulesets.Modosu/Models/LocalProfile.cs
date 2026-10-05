namespace osu.Game.Rulesets.Modosu.Models
{
    public class LocalProfile
    {
        public string Name { get; set; } = "";

        public bool IsActive { get; set; }

        /// <summary>
        /// Number of recorded plays, persisted in the profile JSON.
        /// </summary>
        public int PlayCount { get; set; }
    }
}
