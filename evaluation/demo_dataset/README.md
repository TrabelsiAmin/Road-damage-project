# Development demo photographs

These ten photographs are a development demonstration set. They are not TariqMap field observations, and they were not inserted into Supabase.

Each class code was assigned by looking at the stored image on 8 November 2026. The assignment is not a model detection, not an RDD label, and not a field survey. `MANIFEST.json` records the source page, license, attribution, original dimensions, stored dimensions, and SHA-256.

| File | Reviewed class | License | Attribution |
| --- | --- | --- | --- |
| `photos/d00-earlswood.jpg` | D00 | CC BY-SA 2.0 | Jaggery |
| `photos/d00-chapel-road.jpg` | D00 | CC BY-SA 2.0 | Des Blenkinsopp |
| `photos/d00-starham-road.jpg` | D00 | CC BY-SA 2.0 | JThomas |
| `photos/d10-lane-crossing-crack.jpg` | D10 | CC BY-SA 2.0 | Oliver Dixon |
| `photos/d20-cracked-asphalt-rain.jpg` | D20 | CC0 | W.carter |
| `photos/d20-deteriorated-asphalt.jpg` | D20 | CC BY-SA 3.0 | Bidgee |
| `photos/d20-pentwynmawr.jpg` | D20 | CC BY-SA 2.0 | Jaggery |
| `photos/d40-potholes-asphalt-20171023.jpg` | D40 | CC BY-SA 4.0 | Santeri Viinamäki |
| `photos/d40-bache-coyoacan.jpg` | D40 | CC BY 4.0 | Msofiaa |
| `photos/d40-pothole-asphalt-pavement.jpg` | D40 | CC BY-SA 4.0 | Frankie Fouganthin |

D00 means the crack follows the visible direction of travel. D10 means the crack crosses the lane. D20 means interconnected cracking. D40 means a broken bowl in the surface. Where another pattern is also visible, the manifest says so and does not add a second class.

D10 has one kept photograph. A second transverse crack was reviewed and left out because a vehicle registration was readable. Other reviewed files were left out when the class was a manhole, block cracking, a crack junction with no travel direction, or a composite figure. Those titles are listed in the manifest.

Several stored files are Wikimedia thumbnails. The manifest gives both the stored size and the Commons original size. `d00-starham-road.jpg` is the 640×480 original.

`seed_local_dev.sql` is not an applied migration. It aborts unless the database name is `tariqmap_dev_local` and the server is local. It inserts missing rows only. It does not delete, and it does not invent a priority score, a model version, coordinates, or a bounding box. It was not executed. The only Supabase project available here is production `lendqcjihusqkmxansbl`.

`supabase/seed/demo_data.sql` is a different, older script. It deletes every `is_demo` row. Do not use it for this photograph set.
