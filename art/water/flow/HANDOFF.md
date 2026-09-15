# Water W03 — moving light network and turquoise body, art OPEN

2026-09-15. User identified the missing character as changing white networks
that reveal water-surface oscillation and explicitly requested stronger turquoise.
W03 continues W01 optical motion and W02 pixel reflections in the same Surface
shader/material. Main checkout is read-only; no commit/push.

Production changes only the existing water shader/.tres. The network uses the
existing continuous optical slopes to bend/advect the connected cell field at
continuous seconds. World coordinates preserve patterns across chunks/placed
parts; flow pixels are half-voxel while reflection pixels stay one voxel. Sparse
moving gaps keep shapes from being a closed uniform mesh. Strength0.60 fades to
0.32of that at deep band and derivatives remove subpixel detail at distance.
It applies on upward water faces, never changes geometry/collision.

This is an artistic bright pattern composited in water ALBEDO, lit by the existing
environment. Body emission remains0, so the network is not self-lit. It is not
physically refracted light projected onto bottom/rocks, actual refraction or
caustic render pass. Those require a separate owner/scope after this look is
accepted. Existing foam/contact/wake and swimming/gameplay are unchanged.

Canonical colours: tint(0.02,0.88,0.86), light(0.055,0.90,0.86),
deep(0.005,0.63,0.70), tint_strength0.32; palette influence0.06 prevents Source
tint from greying the water. Shallow opacity0.42→0.50 gives the body more colour;
deep0.78 remains. Roughness0.28→0.22 sharpens real W01/W02 reflections/highlights.
Pixel reflections remain enabled. Legacy ripple alpha0 avoids drawing the former
duplicate network; authored scene-embedded overrides may need retuning after art
acceptance instead of silently rewriting their storage.

Native actual-frame evidence: close `before`(W02 exact checkpoint), `no-network`
(new colour/reflection only), `flow`; plus game/wide flow. Each sequence has48PNG
at12samples/s and a4sGIF. QA-only Sky/probe/specular and disposable island marks
retain earlier limits; the broad fixture is not a gameplay swimming map.

`test_water_flow.gd` executes the production fragment and only exposes flow_weight
as unshaded colour. World split atx=-0.63 produces5significant edge pixels and
average0.0000153 across512²; negative/positive space covered. Time3.25→3.75 changes
31406pixels(avg0.0922). Shallow mean0.1238, deep0.0737; strength0 and distant mask
vanish. Default storage/no-glow is also headless-tested. Related native and
headless results/logs are inqa; see final package guard for the complete set.

First diagnostic failure used EMISSION in unshaded mode and produced black,
despite the normal stand working; archived in `failed-emission-diagnostic`.
Second correctly detected sparkling subpixel remnants at camera.size64; reducing
fade end0.16→0.10 fixed it and is archived in `failed-distance-threshold`.
The first visually excessive cell attempts are retained in chat and
`failed-fragmented-network`. None is relabelled PASS.

Known QA ReflectionProbe shutdown7TextureRID warning remains the prior Godot4.7.2
engine issue. Existing UID/fragment ObjectDB warnings remain separate. No engine
fix or clean probe-lifecycle claim.

Transfer the incremental W03 `refinement.patch`, production2files, adjusted
water tests and new flow render/test+UIDs. QA additionally needs checkpoint-w02,
prior W01/W02 helpers and `documentation-sections.md`; never replace current main
docs wholesale. Source/schema/mesher/editor/authored maps/physics/library/lighting
owners remain unchanged. Art/input/main integration and actual bottom caustics OPEN.
