// Plugin-side: what lets one card be rebuilt alone. build.mjs prepends this
// file after the helpers of lib.js, surfaces.js and calls.js. A rebuilt card has new components; relink() moves
// every instance of the old ones onto the component of the same name in the
// new card, so the cards that use them keep their own components and node ids.

/** A component as variant() names it: its set and its variant, or its own name. */
const address = (c) => (c.parent.type === 'COMPONENT_SET' ? `${c.parent.name} / ${c.name}` : c.name);
/** The card a layer is in, by name; outside the section, the frame that holds it. */
const cardOf = (n) => where(n).split(' / ')[0];
/** The nearest layer above [n] that [is] what is asked for. */
const up = (n, is) => { for (let x = n.parent; x; x = x.parent) if (is(x)) return x; return null; };
/** The instance that holds [i] and is in no other; [i] itself when nothing holds it. */
const outermost = (i) => { let top = i; for (let x = i.parent; x; x = x.parent) if (x.type === 'INSTANCE') top = x; return top; };
// An instance inside another one has the ids of both in its own.
const depth = (i) => i.id.split(';').length;
/** What [i] overrides, each as "field of layer". The layer's name stands for it, as a swap gives it a new id. */
function overridden(i) {
  // Looked up inside the instance: figma.getNodeByIdAsync on the id of an override has hung for ten seconds and thrown.
  const names = new Map(i.findAll(() => true).map((n) => [n.id, n.name]));
  return i.overrides.flatMap((o) => o.overriddenFields.map((f) => `${f} of ${o.id === i.id ? 'the instance' : names.get(o.id)}`));
}
/** The component properties [i] sets apart from its component's defaults, by display name. */
async function ownValues(i) {
  const main = await i.getMainComponentAsync(), defaults = (main.parent.type === 'COMPONENT_SET' ? main.parent : main).componentPropertyDefinitions;
  const own = Object.entries(i.componentProperties).filter(([key, p]) => p.type !== 'VARIANT' && p.value !== defaults[key]?.defaultValue);
  return Object.fromEntries(own.map(([key, p]) => [key.split('#')[0], p.value]));
}
/** Sets the properties [values] on [i] by their display names; [renewed] turns an old component a property swaps in into the new one. What [i] has no property for goes to [lost]. */
function setValues(i, values, renewed, lost) {
  for (const [name, old] of Object.entries(values)) {
    const value = renewed.get(old)?.id ?? old, key = Object.keys(i.componentProperties).find((k) => k.split('#')[0] === name);
    if (!key) lost.push(`property ${name} — ${where(i)}`);
    else if (i.componentProperties[key].value !== value) i.setProperties({ [key]: value });
  }
}
// Set once instances start to move: from then on the new card is the one in use.
let relinking = false;
/** Takes back the card of a script that threw, so the card it was replacing stays the only one. */
function discard() { if (OLD && !relinking) CARD?.remove(); }

/**
 * Sets again the properties the instances in [was] had set before the move, where the move dropped them,
 * and adds to [lost] the overrides that are gone.
 */
function restore(was, renewed, lost) {
  for (const { top, id, overrides, values } of was) {
    // Found again by its id under the outermost instance that holds it: the node held from before has the layers of the
    // old component, and figma.getNodeByIdAsync can hang for ten seconds and throw on an id that is gone.
    // An instance inside an old component is gone with it, and what it had set is among the overrides of the one that held it.
    const i = top.id === id ? top : top.findOne((x) => x.id === id);
    if (!i) continue;
    setValues(i, values, renewed, lost);
    // One for one: two layers of one name with the same field overridden are two entries.
    const kept = overridden(i);
    for (const o of overrides) { const at = kept.indexOf(o); if (at < 0) lost.push(`${o} — ${where(i)}`); else kept.splice(at, 1); }
  }
}

/**
 * Moves the instances of the components in [olds] onto their namesakes in [fresh].
 * Reports how many moved, the cards they are in, the overrides that did not survive the move, and
 * the components elsewhere that changed size with it: their card laid them out at the old size.
 */
async function relink(olds, fresh) {
  const next = new Map(fresh.findAllWithCriteria({ types: ['COMPONENT'] }).map((c) => [address(c), c]));
  const prev = olds.flatMap((o) => o.findAllWithCriteria({ types: ['COMPONENT'] }));
  // Left alone: the old card's own examples. In a card this run rebuilds later, only an instance with no namesake to move to,
  // which that card's new script no longer asks for. Every other instance moves, in such a card too: left on a component
  // that is then removed it turns into a plain frame, and the move of the layers that hold it goes wrong.
  const later = (n) => n.parent === host() && REBUILT_LATER.includes(n.getPluginData('script'));
  const stays = (i, c) => up(i, (n) => olds.includes(n)) || (!next.has(address(c)) && up(i, later));
  /** The instances to move off an old component, anywhere in the file, each with the name of that component. */
  async function stale() {
    const out = [];
    for (const c of prev) for (const i of await c.getInstancesAsync()) if (!stays(i, c)) out.push([i, address(c)]);
    return out;
  }
  const first = await stale(), gone = new Map();
  for (const [i, a] of first) if (!next.has(a)) gone.set(a, cardOf(i));
  if (gone.size) throw new Error(`${fresh.name} no longer has ${[...gone].map(([a, user]) => `"${a}" (used in ${user})`).join(', ')}: keep the name, or rebuild the cards that use it in the same run`);
  // What each instance sets of its own, taken before any of them moves: one that follows its
  // component onto the new card is not swapped here, and Figma drops the properties it had set.
  // Named now, as is every card with an instance that moves or follows: after the move some of these layers are no more.
  const was = [], touched = [...new Set(first.map(([i]) => cardOf(i)))];
  for (const [i] of first) was.push({ top: outermost(i), id: i.id, overrides: overridden(i), values: await ownValues(i) });
  relinking = true;
  const holders = new Map(), lost = [], renewed = new Map(prev.filter((c) => next.has(address(c))).map((c) => [c.id, next.get(address(c))]));
  let moved = 0;
  // Outermost first: an instance inside another follows its own component, unless its swap is an override, and then it is still stale on the next pass.
  for (let todo = await stale(), pass = 0; todo.length; todo = await stale(), pass++) {
    // Each pass goes a level deeper into nested instances; no card nests them this deep.
    if (pass > 8) throw new Error(`instances that will not move: ${todo.slice(0, 5).map(([i]) => where(i)).join('; ')}`);
    const least = Math.min(...todo.map(([i]) => depth(i)));
    for (const [i, a] of todo.filter(([x]) => depth(x) === least)) {
      const holder = up(i, (x) => x.type === 'COMPONENT');
      if (holder && !holders.has(holder)) holders.set(holder, `${holder.width}x${holder.height}`);
      i.swapComponent(next.get(a));
      moved++;
    }
  }
  restore(was, renewed, lost);
  const resized = [...holders].filter(([h, size]) => size !== `${h.width}x${h.height}`).map(([h, size]) => `${where(h)}: ${size} → ${h.width}x${h.height}`);
  return { moved, lost, resized, touched };
}
