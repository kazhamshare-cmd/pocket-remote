use std::process::Command;

#[cfg(target_os = "macos")]
use core_foundation::base::TCFType;

/// アクセシビリティ権限をチェック
#[cfg(target_os = "macos")]
pub fn check_accessibility_permission() -> bool {
    // AppleScriptで簡単なキー操作をテストして権限を確認
    let output = Command::new("osascript")
        .arg("-e")
        .arg(r#"
            try
                tell application "System Events"
                    -- 何もしないがアクセス権限が必要
                    set frontApp to name of first application process whose frontmost is true
                end tell
                return "ok"
            on error errMsg
                return "error"
            end try
        "#)
        .output();

    match output {
        Ok(o) => {
            let result = String::from_utf8_lossy(&o.stdout);
            result.trim() == "ok"
        }
        Err(_) => false,
    }
}

#[cfg(not(target_os = "macos"))]
pub fn check_accessibility_permission() -> bool {
    true // macOS以外では常にtrue
}

/// アクセシビリティ設定画面を開く
#[cfg(target_os = "macos")]
pub fn open_accessibility_settings() -> bool {
    Command::new("open")
        .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

#[cfg(not(target_os = "macos"))]
pub fn open_accessibility_settings() -> bool {
    false
}

/// アクセシビリティ権限を要求（システムダイアログを表示）
#[cfg(target_os = "macos")]
pub fn request_accessibility_permission() -> bool {
    // tccutil でリセットしてから再度プロンプトを表示することもできるが、
    // 通常はユーザーに手動で設定してもらう必要がある

    // AXIsProcessTrustedWithOptions を使用してシステムダイアログを表示
    use std::ptr;

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrustedWithOptions(options: *const std::ffi::c_void) -> bool;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFDictionaryCreate(
            allocator: *const std::ffi::c_void,
            keys: *const *const std::ffi::c_void,
            values: *const *const std::ffi::c_void,
            numValues: isize,
            keyCallBacks: *const std::ffi::c_void,
            valueCallBacks: *const std::ffi::c_void,
        ) -> *const std::ffi::c_void;
        fn CFRelease(cf: *const std::ffi::c_void);

        static kCFBooleanTrue: *const std::ffi::c_void;
        static kCFTypeDictionaryKeyCallBacks: std::ffi::c_void;
        static kCFTypeDictionaryValueCallBacks: std::ffi::c_void;
    }

    // kAXTrustedCheckOptionPrompt キー
    const K_AX_TRUSTED_CHECK_OPTION_PROMPT: &[u8] = b"AXTrustedCheckOptionPrompt\0";

    unsafe {
        // CFString を作成する代わりに、直接キーを使用
        let key_str = core_foundation::string::CFString::new("AXTrustedCheckOptionPrompt");
        let key_ptr = key_str.as_concrete_TypeRef() as *const std::ffi::c_void;

        let keys = [key_ptr];
        let values = [kCFBooleanTrue];

        let options = CFDictionaryCreate(
            ptr::null(),
            keys.as_ptr(),
            values.as_ptr(),
            1,
            &kCFTypeDictionaryKeyCallBacks as *const _ as *const std::ffi::c_void,
            &kCFTypeDictionaryValueCallBacks as *const _ as *const std::ffi::c_void,
        );

        let result = AXIsProcessTrustedWithOptions(options);

        if !options.is_null() {
            CFRelease(options);
        }

        result
    }
}

#[cfg(not(target_os = "macos"))]
pub fn request_accessibility_permission() -> bool {
    true
}
