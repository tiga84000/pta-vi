# PTA VI — P’tite Teub Auto

Petit GTA-like humoristique en 3D, jouable dans Safari (iPhone) et sur ordinateur.

- Moteur : Godot 4.7.2 stable, GDScript, rendu Compatibility (WebGL 2)
- Export : Web HTML5/WebAssembly **sans threads** (compatible GitHub Pages)
- Déploiement : GitHub Actions → GitHub Pages à chaque push sur `main`

## Prototype actuel
Écran d’accueil, bouton « Jouer », pièce 3D, personnage provisoire (capsule), joystick tactile
(gauche), caméra 3ᵉ personne (glisser à droite). Clavier : WASD / ZQSD / flèches.

## Test local
```
godot --headless --import
godot --headless --export-release "Web" build/web/index.html
python3 tools/test_web.py build/web ./shots   # Playwright + Chrome
```
