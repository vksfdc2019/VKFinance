/** Convert a photo to a bounded JPEG before it crosses the API boundary. */
export async function prepareReceipt(
  file: File
): Promise<{ fileName: string; mimeType: string; data: string }> {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type))
    throw new Error('Choose a JPEG, PNG or WebP photo.');
  if (file.size > 10_000_000)
    throw new Error('Choose a photo smaller than 10 MB.');
  const bitmap = await createImageBitmap(file, {
    imageOrientation: 'from-image',
  });
  try {
    if (
      !bitmap.width ||
      !bitmap.height ||
      bitmap.width * bitmap.height > 40_000_000
    )
      throw new Error(
        'This photo is too large to process. Choose a smaller image.'
      );
    const ratio = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(bitmap.width * ratio);
    canvas.height = Math.round(bitmap.height * ratio);
    const context = canvas.getContext('2d');
    if (!context)
      throw new Error('Photo processing is unavailable in this browser.');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    for (const quality of [0.85, 0.7, 0.5]) {
      const dataUrl = canvas.toDataURL('image/jpeg', quality);
      const data = dataUrl.split(',')[1];
      if (data.length <= 460_000)
        return {
          fileName:
            file.name
              .replace(/\.[^.]+$/, '')
              .replace(/[^a-zA-Z0-9 ._-]/g, '_')
              .slice(0, 110) + '.jpg',
          mimeType: 'image/jpeg',
          data,
        };
    }
    throw new Error(
      'The compressed image is still too large. Crop the receipt and try again.'
    );
  } finally {
    bitmap.close();
  }
}
