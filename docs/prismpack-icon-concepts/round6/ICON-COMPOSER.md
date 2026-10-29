# Round 6 deck: suggested Icon Composer settings

These are starting points, not tested in Icon Composer. Its own glass, blur
and specular will change the look, so tune by eye. Import each SVG as its
own layer, in file order (01 at the bottom).

| Layer | Liquid Glass | Opacity | Blend | Notes |
|---|---|---|---|---|
| 01-backdrop | n/a (background fill) | 100% | Normal | Or use Icon Composer's own background gradient with the same stops. |
| 02 to 07 cards | On | 100% | Normal | Chromatic shadow off; a neutral shadow keeps the stack readable. |
| 08-front-glass | **On, high translucency** | 100% | Normal | The clear card. Icon Composer's glass makes it refract the violet card behind it. |
| 09-front-sheen | Off | 50 to 70% | Soft Light or Overlay | The rainbow sheen. Lower it if the card goes muddy. |
| 10-prism-light | Off, or light glass | 100% | Normal | The bright face. |
| 11-prism-shade | Off | 60 to 100% | Normal | The shaded face that makes it 3D. |
| 99-glint | Drop it | n/a | n/a | Icon Composer's specular highlight replaces it. |

Check the result in Icon Composer's light, dark, tinted and clear previews.
