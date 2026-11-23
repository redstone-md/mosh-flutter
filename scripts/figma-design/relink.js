// Plugin-side: what lets one card be rebuilt alone. build.mjs prepends this
// file after surfaces.js. A rebuilt card has new components; relink() moves
// every instance of the old ones onto the component of the same name in the
// new card, so the cards that use them keep their own components and node ids.

/** A layer's path below the section, for a message. */
const where = (n) => { const p = []; for (let x = n; x && x.type !== 'SECTION'; x = x.parent) p.unshift(x.name); return p.join(' / '); };
/** A component as variant() names it: its set and its variant, or its own name. */
const address = (c) => (c.parent.type === 'COMPONENT_SET' ? `${c.parent.name} / ${c.name}` : c.name);
/** The card a layer is in, by name. */
const cardOf = (n) => where(n).split(' / ')[0];
const up = (n, is) => { for (let x = n.parent; x; x = x.parent) if (is(x)) return x; return null; };
// An instance inside another one has the ids of both in its own.
const depth = (i) => i.id.split(';').length;
/** What [i] overrides, as "field of layer". The layer's name stands for it, as a swap gives it a new id. */
function overridden(i) {
  // Looked up inside the instance: figma.getNodeByIdAsync on the id of an override has hung for ten seconds and thrown.
  const names = new Map(i.findAll(() => true).map((n) => [n.id, n.name]));
  return new Set(i.overrides.flatMap((o) => o.overriddenFields.map((f) => `${f} of ${o.id === i.id ? 'the instance' : names.get(o.id)}`)));
}
/** The component properties [i] sets apart from its component's defaults, by display name. */
async function ownValues(i) {
  const main = await i.getMainComponentAsync(), defaults = (main.parent.type === 'COMPONENT_SET' ? main.parent : main).componentPropertyDefinitions;
  const own = Object.entries(i.componentProperties).filter(([key, p]) => p.type !== 'VARIANT' && p.value !== defaults[key]?.defaultValue);
  return Object.fromEntries(own.map(([key, p]) => [key.split('#')[0], p.value]));
}
// Set once instances start to move: from then on the new card is the one in use.
let relinking = false;
/** Takes back the card of a script that threw, so the card it was replacing stays the only one. */
function discard() { if (OLD && !relinking) CARD.remove(); }

/**
 * Sets again the properties the instances in [was] had set before the move, where the move dropped them.
 * Returns what could not be kept: a property the new component lacks, an override that is gone.
 */
async function restore(was) {
  const lost = [];
  for (const { id, overrides, values } of was) {
    // Asked for again by its id: the layers of the node held from before are those of the old component.
    // An instance inside an old component is gone with it, and what it had set is among the overrides of the one that held it.
    const i = await figma.getNodeByIdAsync(id);
    if (!i) continue;
    for (const [name, value] of Object.entries(values)) {
      const key = Object.keys(i.componentProperties).find((k) => k.split('#')[0] === name);
      if (!key) lost.push(`property ${name} — ${where(i)}`);
      else if (i.componentProperties[key].value !== value) i.setProperties({ [key]: value });
    }
    const kept = overridden(i);
    for (const o of overrides) if (!kept.has(o)) lost.push(`${o} — ${where(i)}`);
  }
  return lost;
}

/**
 * Moves the instances of the components in [olds] onto their namesakes in [fresh].
 * Reports how many moved, the cards they are in, the overrides that did not survive the move, and
 * the components elsewhere that changed size with it: their card laid them out at the old size.
 */
async function relink(olds, fresh) {
  const next = new Map(fresh.findAllWithCriteria({ types: ['COMPONENT'] }).map((c) => [address(c), c]));
  const prev = olds.flatMap((o) => o.findAllWithCriteria({ types: ['COMPONENT'] }));
  // Left alone: the old card's own examples, and the cards this run rebuilds anyway.
  const leaving = (n) => olds.includes(n) || (n.parent === host() && REBUILT_LATER.includes(Number(n.getPluginData('order'))));
  /** The instances still on an old component, anywhere in the file, each with the name of that component. */
  async function stale() {
    const out = [];
    for (const c of prev) for (const i of await c.getInstancesAsync()) if (!up(i, leaving)) out.push([i, address(c)]);
    return out;
  }
  const first = await stale(), gone = new Map();
  for (const [i, a] of first) if (!next.has(a)) gone.set(a, cardOf(i));
  if (gone.size) throw new Error(`${fresh.name} no longer has ${[...gone].map(([a, user]) => `"${a}" (used in ${user})`).join(', ')}: keep the name, or rebuild the cards that use it in the same run`);
  // What each instance sets of its own, taken before any of them moves: one that follows its
  // component onto the new card is not swapped here, and Figma drops the properties it had set.
  // Named now, as is every card with an instance that moves or follows: after the move some of these layers are no more.
  const was = [], touched = [...new Set(first.map(([i]) => cardOf(i)))];
  for (const [i] of first) was.push({ id: i.id, overrides: overridden(i), values: await ownValues(i) });
  relinking = true;
  const holders = new Map();
  let moved = 0;
  // Outermost first: an instance inside another follows its own component, unless its swap is an override, and then it is still stale on the next pass.
  for (let todo = await stale(), pass = 0; todo.length; todo = await stale(), pass++) {
    if (pass > 8) throw new Error(`instances that will not move: ${todo.slice(0, 5).map(([i]) => where(i)).join('; ')}`);
    const least = Math.min(...todo.map(([i]) => depth(i)));
    for (const [i, a] of todo.filter(([x]) => depth(x) === least)) {
      const holder = up(i, (x) => x.type === 'COMPONENT');
      if (holder && !holders.has(holder)) holders.set(holder, `${holder.width}x${holder.height}`);
      i.swapComponent(next.get(a));
      moved++;
    }
  }
  const lost = await restore(was);
  const resized = [...holders].filter(([h, size]) => size !== `${h.width}x${h.height}`).map(([h, size]) => `${where(h)}: ${size} → ${h.width}x${h.height}`);
  return { moved, lost, resized, touched };
}
