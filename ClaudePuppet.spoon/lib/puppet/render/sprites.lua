-- Every sprite, as rows of colour keys from config.COLORS ("." is transparent).
--
-- BODIES are the characters a harness can wear (its `character.body`), each in the same four poses on the same
-- grid, so every scene draws any of them: SIDE and SMILE (9 x 9, at the desk, facing the monitor on the right;
-- the paws the desk scene draws reach out from column 9), FRONT and FRONT_ASLEEP (9 wide, up to 8 tall, standing
-- on the ping pong table and the home desk).

local BODIES = {
  -- The first puppet: a block with four legs.
  claude = {
    SIDE = {
      "..ccccc..",
      ".ccccccc.",
      ".cccccck.",
      ".cccccck.",
      ".ccccccc.",
      ".ccccccc.",
      ".ccccccc.",
      ".ccccccc.",
      ".c.c.c.c.",
    },
    SMILE = {
      "..ccccc..",
      ".ccccccc.",
      ".ckccckc.",
      ".ckccckc.",
      ".ccccccc.",
      ".kccccck.",
      ".ckkkkkc.",
      ".ccccccc.",
      ".c.c.c.c.",
    },
    FRONT = {
      ".ccccccc.",
      ".ckcccck.",
      "ccccccccc",
      ".ccccccc.",
      ".c.c.c.c.",
    },
    FRONT_ASLEEP = {
      ".ccccccc.",
      ".cccccccc",
      "ccccccccc",
      ".ccccccc.",
      ".c.c.c.c.",
    },
  },
  -- An owl: ear tufts, big ringed eyes looking at the monitor, a beak, a feathered chest, talons.
  owl = {
    SIDE = {
      ".c.....c.",
      ".ccccccc.",
      ".cwwcwwc.",
      ".cwkcwkc.",
      ".cccyccc.",
      ".ccccccc.",
      ".ccwcwcc.",
      "..ccccc..",
      "..y...y..",
    },
    SMILE = {
      ".c.....c.",
      ".ccccccc.",
      ".cwwcwwc.",
      ".ckkckkc.",
      ".ccyyycc.",
      ".cccyccc.",
      ".ccwcwcc.",
      "..ccccc..",
      "..y...y..",
    },
    FRONT = {
      ".c.....c.",
      ".ccccccc.",
      "cwwwcwwwc",
      "cwkwcwkwc",
      "cwwwywwwc",
      ".cccyccc.",
      ".ccwcwcc.",
      "..y...y..",
    },
    FRONT_ASLEEP = {
      ".c.....c.",
      ".ccccccc.",
      "ccccccccc",
      "ckkkckkkc",
      "ccccycccc",
      ".cccyccc.",
      ".ccwcwcc.",
      "..y...y..",
    },
  },
  -- A cat: pointed ears, eyes on the monitor, whiskers, a tail curling up behind, paws.
  cat = {
    SIDE = {
      ".c...c...",
      ".cc.cc...",
      ".ccccccc.",
      ".cccckck.",
      ".cccccccw",
      "c.ccccc..",
      "c.ccccc..",
      ".cccccc..",
      "..c..c...",
    },
    SMILE = {
      ".c...c...",
      ".cc.cc...",
      ".ccccccc.",
      ".ckcckcc.",
      "wcccccccw",
      "c.ckkkc..",
      "c.ccccc..",
      ".cccccc..",
      "..c..c...",
    },
    FRONT = {
      ".c.....c.",
      ".cc...cc.",
      ".ccccccc.",
      ".ckcccck.",
      "wccckcccw",
      "..ccccc..",
      ".ccccccc.",
      "..cc.cc..",
    },
    FRONT_ASLEEP = {
      ".c.....c.",
      ".cc...cc.",
      ".ccccccc.",
      ".kkccckk.",
      "wccckcccw",
      "..ccccc..",
      ".ccccccc.",
      "..cc.cc..",
    },
  },
}

return {
  BODIES = BODIES,
  -- The body a harness wears; Claude's when it names none, or one this file does not have.
  body = function(harness)
    local name = harness and harness.character and harness.character.body
    return BODIES[name] or BODIES.claude
  end,
  INVADER = { { ".vvv.", "v.v.v", "v...v" }, { ".vvv.", "v.v.v", ".v.v." } },
  SHIP = { "..c..", "ccccc" },
  BOOM = { "y.y.y", ".y.y.", "y.y.y" },
  CHECK = { "......p", ".....p.", "p...p..", ".p.p...", "..p...." },
  CROSS = { "r...r", ".r.r.", "..r..", ".r.r.", "r...r" },
  DONE = { "....p", "p..p.", ".pp.." },
  QUESTION = { ".www.", "w...w", "....w", "...w.", "..w..", ".....", "..w.." },
  LENS = { ".www..", "w...w.", "w...w.", ".www..", "....g.", ".....g" },
}
