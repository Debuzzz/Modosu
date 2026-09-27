// Regression tests for replay file persistence (the "drifting cursor / no replay when watching a
// score" bug).
//
// MOsu is a non-legacy ruleset, so Player.ImportScore never stores a replay file (legacy-only).
// DrawableMosuRuleset attaches the recorded replay to the score's database row itself. These tests
// pin the contract: whenever a play session ends in a saved score, that score must carry its
// replay file — including when the game is exited the moment the score row lands in the database,
// i.e. before any asynchronous (realm notification) attach has had a chance to run.

using System;
using System.IO;
using System.Linq;
using NUnit.Framework;
using osu.Framework.Allocation;
using osu.Framework.Extensions;
using osu.Game.Beatmaps;
using osu.Game.Beatmaps.ControlPoints;
using osu.Game.Beatmaps.Formats;
using osu.Game.Database;
using osu.Game.Rulesets;
using osu.Game.Rulesets.MOsu;
using osu.Game.Rulesets.Mods;
using osu.Game.Rulesets.Osu;
using osu.Game.Rulesets.Osu.Beatmaps;
using osu.Game.Rulesets.Osu.Objects;
using osu.Game.Rulesets.Osu.Replays;
using osu.Game.Rulesets.UI;
using osu.Game.Scoring;
using osu.Game.Screens.Ranking;
using osu.Game.Tests.Visual;
using osuTK;
using osuTK.Input;
using Realms;

namespace osu.Game.Rulesets.MOsu.Tests.Screens
{
    [TestFixture]
    public partial class TestSceneReplayPersistence : TestSceneOsuPlayer
    {
        [Resolved]
        private RealmAccess realm { get; set; } = null!;

        [Resolved]
        private ScoreManager scoreManager { get; set; } = null!;

        [Resolved]
        private BeatmapManager beatmapManager { get; set; } = null!;

        // PlayerTestScene's CreatePlayer disables the results screen, which also skips the score
        // import entirely (import only runs on the way to the results screen). Enable results so
        // the full import path executes.
        protected override TestPlayer CreatePlayer(Ruleset ruleset) => new TestPlayer(false, true, false);

        protected override bool HasCustomSteps => true;

        private Guid scoreId;
        private Guid beatmapId;
        private Live<BeatmapSetInfo>? importedSet;

        [Test]
        public void TestReplayAttachedToSavedScore()
        {
            importBeatmap();
            loadPlayer();

            AddStep("capture score id", () => scoreId = Player.Score.ScoreInfo.ID);

            addHitSteps();

            AddUntilStep("wait for pass", () => Player.GameplayState.HasPassed);
            AddAssert("replay frames recorded", () => Player.Score.Replay.Frames.Count > 0);

            AddUntilStep("wait for results screen", () => Stack.CurrentScreen is ResultsScreen);

            // The user-visible symptom: watching the score must yield a replay with frames.
            AddUntilStep("wait for replay file on score", () =>
                realm.Run(r => r.Find<ScoreInfo>(scoreId)?.Files.Any(f => f.Filename.EndsWith(".osr")) ?? false));

            AddAssert("watching the score yields a playable replay", () =>
                scoreManager.GetScore(realm.Run(r => r.Find<ScoreInfo>(scoreId)!))
                          .Replay.Frames.Count > 0);
        }

        [Test]
        public void TestReplayAttachedWhenExitingRightAfterImport()
        {
            importBeatmap();
            loadPlayer();

            AddStep("capture score id", () => scoreId = Player.Score.ScoreInfo.ID);

            // Deterministically simulate the race the user hits: the score row lands in the
            // database and the player is disposed within the same game-thread call — before the
            // async attach (realm notification -> Schedule) can run. The notification callback
            // then bails on IsDisposed, and (pre-fix) nothing else attaches the file, so the
            // saved score is left without its replay.
            AddStep("row lands -> exit player immediately", () =>
            {
                // Give the recorded replay at least one frame so the attach proceeds.
                Player.Score.Replay.Frames.Add(new OsuReplayFrame(0, new Vector2(256, 192), OsuAction.LeftButton));

                realm.Write(r =>
                {
                    r.Add(new ScoreInfo
                    {
                        ID = scoreId,
                        BeatmapInfo = r.Find<BeatmapInfo>(beatmapId),
                        Ruleset = r.Find<RulesetInfo>(CreatePlayerRuleset().RulesetInfo.ShortName),
                    });
                });

                // Dispose immediately — the notification's scheduled attach can only run on a
                // later frame, by which time the ruleset is disposed. (Direct dispose rather than
                // a stack exit: an exit animates out over ~200ms, letting the async attach win
                // the race. The disposed player left in the tree spams ObjectDisposedException
                // into the log until the scene tears down — cosmetic only.)
                Player.Dispose();
            });

            AddAssert("replay file attached to saved score", () =>
                realm.Run(r => r.Find<ScoreInfo>(scoreId)?.Files.Any(f => f.Filename.EndsWith(".osr")) ?? false));
        }

