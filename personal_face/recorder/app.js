(() => {
  const steps = window.FACE_STEPS || [];

  const els = {
    preview: document.getElementById("preview"),
    overlayHint: document.getElementById("overlayHint"),
    recDot: document.getElementById("recDot"),
    recBadge: document.getElementById("recBadge"),
    timeBadge: document.getElementById("timeBadge"),
    stepTitle: document.getElementById("stepTitle"),
    stepDesc: document.getElementById("stepDesc"),
    countdown: document.getElementById("countdown"),
    stepDuration: document.getElementById("stepDuration"),
    stepCounter: document.getElementById("stepCounter"),
    barFill: document.getElementById("barFill"),
    checklist: document.getElementById("checklist"),
    btnCamera: document.getElementById("btnCamera"),
    btnSession: document.getElementById("btnSession"),
    btnSkip: document.getElementById("btnSkip"),
    btnStop: document.getElementById("btnStop"),
    doneModal: document.getElementById("doneModal"),
    doneText: document.getElementById("doneText"),
    btnDownload: document.getElementById("btnDownload"),
    btnCloseModal: document.getElementById("btnCloseModal"),
  };

  let stream = null;
  let recorder = null;
  let chunks = [];
  let recordedBlob = null;
  let mimeType = "video/webm";

  let stepIndex = -1;
  let stepEndsAt = 0;
  let sessionActive = false;
  let sessionStartedAt = 0;
  let tickTimer = null;

  function fmt(sec) {
    sec = Math.max(0, Math.ceil(sec));
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  }

  function totalSeconds() {
    return steps.reduce((a, s) => a + s.seconds, 0);
  }

  function buildChecklist() {
    els.checklist.innerHTML = "";
    steps.forEach((s, i) => {
      const li = document.createElement("li");
      li.dataset.i = String(i);
      li.innerHTML = `<span class="dot"></span><span class="label">${s.title}</span><span class="dur">${fmt(s.seconds)}</span>`;
      els.checklist.appendChild(li);
    });
    els.stepCounter.textContent = `Step 0 / ${steps.length}`;
    els.stepDuration.textContent = `Full session ≈ ${fmt(totalSeconds())}`;
  }

  function setBadge(state) {
    els.recBadge.className = "badge " + state;
    els.recBadge.textContent =
      state === "live" ? "Camera" : state === "rec" ? "Recording" : "Idle";
    els.recDot.classList.toggle("hidden", state !== "rec");
  }

  function updateChecklistUI() {
    [...els.checklist.children].forEach((li, i) => {
      li.classList.remove("active", "done");
      if (i < stepIndex) li.classList.add("done");
      if (i === stepIndex) li.classList.add("active");
    });
    const pct = stepIndex < 0 ? 0 : ((stepIndex + 1) / steps.length) * 100;
    els.barFill.style.width = `${Math.min(100, pct)}%`;
    els.stepCounter.textContent = `Step ${Math.max(0, stepIndex + 1)} / ${steps.length}`;
  }

  function showStep(i) {
    stepIndex = i;
    if (i < 0 || i >= steps.length) return;
    const s = steps[i];
    els.stepTitle.textContent = s.title;
    els.stepDesc.textContent = s.desc;
    els.stepDuration.textContent = `This step: ${fmt(s.seconds)}`;
    stepEndsAt = performance.now() + s.seconds * 1000;
    updateChecklistUI();
  }

  function pickMime() {
    const candidates = [
      "video/webm;codecs=vp9,opus",
      "video/webm;codecs=vp8,opus",
      "video/webm",
      "video/mp4",
    ];
    for (const c of candidates) {
      if (window.MediaRecorder && MediaRecorder.isTypeSupported(c)) return c;
    }
    return "";
  }

  async function startCamera() {
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: {
          width: { ideal: 1280 },
          height: { ideal: 720 },
          frameRate: { ideal: 30 },
          facingMode: "user",
        },
        audio: false,
      });
      els.preview.srcObject = stream;
      els.overlayHint.classList.add("hidden");
      els.btnCamera.textContent = "Camera on";
      els.btnCamera.disabled = true;
      els.btnSession.disabled = false;
      setBadge("live");
    } catch (err) {
      console.error(err);
      els.overlayHint.textContent =
        "Camera permission denied or unavailable. Allow the camera and try again.";
      alert("Could not open the camera.\n\n" + (err && err.message ? err.message : err));
    }
  }

  function startRecorder() {
    chunks = [];
    recordedBlob = null;
    mimeType = pickMime() || "video/webm";
    const opts = mimeType ? { mimeType, videoBitsPerSecond: 4_000_000 } : { videoBitsPerSecond: 4_000_000 };
    try {
      recorder = new MediaRecorder(stream, opts);
    } catch {
      recorder = new MediaRecorder(stream);
    }
    recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) chunks.push(e.data);
    };
    recorder.onstop = () => {
      const type = chunks[0]?.type || mimeType || "video/webm";
      recordedBlob = new Blob(chunks, { type });
      const mins = ((performance.now() - sessionStartedAt) / 60000).toFixed(1);
      els.doneText.textContent = `Saved about ${mins} minutes of video (${(recordedBlob.size / (1024 * 1024)).toFixed(1)} MB). Download it, then upload to Google Drive.`;
      els.doneModal.classList.remove("hidden");
      setBadge("live");
    };
    recorder.start(1000);
    setBadge("rec");
  }

  function stopRecorder() {
    if (recorder && recorder.state !== "inactive") {
      recorder.stop();
    }
  }

  function endSession(completed) {
    sessionActive = false;
    if (tickTimer) {
      clearInterval(tickTimer);
      tickTimer = null;
    }
    els.btnSkip.disabled = true;
    els.btnStop.disabled = true;
    els.btnSession.disabled = !stream;
    els.btnSession.textContent = "Start session";
    stopRecorder();
    if (!completed) {
      // onstop still fires download modal
    }
  }

  function nextStepOrFinish() {
    if (stepIndex + 1 >= steps.length) {
      els.stepTitle.textContent = "All steps done";
      els.stepDesc.textContent = "Stopping recording and preparing your file…";
      els.countdown.textContent = "00:00";
      updateChecklistUI();
      [...els.checklist.children].forEach((li) => li.classList.add("done"));
      els.barFill.style.width = "100%";
      endSession(true);
      return;
    }
    showStep(stepIndex + 1);
  }

  function tick() {
    if (!sessionActive) return;
    const now = performance.now();
    const left = (stepEndsAt - now) / 1000;
    els.countdown.textContent = fmt(left);
    const elapsed = (now - sessionStartedAt) / 1000;
    els.timeBadge.textContent = fmt(elapsed);
    if (left <= 0) nextStepOrFinish();
  }

  function startSession() {
    if (!stream) return;
    sessionActive = true;
    sessionStartedAt = performance.now();
    els.btnSession.disabled = true;
    els.btnSkip.disabled = false;
    els.btnStop.disabled = false;
    els.btnSession.textContent = "Session running…";
    startRecorder();
    showStep(0);
    if (tickTimer) clearInterval(tickTimer);
    tickTimer = setInterval(tick, 200);
    tick();
  }

  function download() {
    if (!recordedBlob) return;
    const ext = recordedBlob.type.includes("mp4") ? "mp4" : "webm";
    const a = document.createElement("a");
    const url = URL.createObjectURL(recordedBlob);
    a.href = url;
    a.download = `odin_face_${new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-")}.${ext}`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }

  els.btnCamera.addEventListener("click", startCamera);
  els.btnSession.addEventListener("click", startSession);
  els.btnSkip.addEventListener("click", () => {
    if (sessionActive) nextStepOrFinish();
  });
  els.btnStop.addEventListener("click", () => endSession(false));
  els.btnDownload.addEventListener("click", download);
  els.btnCloseModal.addEventListener("click", () => els.doneModal.classList.add("hidden"));

  buildChecklist();
  setBadge("idle");
})();
