use std::path::Path;

/// 对应 bash clean_target()
pub fn clean_target(target: &Path) {
    if target.is_symlink() {
        let _ = std::fs::remove_file(target);
        return;
    }
    if target.is_dir() {
        let _ = std::fs::remove_dir_all(target);
        return;
    }
    if target.is_file() {
        let _ = std::fs::remove_file(target);
    }
}

/// 递归复制，保留权限，类似 cp -aL
pub fn copy_recursive(src: &Path, dest: &Path) -> std::io::Result<()> {
    if src.is_dir() && !src.is_symlink() {
        std::fs::create_dir_all(dest)?;
        for entry in std::fs::read_dir(src)? {
            let entry = entry?;
            let ty = entry.file_type()?;
            let from = entry.path();
            let to = dest.join(entry.file_name());
            if ty.is_dir() {
                copy_recursive(&from, &to)?;
            } else {
                // -L: follow symlink, copy file content
                let real = if ty.is_symlink() {
                    std::fs::canonicalize(&from).unwrap_or(from.clone())
                } else {
                    from.clone()
                };
                if real.is_dir() {
                    copy_recursive(&real, &to)?;
                } else {
                    if let Some(parent) = to.parent() {
                        std::fs::create_dir_all(parent)?;
                    }
                    std::fs::copy(&real, &to)?;
                }
            }
        }
    } else {
        // file or symlink to file
        let real = if src.is_symlink() {
            std::fs::canonicalize(src).unwrap_or(src.to_path_buf())
        } else {
            src.to_path_buf()
        };
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)?;
        }
        if real.is_dir() {
            copy_recursive(&real, dest)?;
        } else {
            std::fs::copy(&real, dest)?;
        }
    }
    Ok(())
}

/// 显示宽度（CJK 等全角字符算 2 列），供表格对齐
pub fn display_width(s: &str) -> usize {
    s.chars()
        .map(|c| {
            let u = c as u32;
            if (0x1100..=0x115F).contains(&u)
                || (0x2E80..=0xA4CF).contains(&u)
                || (0xAC00..=0xD7A3).contains(&u)
                || (0xF900..=0xFAFF).contains(&u)
                || (0xFE30..=0xFE4F).contains(&u)
                || (0xFF00..=0xFF60).contains(&u)
                || (0xFFE0..=0xFFE6).contains(&u)
                || (0x20000..=0x3FFFD).contains(&u)
            {
                2
            } else {
                1
            }
        })
        .sum()
}

/// 按显示宽度把字符串补空格到 w 列
pub fn pad_display(txt: &str, w: usize) -> String {
    let dw = display_width(txt);
    if dw >= w {
        txt.to_string()
    } else {
        format!("{}{}", txt, " ".repeat(w - dw))
    }
}

pub fn is_empty_dir(p: &Path) -> bool {
    if !p.is_dir() {
        return false;
    }
    match std::fs::read_dir(p) {
        Ok(mut it) => it.next().is_none(),
        Err(_) => true,
    }
}