        // Import a small beatmap through the standard BeatmapManager path (like
        // TestSceneAutoplayRandomV2 does with a real .osz). This registers the beatmap, set, and
        // files in the test database exactly as in real gameplay, so ScoreImporter.Populate can
        // re-resolve the score's beatmap and ruleset from the database.
        private void importBeatmap()
        {
            AddStep("import beatmap", () =>
            {
                var beatmap = createHitCircleBeatmap(new double[] { 2000, 3000, 4000, 5000 });

                using var stream = new MemoryStream();
                using (var writer = new StreamWriter(stream, leaveOpen: true))
                    new LegacyBeatmapEncoder(beatmap, null, null).Encode(writer);
                stream.Seek(0, SeekOrigin.Begin);

                importedSet = beatmapManager.Import(new ImportTask(stream, "replay_persistence_test.osu")).GetResultSafely();
                if (importedSet == null)
                    Assert.Fail("Failed to import beatmap");

                beatmapId = importedSet.PerformRead(s => s.Beatmaps.Single()).ID;

                // The score's ruleset is the played ruleset (mosu) — make sure a row for it
                // exists in the database (ScoreImporter.Populate re-resolves it from there).
                var rulesetInfo = CreatePlayerRuleset().RulesetInfo;
                realm.Write(r =>
                {
                    if (r.Find<RulesetInfo>(rulesetInfo.ShortName) == null)
                        r.Add(rulesetInfo);
                });
            });
        }

        private void loadPlayer()
        {
            AddStep("load player", () =>
            {
                var ruleset = CreatePlayerRuleset();

                // The working beatmap is clock-backed (like in every other player test scene) so
                // the test step machinery can drive gameplay time. Its BeatmapInfo is a detached
                // copy of the row imported above — same ID and hash — so ScoreImporter.Populate
                // can re-resolve the real database row when the score is imported.
                var dbInfo = importedSet!.PerformRead(s => s.Beatmaps.Single()).Detach();
                var beatmap = createHitCircleBeatmap(new double[] { 2000, 3000, 4000, 5000 });
                beatmap.BeatmapInfo = dbInfo;

                Ruleset.Value = ruleset.RulesetInfo;
                Beatmap.Value = CreateWorkingBeatmap(beatmap);

                // NoFail so a slightly mistimed click can't turn the pass into a fail.
                var noFail = ruleset.CreateMod<ModNoFail>();
                SelectedMods.Value = noFail != null ? new[] { noFail } : Array.Empty<Mod>();

                Player = CreatePlayer(ruleset);
                LoadScreen(Player);
            });

            AddUntilStep("wait for player loaded", () => Player.IsLoaded && Player.Alpha == 1);
        }

        private void addHitSteps()
        {
            AddStep("hit all objects", () =>
            {
                foreach (var hitObject in ((DrawableRuleset<OsuHitObject>)Player.DrawableRuleset).Beatmap.HitObjects.OrderBy(h => h.StartTime))
                {
                    double startTime = hitObject.StartTime;
                    Vector2 position = hitObject.Position;

                    AddUntilStep($"wait for {startTime}", () => Player.GameplayClockContainer.CurrentTime >= startTime);
                    AddStep($"hit {startTime}", () =>
                    {
                        InputManager.MoveMouseTo(Player.DrawableRuleset.Playfield.GamefieldToScreenSpace(position));
                        InputManager.Click(MouseButton.Left);
                    });
                }
            });
        }

        private static OsuBeatmap createHitCircleBeatmap(double[] startTimes)
        {
            var controlPointInfo = new ControlPointInfo();
            controlPointInfo.Add(0, new TimingControlPoint
            {
                Time = 0,
                BeatLength = 500,
            });

            var beatmap = new OsuBeatmap
            {
                BeatmapInfo = new BeatmapInfo
                {
                    Difficulty = new BeatmapDifficulty
                    {
                        ApproachRate = 5,
                        CircleSize = 4,
                        OverallDifficulty = 3,
                        DrainRate = 1.5f,
                    },
                    Metadata = new BeatmapMetadata
                    {
                        Title = "Replay Persistence Test",
                        Artist = "Test",
                    },
                },
                ControlPointInfo = controlPointInfo,
            };

            foreach (var startTime in startTimes)
            {
                beatmap.HitObjects.Add(new HitCircle
                {
                    StartTime = startTime,
                    Position = beatmap.HitObjects.Count % 2 == 0 ? new Vector2(256, 192) : new Vector2(100, 100),
                    NewCombo = beatmap.HitObjects.Count == 0,
                });
            }

            return beatmap;
        }
    }
}
