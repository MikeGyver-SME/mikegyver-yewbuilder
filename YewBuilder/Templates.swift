import Foundation

/// The built-in starter project: a minimal working Yew app (counter +
/// greeting). It ships as the default content for all five files so the
/// Build button works on first launch without typing anything.
///
/// Lessons from Mike's earlier Yew builds (see AGENTS.md) are baked in:
/// - Trunk.toml sets public_url = "./" and filehash = false, so the built
///   site works in a subfolder and filenames stay stable across rebuilds.
/// - index.html sets data-integrity="none" on both asset links, so a
///   Trunk fingerprint can never block the stylesheet after an upload.
/// - main.rs never uses std::time (it panics on wasm32) — there is no
///   clock in this starter at all.
enum Templates {
    static let cargoToml = """
[package]
name = "yewbuilder-app"
version = "0.1.0"
edition = "2021"

[dependencies]
yew = { version = "0.21", features = ["csr"] }
wasm-bindgen = "0.2"

[profile.release]
opt-level = 2
"""

    static let trunkToml = """
[build]
target = "index.html"
dist = "dist"
# Subfolder-safe: Trunk defaults to root-absolute paths ("/x.js"), which
# 404 when the site lives in a subfolder. "./" makes every rebuild emit
# relative paths, so no post-build fix is needed.
public_url = "./"
# Keep filenames stable across rebuilds so index.html and the uploaded
# files can never drift apart (no more hashed names).
filehash = false
"""

    static let indexHtml = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>YewBuilder App — MikeGyver Studio</title>
<link data-trunk rel="rust" data-wasm-opt="0" data-integrity="none" />
<link data-trunk rel="css" href="styles.css" data-integrity="none" />
</head>
<body>
<div id="app"></div>
</body>
</html>
"""

    static let stylesCss = """
* { box-sizing: border-box; }
body { margin: 0; background: #060d1f; color: #e8eefc; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
.wrap { max-width: 640px; margin: 0 auto; padding: 48px 20px; text-align: center; }
h1 { font-size: 36px; margin: 0 0 8px; }
p { color: #b9c6e8; line-height: 1.6; }
.count { font-size: 64px; font-weight: 800; color: #f5c542; margin: 16px 0; }
button { background: #f5c542; color: #111; border: 0; border-radius: 10px; padding: 12px 22px; font-size: 16px; font-weight: 700; cursor: pointer; }
button:active { transform: scale(0.97); }
footer { margin-top: 32px; color: #7e8fb5; font-size: 13px; }
"""

    static let mainRs = """
use yew::prelude::*;

#[function_component(App)]
fn app() -> Html {
    let count = use_state(|| 0);
    let onclick = {
        let count = count.clone();
        Callback::from(move |_| count.set(*count + 1))
    };
    html! {
        <div class="wrap">
            <h1>{ "Hello from Yew! \\u{1F680}" }</h1>
            <p>{ "Built on your iPhone with YewBuilder and deployed to MikeGyver Studio." }</p>
            <div class="count">{ *count }</div>
            <button {onclick}>{ "Tap me" }</button>
            <footer>{ "YewBuilder — MikeGyver Studio · Sharing is Caring" }</footer>
        </div>
    }
}

fn main() {
    yew::Renderer::<App>::new().render();
}
"""

    /// Default content for a file, by its project path.
    static func content(for path: String) -> String {
        switch path {
        case "Cargo.toml": return cargoToml
        case "Trunk.toml": return trunkToml
        case "index.html": return indexHtml
        case "styles.css": return stylesCss
        case "src/main.rs": return mainRs
        default: return ""
        }
    }
}
