
using System.Linq;
using osu.Framework.Graphics.Sprites;
using osu.Framework.Localisation;
using osu.Game.Graphics;
using osu.Game.Rulesets.Mods;
using osu.Game.Rulesets.Osu.Objects;
using osu.Game.Rulesets.UI;

namespace osu.Game.Rulesets.MOsu.Mods
{
    public class OsuModMetronome : Mod, IApplicableToDrawableRuleset<OsuHitObject>
    {
        public override string Name => "Metronome";

        public override LocalisableString Description => "Plays a metronome tick on every beat, with a higher-pitched accent on the downbeat.";

        public override string Acronym => "ME";

        public override ModType Type => ModType.Fun;

        public override IconUsage? Icon => OsuIcon.Metronome;

        public void ApplyToDrawableRuleset(DrawableRuleset<OsuHitObject> drawableRuleset)
        {
            double firstHitTime = drawableRuleset.Beatmap.HitObjects.FirstOrDefault()?.StartTime ?? 0;
            drawableRuleset.Overlays.Add(new MetronomeBeat(firstHitTime));
        }
    }
}
