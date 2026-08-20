// Slice 10.1 — the window, and nothing else.
//
// No commands, no plugins, no tool surface. The Rust tool layer (layer 1) is
// slice 10.2 onward; see context/features/10-migrate-to-tauri.md.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("PigeonEye failed to start");
}
