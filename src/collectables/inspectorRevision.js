// Fields consumed by the object model. Refresh only when its input changes.
const modelFields = [
  'instanceId', 'id', 'collectableType', 'image', 'backImage', 'rimImage',
  'edgeImage', 'edgeStyle', 'accent', 'finish', 'finishStrength', 'title',
  'imagePositionX', 'imagePositionY', 'imageZoom', 'tint', 'tintStrength',
  'stitchColor', 'stitchPattern', 'stitchWidth',
]

// Compare original values directly instead of copying embedded artwork into a giant JSON key.
export const inspectorInputs = item => modelFields.map(field => item[field])
