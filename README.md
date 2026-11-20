# PTA VI — P'tite Teub Auto

Parodie 3D humoristique et semi-réaliste, jouable dans Safari (iPhone) — Godot 4.7, rendu Compatibility, export Web sans threads.

- **V0.2** (racine du site) : appartement de Yannick explorable — chambre (lits superposés), salon avec verrière, cuisine, salle de bain, entrée ; collisions murs/meubles, caméra 3e personne avec collisions, joystick tactile ; affiches de football originales.
- **V0.1** : conservée sur la branche `v0.1`, publiée sous `/v0.1/`.

## Tests
- `godot --headless --path . -- --autotest=1 --quitdone=1` : parcours automatique de 15 points, détecte traversées de murs et caméra dans les murs.
- `python3 tools/test_web.py build/web <dossier_captures>` : Playwright (Chrome, viewport iPhone) — titre, joystick tactile, rotation caméra, autotest dans le navigateur, budgets (draw calls, primitives, mémoire textures).
- `python3 -I tools/make_assets.py assets` régénère textures et affiches (toutes originales, sans marque ni licence).

## Paramètres d'URL (tests)
`?autotest=1` · `?spawn=chambre|hall|sdb|salon|kitchen|verriere` · `?yaw=<deg>` · `?pitch=<deg>`
