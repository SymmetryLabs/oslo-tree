// A visitor's choice of look, kept apart from the page so it can later go
// to the tree. Today a choice only plays here: `endpoint` is null and
// nothing leaves the page. When a backend exists (a public vote on what
// the real tree plays, see docs/oslo-site.md), pass its URL and each
// choice is posted to it as JSON: { look, source, at }. Nothing is
// counted or shown back here until that backend answers with real numbers.

export function createChoices({ endpoint = null } = {}) {
  const listeners = new Set();
  const adjustListeners = new Set();
  let current = null;
  let pending = null;
  let timer = null;
  return {
    /** Choose look `id`; `source` is "visitor", "link" or "default". */
    choose(id, source = "visitor") {
      if (id === current) return null;
      current = id;
      const choice = { look: id, source, at: new Date().toISOString() };
      for (const listen of listeners) listen(choice);
      if (endpoint && source === "visitor") {
        const body = JSON.stringify(choice);
        if (!navigator.sendBeacon?.(endpoint, new Blob([body], { type: "application/json" }))) {
          fetch(endpoint, { method: "POST", body, headers: { "content-type": "application/json" }, keepalive: true }).catch(() => {});
        }
      }
      return choice;
    },
    /**
     * The visitor moved control `control` of look `look` to `position`
     * (0 to 1). Recorded like a choice ({ look, control, position, at }),
     * posted at most once a second to the endpoint when there is one.
     */
    adjust(look, control, position) {
      const adjustment = { look, control, position, at: new Date().toISOString() };
      for (const listen of adjustListeners) listen(adjustment);
      if (endpoint) {
        pending = adjustment;
        if (!timer) {
          timer = setTimeout(() => {
            timer = null;
            const body = JSON.stringify({ kind: "adjust", ...pending });
            fetch(endpoint, { method: "POST", body, headers: { "content-type": "application/json" }, keepalive: true }).catch(() => {});
          }, 1000);
        }
      }
      return adjustment;
    },
    /** Call `listen(adjustment)` on every adjustment. */
    onAdjust(listen) {
      adjustListeners.add(listen);
      return () => adjustListeners.delete(listen);
    },
    /** Call `listen(choice)` on every choice; returns a function that stops it. */
    onChoice(listen) {
      listeners.add(listen);
      return () => listeners.delete(listen);
    },
    get current() {
      return current;
    },
  };
}
