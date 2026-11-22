//! Filter and tree-search semantics shared by the tree and saved-filter counts.

use crate::process::ProcessRecord;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum SearchAspect {
    #[default]
    All,
    Name,
    Pid,
    User,
    Command,
    Path,
    Port,
}

impl SearchAspect {
    pub const ALL: [Self; 7] = [
        Self::All,
        Self::Name,
        Self::Pid,
        Self::User,
        Self::Command,
        Self::Path,
        Self::Port,
    ];

    pub const fn name(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Name => "name",
            Self::Pid => "pid",
            Self::User => "user",
            Self::Command => "command",
            Self::Path => "path",
            Self::Port => "port",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|aspect| aspect.name() == value)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub struct SearchOptions {
    pub match_case: bool,
    pub whole_word: bool,
    pub aspect: SearchAspect,
}

impl SearchOptions {
    /// The stored form of a saved filter: `aspect:query`.
    pub fn saved_query(self, query: &str) -> String {
        format!("{}:{query}", self.aspect.name())
    }

    pub fn with_aspect(self, aspect: SearchAspect) -> Self {
        Self { aspect, ..self }
    }
}

/// A matcher for one query: plain substring, or whole word (bounded by
/// characters other than ASCII letters, digits and `_`).
#[derive(Clone, Debug)]
pub struct TextMatcher {
    needle: Vec<char>,
    match_case: bool,
    whole_word: bool,
}

fn is_word(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

impl TextMatcher {
    pub fn new(query: &str, match_case: bool, whole_word: bool) -> Self {
        let needle = if match_case {
            query.chars().collect()
        } else {
            query.chars().flat_map(char::to_lowercase).collect()
        };
        Self {
            needle,
            match_case,
            whole_word,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.needle.is_empty()
    }

    pub fn matches(&self, value: &str) -> bool {
        if self.needle.is_empty() {
            return true;
        }
        self.first_match_utf16(value).is_some()
    }

    /// The first match in `value` as a UTF-16 range, for highlighting.
    pub fn first_match_utf16(&self, value: &str) -> Option<(usize, usize)> {
        if self.needle.is_empty() || value.is_empty() {
            return None;
        }
        // Folded characters with the UTF-16 offset of the original character
        // each one came from.
        let mut folded: Vec<(char, usize, usize)> = Vec::with_capacity(value.len());
        let mut offset = 0usize;
        for original in value.chars() {
            let width = original.len_utf16();
            if self.match_case {
                folded.push((original, offset, offset + width));
            } else {
                for lowered in original.to_lowercase() {
                    folded.push((lowered, offset, offset + width));
                }
            }
            offset += width;
        }
        let n = self.needle.len();
        if folded.len() < n {
            return None;
        }
        for start in 0..=folded.len() - n {
            if folded[start..start + n]
                .iter()
                .zip(&self.needle)
                .all(|((c, _, _), needle)| c == needle)
            {
                if self.whole_word {
                    let before_ok = start == 0 || !is_word(folded[start - 1].0);
                    let after_ok = start + n == folded.len() || !is_word(folded[start + n].0);
                    if !(before_ok && after_ok) {
                        continue;
                    }
                }
                return Some((folded[start].1, folded[start + n - 1].2));
            }
        }
        None
    }

    pub fn matches_any<'a>(&self, fields: impl IntoIterator<Item = &'a str>) -> bool {
        fields.into_iter().any(|field| self.matches(field))
    }
}

/// A parsed filter: its text and the options it applies.
#[derive(Clone, Debug)]
pub struct SearchQuery {
    pub text: String,
    pub options: SearchOptions,
    matcher: TextMatcher,
}

impl SearchQuery {
    pub fn new(text: impl Into<String>, options: SearchOptions) -> Self {
        let text = text.into();
        let matcher = TextMatcher::new(&text, options.match_case, options.whole_word);
        Self {
            text,
            options,
            matcher,
        }
    }

    /// Reads typed prefixes: `:8080` is `port:8080`, and `name:foo`,
    /// `pid:12`, … select their aspect.
    pub fn parse(value: &str, options: SearchOptions) -> Self {
        let text = value.trim();
        if let Some(rest) = text.strip_prefix(':')
            && !rest.is_empty()
            && rest.bytes().all(|b| b.is_ascii_digit())
        {
            return Self::new(rest, options.with_aspect(SearchAspect::Port));
        }
        for aspect in SearchAspect::ALL {
            let prefix = format!("{}:", aspect.name());
            if let Some(rest) = text.strip_prefix(&prefix) {
                return Self::new(rest.trim(), options.with_aspect(aspect));
            }
        }
        Self::new(text, options)
    }

    /// The port `text` names, or None when it is not a valid port number.
    pub fn port(&self) -> Option<u16> {
        if self.text.is_empty() || !self.text.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        let port: u32 = self.text.parse().ok()?;
        (1..=65535).contains(&port).then_some(port as u16)
    }

    pub fn matches(&self, record: &ProcessRecord) -> bool {
        if self.text.is_empty() {
            return true;
        }
        let port = self.port();
        if self.options.aspect == SearchAspect::Port {
            return port.is_some_and(|port| {
                record
                    .local_ports
                    .as_ref()
                    .is_some_and(|ports| ports.contains(&port))
            });
        }
        // A bare number in the default search also finds the processes using
        // that port, so typing `8080` answers "who is on 8080?".
        if self.options.aspect == SearchAspect::All
            && let Some(port) = port
            && record
                .local_ports
                .as_ref()
                .is_some_and(|ports| ports.contains(&port))
        {
            return true;
        }
        let pid = record.pid.to_string();
        let uid = record.uid.to_string();
        match self.options.aspect {
            SearchAspect::All => self.matcher.matches_any([
                record.display_name(),
                pid.as_str(),
                record.executable_path.as_str(),
                record.command_line.as_str(),
                record.app_bundle_path.as_str(),
            ]),
            SearchAspect::Name => self.matcher.matches(record.display_name()),
            SearchAspect::Pid => self.matcher.matches(&pid),
            SearchAspect::User => self
                .matcher
                .matches_any([record.user.as_str(), uid.as_str()]),
            SearchAspect::Command => self.matcher.matches(&record.command_line),
            SearchAspect::Path => self.matcher.matches_any([
                record.executable_path.as_str(),
                record.app_bundle_path.as_str(),
            ]),
            SearchAspect::Port => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn record() -> ProcessRecord {
        ProcessRecord {
            pid: 4242,
            uid: 1000,
            user: "alice".into(),
            name: "postgres".into(),
            executable_path: "/usr/bin/postgres".into(),
            command_line: "postgres -D /var/lib/data".into(),
            local_ports: Some(Arc::from(vec![5432u16, 40000])),
            ..ProcessRecord::default()
        }
    }

    #[test]
    fn prefixes_select_aspects() {
        let query = SearchQuery::parse(":5432", SearchOptions::default());
        assert_eq!(query.options.aspect, SearchAspect::Port);
        assert_eq!(query.text, "5432");
        assert!(query.matches(&record()));
        let query = SearchQuery::parse("user: alice", SearchOptions::default());
        assert_eq!(query.options.aspect, SearchAspect::User);
        assert_eq!(query.text, "alice");
        assert!(query.matches(&record()));
        assert!(SearchQuery::parse("pid:424", SearchOptions::default()).matches(&record()));
        assert!(!SearchQuery::parse("name:424", SearchOptions::default()).matches(&record()));
    }

    #[test]
    fn bare_numbers_also_find_ports() {
        assert!(SearchQuery::parse("40000", SearchOptions::default()).matches(&record()));
        assert!(!SearchQuery::parse("port:99999", SearchOptions::default()).matches(&record()));
    }

    #[test]
    fn whole_word_and_case() {
        let options = SearchOptions {
            whole_word: true,
            ..SearchOptions::default()
        };
        assert!(SearchQuery::parse("data", options).matches(&record()));
        assert!(!SearchQuery::parse("dat", options).matches(&record()));
        let options = SearchOptions {
            match_case: true,
            ..SearchOptions::default()
        };
        assert!(!SearchQuery::parse("POSTGRES", options).matches(&record()));
        assert!(SearchQuery::parse("POSTGRES", SearchOptions::default()).matches(&record()));
    }

    #[test]
    fn first_match_reports_utf16_offsets() {
        let matcher = TextMatcher::new("gres", false, false);
        assert_eq!(matcher.first_match_utf16("PostGRES"), Some((4, 8)));
        let matcher = TextMatcher::new("b", false, true);
        assert_eq!(matcher.first_match_utf16("ab b"), Some((3, 4)));
    }
}
