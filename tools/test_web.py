"""Tests Playwright V0.2 (parcours tactile + autotest collisions/budgets). Test de fumée Playwright : charge l'export Web de PTA VI dans Chrome (viewport iPhone paysage),
clique sur JOUER, déplace le joystick tactile et vérifie les logs / erreurs console."""
import subprocess, sys, time, json
from playwright.sync_api import sync_playwright

web_dir = sys.argv[1]
out_dir = sys.argv[2]
port = 8765

server = subprocess.Popen([sys.executable, "-I", "-m", "http.server", str(port), "--directory", web_dir, "--bind", "127.0.0.1"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1.0)
logs, errors = [], []
result = {}
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(
            executable_path="/usr/bin/google-chrome",
            headless=True,
            args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                  "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"])
        ctx = browser.new_context(viewport={"width": 844, "height": 390}, device_scale_factor=2, has_touch=True, is_mobile=True,
                                  user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1")
        page = ctx.new_page()
        page.on("console", lambda m: logs.append(f"{m.type}: {m.text}"))
        page.on("pageerror", lambda e: errors.append(str(e)))
        t0 = time.time()
        page.goto(f"http://127.0.0.1:{port}/index.html")
        page.wait_for_selector("canvas", timeout=60000)
        result["canvas_after_s"] = round(time.time() - t0, 1)
        time.sleep(6)
        page.screenshot(path=f"{out_dir}/1_title.png")

        page.touchscreen.tap(422, 281)
        for _ in range(40):
            if any("jeu démarré" in l for l in logs):
                break
            time.sleep(0.5)
        result["game_started"] = any("jeu démarré" in l for l in logs)
        time.sleep(2)
        page.screenshot(path=f"{out_dir}/2_room.png")

        cdp = ctx.new_cdp_session(page)
        def touch(kind, x, y, pid=1):
            pts = [] if kind == "touchEnd" else [{"x": x, "y": y, "id": pid}]
            cdp.send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": pts})
        # joystick à gauche : pousser vers le haut (avancer)
        touch("touchStart", 120, 300)
        for i in range(1, 16):
            touch("touchMove", 120, 300 - i * 5)
            time.sleep(0.12)
        page.screenshot(path=f"{out_dir}/3_moving.png")
        time.sleep(1.2)
        touch("touchEnd", 0, 0)
        # rotation caméra à droite
        touch("touchStart", 600, 200, 2)
        for i in range(1, 12):
            touch("touchMove", 600 + i * 12, 200, 2)
            time.sleep(0.05)
        touch("touchEnd", 0, 0)
        time.sleep(0.8)
        page.screenshot(path=f"{out_dir}/4_after.png")

        # portrait : message de rotation
        page.set_viewport_size({"width": 390, "height": 844})
        time.sleep(1.5)
        page.screenshot(path=f"{out_dir}/5_portrait.png")

        # --- autotest embarqué : collisions, caméra, budgets de rendu ---
        page.close()
        page2 = ctx.new_page()
        logs2 = []
        page2.on("console", lambda m: logs2.append(m.text))
        page2.on("pageerror", lambda e: errors.append("autotest: " + str(e)))
        page2.goto(f"http://127.0.0.1:{port}/index.html?autotest=1")
        for _ in range(240):
            if any("[PTA-TEST] RESULT" in l for l in logs2):
                break
            page2.wait_for_timeout(1000)
        line = next((l for l in logs2 if "[PTA-TEST] RESULT" in l), None)
        result["autotest"] = json.loads(line.split("RESULT", 1)[1]) if line else None
        browser.close()
finally:
    server.terminate()

result["pos_logs"] = [l for l in logs if "[PTA] pos" in l][:5]
result["errors"] = errors
result["bad_console"] = [l for l in logs if l.startswith(("error", "warning")) and "GPU stall" not in l][:10]
print(json.dumps(result, ensure_ascii=False, indent=1))

import os
res = result.get("autotest") or {}
budgets = {
    "autotest_pass": bool(res.get("pass")),
    "draw_calls<=150": res.get("draw_calls_max", 9999) <= 150,
    "primitives<=80000": res.get("primitives_max", 10**9) <= 80000,
    "texture_mem<=64MB": res.get("texture_mem_mb", 999) <= 64,
    "game_started": result.get("game_started", False),
    "no_page_errors": not errors,
    "no_console_errors": not result["bad_console"],
}
sizes = {f: os.path.getsize(os.path.join(web_dir, f)) for f in ("index.pck", "index.wasm")}
print("BUDGETS", json.dumps(budgets), "SIZES", json.dumps(sizes))
sys.exit(0 if all(budgets.values()) else 1)
