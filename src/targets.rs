use std::{env, path::Path, process::Command};

enum Target<'a> {
    Absolute(&'a str),
    HomeRelative(&'a str),
    App(&'a str),
    Website(&'a str),
}

/// Count targets without opening them or checking whether they exist.
pub fn validate(text: &str) -> Result<usize, String> {
    visit_targets(text, |_| Ok(()))
}

fn visit_targets(
    text: &str,
    mut visit: impl FnMut(Target<'_>) -> Result<(), String>,
) -> Result<usize, String> {
    let mut count = 0;
    let mut errors = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let outer_space = |c: char| c == '\t' || (c.is_whitespace() && !c.is_control());
        let line = line.trim_start_matches(outer_space);
        let line = if line.starts_with('/') || line.starts_with("~/") {
            line
        } else {
            line.trim_end_matches(outer_space)
        };
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        match parse_target(line).and_then(&mut visit) {
            Ok(()) => count += 1,
            Err(error) => errors.push(format!("Line {}: {error}", index + 1)),
        }
    }
    if errors.is_empty() {
        Ok(count)
    } else {
        Err(errors.join("\n"))
    }
}

fn parse_target(line: &str) -> Result<Target<'_>, String> {
    if line.chars().any(char::is_control) {
        return Err("target contains a control character".into());
    }
    if line.starts_with('/') {
        return Ok(Target::Absolute(line));
    }
    if let Some(path) = line.strip_prefix("~/") {
        return Ok(Target::HomeRelative(path));
    }
    if let Some(name) = line.strip_prefix("app:") {
        let name = name.trim();
        if name.is_empty() {
            return Err("missing app name after app:".into());
        }
        return Ok(Target::App(name));
    }
    if let Some((scheme, rest)) = line.split_once("://")
        && (scheme.eq_ignore_ascii_case("http") || scheme.eq_ignore_ascii_case("https"))
    {
        return if valid_website(rest) {
            Ok(Target::Website(line))
        } else {
            Err("invalid HTTP(S) URL; expected a host and a properly escaped URL".into())
        };
    }
    Err("expected an absolute path, ~/ path, app:Name, or http(s) URL".into())
}

// Check obvious URL syntax errors; leave URL interpretation to the system browser.
fn valid_website(rest: &str) -> bool {
    if rest
        .chars()
        .any(|c| c.is_whitespace() || "\\\"<>`{}|".contains(c))
        || rest.split('%').skip(1).any(|part| {
            !part
                .as_bytes()
                .get(..2)
                .is_some_and(|pair| pair.iter().all(u8::is_ascii_hexdigit))
        })
    {
        return false;
    }

    let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
    let host_port = match authority.split_once('@') {
        Some((_, host_port)) => host_port,
        None => authority,
    };
    if host_port.contains('@') {
        return false;
    }
    let port = if let Some(bracketed) = host_port.strip_prefix('[') {
        let Some((address, suffix)) = bracketed.split_once(']') else {
            return false;
        };
        if address.parse::<std::net::Ipv6Addr>().is_err() {
            return false;
        }
        match suffix.strip_prefix(':') {
            port @ Some(_) => port,
            None if suffix.is_empty() => None,
            None => return false,
        }
    } else {
        let (host, port) = match host_port.split_once(':') {
            Some((host, port)) => (host, Some(port)),
            None => (host_port, None),
        };
        if host.trim_end_matches('.').is_empty()
            || !host
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || !c.is_ascii() || ".-_%".contains(c))
        {
            return false;
        }
        port
    };
    match port {
        None => true,
        Some(port) => port.bytes().all(|b| b.is_ascii_digit()) && port.parse::<u16>().is_ok(),
    }
}

/// Open each valid target in order, then report any failures by line number.
pub fn launch(text: &str) -> Result<(), String> {
    let home = env::var_os("HOME");
    launch_with(text, home.as_deref().map(Path::new), run_open)
}

fn launch_with(
    text: &str,
    home: Option<&Path>,
    mut run: impl FnMut(Command) -> Result<(), String>,
) -> Result<(), String> {
    visit_targets(text, |target| {
        let mut command = Command::new("/usr/bin/open");
        match target {
            Target::Absolute(path) => command.arg(path),
            Target::HomeRelative(path) => {
                let home = home
                    .filter(|path| path.is_absolute())
                    .ok_or("cannot expand ~/: HOME must be an absolute path")?;
                // A repeated slash after ~/ must not replace the home directory in join().
                command.arg(home.join(path.trim_start_matches('/')))
            }
            Target::App(name) => command.arg("-a").arg(name),
            Target::Website(url) => command.arg("-u").arg(url),
        };
        run(command)
    })
    .map(|_| ())
}

fn run_open(mut command: Command) -> Result<(), String> {
    let output = command
        .output()
        .map_err(|error| format!("could not run open: {error}"))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    let detail = stderr.trim();
    if detail.is_empty() {
        Err(format!("open failed ({})", output.status))
    } else {
        Err(format!("open failed ({}): {detail}", output.status))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;

    #[test]
    fn passes_literal_arguments_to_open_in_input_order() {
        let text = "/Applications/My App.app\n~//Some Docs\napp:-n; $(echo untouched)\nhttps://example.org/?x=1&y=2";
        let mut arguments = Vec::new();
        assert_eq!(
            launch_with(text, Some(Path::new("/Users/Test Person")), |command| {
                assert_eq!(command.get_program(), "/usr/bin/open");
                arguments.push(command.get_args().map(OsString::from).collect::<Vec<_>>());
                Ok(())
            }),
            Ok(())
        );
        assert_eq!(
            arguments,
            [
                vec!["/Applications/My App.app"],
                vec!["/Users/Test Person/Some Docs"],
                vec!["-a", "-n; $(echo untouched)"],
                vec!["-u", "https://example.org/?x=1&y=2"],
            ]
        );
    }

    #[test]
    fn preserves_trailing_spaces_in_file_paths() {
        let mut paths = Vec::new();
        launch_with(
            "/tmp/absolute \n~/relative  \r\n",
            Some(Path::new("/Users/Test")),
            |command| {
                paths.push(command.get_args().next().unwrap().to_owned());
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(paths, ["/tmp/absolute ", "/Users/Test/relative  "]);
    }

    #[test]
    fn continues_after_bad_lines_and_failed_opens() {
        let mut attempts = Vec::new();
        let error = launch_with("# comment\n/fails\ninvalid\n/works", None, |command| {
            let path = command.get_args().next().unwrap().to_owned();
            let result = if path == "/fails" {
                Err("open failed: test error".into())
            } else {
                Ok(())
            };
            attempts.push(path);
            result
        })
        .unwrap_err();
        assert_eq!(attempts, ["/fails", "/works"]);
        assert!(error.contains("Line 2: open failed: test error"), "{error}");
        assert!(error.contains("Line 3:"), "{error}");
        assert!(!error.contains("Line 4:"), "{error}");
    }

    #[test]
    fn refuses_home_expansion_without_an_absolute_home() {
        for home in [None, Some(Path::new("relative"))] {
            let error = launch_with("~/document", home, |_| {
                panic!("an unresolved home path must not be opened")
            })
            .unwrap_err();
            assert!(
                error.contains("Line 1:") && error.contains("HOME"),
                "{error}"
            );
        }
    }

    #[test]
    fn reports_a_child_process_failure() {
        let error = run_open(Command::new("/usr/bin/false")).unwrap_err();
        assert!(error.contains("exit status: 1"), "{error}");
    }

    #[test]
    fn launching_only_ignored_lines_succeeds_without_opening_anything() {
        assert_eq!(launch("\n # ignored"), Ok(()));
    }

    #[test]
    fn counts_path_entries_not_whole_line_comments() {
        assert_eq!(
            validate(
                "\r\n  # profile\r\n/Applications/My App.app\r\n~/My Documents\n\t\n/dir/#literal"
            ),
            Ok(3)
        );
    }

    #[test]
    fn counts_app_names_and_websites() {
        assert_eq!(
            validate(
                "app:Visual Studio Code\nhttp://localhost:8080\nhttps://[::1]/a%20b?q=x#section"
            ),
            Ok(3)
        );
    }

    #[test]
    fn rejects_malformed_app_names_and_websites() {
        for target in [
            "app:",
            "app:   ",
            "https://",
            "https:///path",
            "http://?query",
            "https://example.org/a b",
            "https://example.org\\path",
            "https://example.org:bad",
            "https://[bad]",
            "https://example.org/a%2x",
            "ftp://example.org",
        ] {
            let error = validate(target).expect_err(target);
            if !target.starts_with("ftp:") {
                assert!(
                    error.contains("invalid HTTP(S) URL") || error.contains("missing app name"),
                    "{target:?}: {error}"
                );
            }
        }
    }

    #[test]
    fn accepts_an_empty_list() {
        assert_eq!(validate("  # no entries\n\n"), Ok(0));
    }

    #[test]
    fn reports_every_malformed_path_by_line_number() {
        let err = validate("# comment\nrelative\n/valid\n~someone/path\n/bad\0path").unwrap_err();
        assert!(err.contains("Line 2:"), "{err}");
        assert!(!err.contains("Line 3:"), "{err}");
        assert!(err.contains("Line 4:"), "{err}");
        assert!(err.contains("Line 5:"), "{err}");
    }
}
