// The tokens controls need beyond colour, shape and spacing, as variables in
// "Mosh Dimensions": state/* are layer opacities in percent (Material 3 state
// layers and the scrim), border/* are stroke weights. Safe to run again.
const TOKENS = {
  'state/hover': [8, 'OPACITY'], 'state/focus': [10, 'OPACITY'], 'state/pressed': [10, 'OPACITY'],
  'state/disabledContainer': [12, 'OPACITY'], 'state/disabledContent': [38, 'OPACITY'], 'state/scrim': [54, 'OPACITY'],
  'border/thin': [1, 'STROKE_FLOAT'], 'border/thick': [2, 'STROKE_FLOAT'],
};
const created = [];
for (const [name, [value, scope]] of Object.entries(TOKENS)) {
  if (!DIM[name]) { DIM[name] = figma.variables.createVariable(name, collection('Mosh Dimensions'), 'FLOAT'); created.push(name); }
  DIM[name].setValueForMode(DIM_MODE, value);
  DIM[name].scopes = [scope];
}
return { created };
