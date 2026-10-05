// Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
// See the LICENCE file in the repository root for full licence text.

using System.Linq;
using osu.Framework.Allocation;
using osu.Framework.Graphics;
using osu.Framework.Input.Bindings;
using osu.Game.Database;
using osu.Game.Input.Bindings;
using osu.Game.Rulesets.Modosu.UI;
using osu.Game.Rulesets.Osu;

namespace osu.Game.Rulesets.Modosu
{
    public partial class ModosuInputManager : osu.Game.Rulesets.Osu.OsuInputManager
    {
        public ModosuInputManager(RulesetInfo ruleset)
            : base(ruleset)
        {
        }

        protected override KeyBindingContainer<OsuAction> CreateKeyBindingContainer(RulesetInfo ruleset, int variant, SimultaneousBindingMode unique)
            => new ModosuKeyBindingContainer(ruleset, variant, unique);

        protected override void LoadComplete()
        {
            base.LoadComplete();

            // Upstream's mapper casts KeyBindingContainer to its private OsuKeyBindingContainer, which fails for
            // modosu's ModosuKeyBindingContainer (InvalidCastException on touch). Swap it for the modosu-safe mapper.
            //
            // Note: RulesetInputManager forwards Children/Add/Remove to an inner Content container (parented
            // inside the KeyBindingContainer), so RemoveInternal must not be used here.
            var upstreamMapper = Children.OfType<osu.Game.Rulesets.Osu.UI.OsuTouchInputMapper>().FirstOrDefault();
            if (upstreamMapper != null)
                Remove(upstreamMapper, true);

            Add(new ModosuTouchInputMapper(this) { RelativeSizeAxes = Axes.Both });
        }

        public new bool AllowGameplayInputs
        {
            get => ((ModosuKeyBindingContainer)KeyBindingContainer).AllowGameplayInputs;
            set => ((ModosuKeyBindingContainer)KeyBindingContainer).AllowGameplayInputs = value;
        }

        private partial class ModosuKeyBindingContainer : RulesetKeyBindingContainer
        {
            private bool allowGameplayInputs = true;

            [Resolved]
            private RealmAccess realm { get; set; } = null!;

            public bool AllowGameplayInputs
            {
                get => allowGameplayInputs;
                set
                {
                    allowGameplayInputs = value;
                    ReloadMappings();
                }
            }

            public ModosuKeyBindingContainer(RulesetInfo ruleset, int variant, SimultaneousBindingMode unique)
                : base(ruleset, variant, unique)
            {
            }

            protected override void ReloadMappings(IQueryable<RealmKeyBinding> realmKeyBindings)
            {
                var osuBindings = realm.Realm.All<RealmKeyBinding>()
                    .Where(b => b.RulesetName == osu.Game.Rulesets.Osu.OsuRuleset.SHORT_NAME && b.Variant == 0);

                base.ReloadMappings(osuBindings);

                if (!AllowGameplayInputs)
                    KeyBindings = KeyBindings.Where(static b => b.GetAction<OsuAction>() == OsuAction.Smoke).ToList();
            }
        }
    }
}
