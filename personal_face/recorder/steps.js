// Exact coaching script — durations in seconds (matches personal_face README checklist)
window.FACE_STEPS = [
  {
    id: "neutral",
    title: "Neutral face",
    desc: "Look at the camera with a relaxed face. Sit still. Breathe normally.",
    seconds: 90,
  },
  {
    id: "talk",
    title: "Talk naturally",
    desc: "Read something out loud, chat, or count slowly. Keep looking at the camera. This is the most important step.",
    seconds: 360, // 6 min
  },
  {
    id: "mouth",
    title: "Mouth open / close",
    desc: "Open your mouth wide, hold a second, then close. Repeat slowly. Mix big and small opens.",
    seconds: 90,
  },
  {
    id: "smile",
    title: "Smile and laugh",
    desc: "Small smile → big smile → relax. Laugh a little if you can. Repeat a few times.",
    seconds: 90,
  },
  {
    id: "blink",
    title: "Blink and close eyes",
    desc: "Blink often. A few times, close both eyes for 2–3 seconds, then open.",
    seconds: 75,
  },
  {
    id: "yaw",
    title: "Look left and right",
    desc: "Turn your head slowly left, hold, back to center, then right. Repeat. Not only your eyes — turn your head.",
    seconds: 90,
  },
  {
    id: "pitch",
    title: "Look up and down",
    desc: "Tilt your face up toward the ceiling, then down toward the desk. Slow and smooth.",
    seconds: 75,
  },
  {
    id: "roll",
    title: "Tilt / roll your head",
    desc: "Ear toward left shoulder, then right shoulder. Keep looking roughly toward the camera.",
    seconds: 75,
  },
  {
    id: "talk_turn",
    title: "Talk while turning",
    desc: "Keep talking while you gently turn and tilt your head. This matches real streaming.",
    seconds: 150, // 2.5 min
  },
  {
    id: "brows",
    title: "Eyebrows and frown",
    desc: "Raise both brows, hold, lower. Then a slight frown. Repeat.",
    seconds: 75,
  },
  {
    id: "distance",
    title: "Closer and farther",
    desc: "Lean toward the camera, hold, then lean back. Stay in frame.",
    seconds: 60,
  },
  {
    id: "side",
    title: "¾ side views (optional)",
    desc: "Turn to show a three-quarter left profile, then right. Not the back of your head.",
    seconds: 75,
  },
  {
    id: "wrap",
    title: "Free talk wrap-up",
    desc: "Talk casually for a bit — your normal face while streaming. Relax.",
    seconds: 120,
  },
];

// Total ≈ 24+ minutes if all steps run fully
