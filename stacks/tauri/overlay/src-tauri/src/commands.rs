// __NAME__ — tauri stack pack overlay (REQ-303/304). The `greet` command
// moved out of the generated lib.rs so lib.rs stays wiring-only.
#[tauri::command]
pub fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greet_names_the_caller() {
        assert_eq!(greet("Ada"), "Hello, Ada! You've been greeted from Rust!");
    }
}
