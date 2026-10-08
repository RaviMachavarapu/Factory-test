// __NAME__ — tauri stack pack overlay (REQ-303/304).
// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
mod commands;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|_app| {
            // REQ-390: a smoke run under SPECFLOW_SMOKE=1 starts up and
            // exits 0 without waiting on a window event loop, so the
            // release gate can prove the built app launches.
            if std::env::var("SPECFLOW_SMOKE").as_deref() == Ok("1") {
                std::process::exit(0);
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![commands::greet])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
