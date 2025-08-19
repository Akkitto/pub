#!/usr/bin/env nu
############################################################################
# Copyright © 2025  Daniel Braniewski                                      #
#                                                                          #
# This program is free software: you can redistribute it and/or modify     #
# it under the terms of the GNU Affero General Public License as           #
# published by the Free Software Foundation, either version 3 of the       #
# License, or (at your option) any later version.                          #
#                                                                          #
# This program is distributed in the hope that it will be useful,          #
# but WITHOUT ANY WARRANTY; without even the implied warranty of           #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the             #
# GNU Affero General Public License for more details.                      #
#                                                                          #
# You should have received a copy of the GNU Affero General Public License #
# along with this program.  If not, see <https://www.gnu.org/licenses/>.   #
############################################################################


# - Scripts & def main: https://www.nushell.sh/book/scripts.html
# - glob: https://www.nushell.sh/commands/docs/glob.html
# - open --raw / decode: https://www.nushell.sh/commands/docs/open.html / https://www.nushell.sh/book/loading_data.html
# - save --force: https://www.nushell.sh/commands/docs/save.html
# - mkdir (creates parents): https://www.nushell.sh/commands/docs/mkdir.html
# - Strings: starts-with, index-of, substring, replace -r:
#   https://www.nushell.sh/commands/docs/str_starts-with.html
#   https://www.nushell.sh/commands/docs/str_index-of.html
#   https://www.nushell.sh/commands/docs/str_substring.html
# - Path ops: relative-to, parse, join, dirname, exists:
#   https://www.nushell.sh/commands/docs/path.html

# Usage:
#   use textman
#   textmanremember-tag-ws demo.yaml ws.json
module textman {

  # Remembers the trailing whitespace of each line in the current top-level .content string.
  export def remember-tag-ws [
    yaml_path: string,         # path to the YAML file
    sidecar_path: string       # path to write the JSON array of base64-encoded EOL whitespace
  ] {
    # Read and parse YAML to structured data (Nu auto-detects YAML; 'from yaml' is explicit)
    # docs: open --raw/structured https://www.nushell.sh/commands/docs/open.html
    # docs: from yaml https://www.nushell.sh/commands/docs/from_yaml.html
    let doc = (open $yaml_path)

    if not ($doc | get content | describe | str contains "string") {
      error make --unspanned { msg: ".content is missing or not a string" }  # docs: error make https://www.nushell.sh/book/creating_errors.html
    }

    # Split lines and capture trailing spaces/tabs per line.
    # docs: split row https://www.nushell.sh/commands/docs/split_row.html
    # docs: str replace -r (regex) https://www.nushell.sh/commands/docs/str_replace.html
    # docs: encode base64 https://www.nushell.sh/commands/docs/encode_base64.html
    let tails = (
      ($doc | get content)
      | lines
      | each {|l| $l | str replace --regex '^(.*?)([ \t]*)$' '$2' | encode base64 }
    )

    # Persist as JSON
    # docs: to json https://www.nushell.sh/commands/docs/to_json.html
    # docs: save https://www.nushell.sh/commands/docs/save.html
    $tails | to json | save --force $sidecar_path
  }

  export def save-encoded [ path: path ]: list<string> -> string {
    str join (char newline)
    | lines
    | each { |line|
      if ($line | is-empty) or ($line =~ '^[[:blank:]]+$') {
        ""
      } else {
        $line
      }
    }
    | str join (char newline)
    | encode --ignore-errors iso-8859-2 | decode
    | tee { ||
      save --force $path
    }
  }

  # Restores remembered trailing whitespace onto .content.
  # Only works with YAML source.
  # Works with either:
  #   - literal block:   tag: | ...
  #   - quoted one-liner: tag: "line1\nline2"
  #
  # Docs:
  # open/from yaml: https://www.nushell.sh/commands/docs/open.html , https://www.nushell.sh/commands/docs/from_yaml.html
  # lines: https://www.nushell.sh/commands/docs/lines.html
  # split row: https://www.nushell.sh/commands/docs/split_row.html
  # str replace (regex): https://www.nushell.sh/commands/docs/str_replace.html , regex notes: https://www.nushell.sh/book/regular_expressions.html
  # str trim: https://www.nushell.sh/commands/docs/str_trim.html
  # enumerate: https://www.nushell.sh/commands/docs/enumerate.html
  # update (list index): https://www.nushell.sh/commands/docs/update.html
  # str join: https://www.nushell.sh/commands/docs/str_join.html
  # save: https://www.nushell.sh/commands/docs/save.html
  # decode base64 / decode utf-8: https://www.nushell.sh/commands/docs/decode_base64.html , https://www.nushell.sh/commands/docs/decode.html
  export def restore-tag-ws [
    yaml_path: string,   # YAML file to patch
    sidecar_path: string # JSON array of base64 tails from remember-tag-ws
  ] {
    # Load remembered tails and decode to plain strings
    let tails = (
      open $sidecar_path
      | each {|b64| $b64 | decode base64 | decode }
    )

    # Parse YAML to get the logical .content string (quoted "\n" become real LFs)
    let tag_val = (open $yaml_path | get content)
    let body_lines = ($tag_val | split row "\n")

    # Rebuild each line = (trim current trailing ws) + (remembered tail)
    let rebuilt_lines = (
      $body_lines
      | enumerate
      | each {|it|
          let idx = $it.index
          let body = ($it.item | str replace -r '[ \t]+$' '')
          let tail = (if $idx < ($tails | length) { $tails | get $idx } else { "" })
          $body + $tail
        }
    )

    # Read YAML text to surgically patch header+content
    mut lines = (open $yaml_path --raw | lines)

    # Helper: N spaces
    def _spaces [n:int] { (0..<$n | each {" "} | str join "") }

    # Find either a block header or a double-quoted one-liner
    mut start_idx = -1
    mut content_indent = 0
    mut header_mode = "none"  # "block" | "quoted"

    for row in ($lines | enumerate) {
      let ln = $row.item
      if ($ln =~ '^\s*content:\s*\|[+-]?\s*(?:#.*)?$') {
        let leading_ws = ($ln | str replace -r '^(\s*).*' '$1')
        $start_idx = $row.index
        $content_indent = ($leading_ws | str length) + 2
        $header_mode = "block"
        break
      } else if ($ln =~ '^\s*content:\s*"(?:[^"\\]|\\.)*"\s*(?:#.*)?$') {
        let leading_ws = ($ln | str replace -r '^(\s*).*' '$1')
        $start_idx = $row.index
        $content_indent = ($leading_ws | str length) + 2
        $header_mode = "quoted"
        break
      }
    }

    if $header_mode == "none" {
      error make --unspanned { msg: "Could not find top-level `content:` as either a pipe block or double-quoted one-liner." }
    }

    let ind = (_spaces $content_indent)
    let new_block_lines = ($rebuilt_lines | each {|l| $ind + $l })

    if $header_mode == "block" {
      # ---- SCANNER ----
      # Advance until a *non-blank* line dedents; blank lines stay inside the block.
      mut i = $start_idx + 1
      let n = ($lines | length)
      while $i < $n {
        let cur = ($lines | get $i)
        let cur_trim = ($cur | str trim)                       # blank line => stay in block
        if $cur_trim == "" {
          $i = $i + 1
          continue
        }
        let cur_indent = ($cur | str replace -r '^(\s*).*' '$1' | str length)
        if $cur_indent < $content_indent { break }
        $i = $i + 1
      }
      let end_idx = $i

      let head = ($lines | take ($start_idx + 1))   # keep header 'content: |'
      let tail = ($lines | skip $end_idx)
      $lines = ([$head, $new_block_lines, $tail] | flatten)

    } else if $header_mode == "quoted" {
      # Replace the single quoted line with: header 'content: |' + block lines
      let leading_ws = (($lines | get $start_idx) | str replace -r '^(\s*).*' '$1')
      let header_line = ($leading_ws + 'content: |')
      let head = ($lines | take $start_idx)
      let tail = ($lines | skip ($start_idx + 1))
      $lines = ([$head, [$header_line], $new_block_lines, $tail] | flatten)
    }

    $lines
    | save-encoded $yaml_path
  }
}

use textman

# local helper to slice header/content given start/end delimiters
def slice-front-matter [
  text: string
  start: string
  end: string
] {
  if ($text | str starts-with $start) {
    let from = ($start | str length)
    let idx  = ($text | str index-of $end --range $from..)
    if $idx < 0 {
      null
    } else {
      let header = ($text | str substring $from..$idx)
      let cut    = $idx + ($end | str length)
      let rest0  = ($text | str substring $cut..)
      # trim leading CR/LF after end delimiter
      let content   = ($rest0 | str replace -r '^(\r\n|\n|\r)+' '')
      { header: $header, content: $content }
    }
  } else { null }
}

# Add this next to your helpers.
# Extract & parse front matter; return a structured record you can reuse later.
#
# Returns a record:
# { format: 'toml' | 'yaml' | null
# , raw:    string | null   # front matter text without delimiters
# , meta:   any | null      # parsed metadata (record for typical mappings)
# , content:   string          # content without front matter
# }
#
# Parsers:
# - from toml: https://www.nushell.sh/commands/docs/from_toml.html
# - from yaml: https://www.nushell.sh/commands/docs/from_yaml.html
# Error handling:
# - try/catch: https://www.nushell.sh/commands/docs/try.html
#
# Returns:
# string -> record<
#   format: string
#   raw: string
#   meta: record<
#     title: string
#     date: datetime
#     taxonomies: record<
#       categories: list<string>
#       tags: list<string>
#     >
#   >
#   content: string
# >
def extract-front-matter [ s?: string ]: string -> record<format: string, raw: string, meta: record<title: string, date: datetime, taxonomies: record<categories: list<string>, tags: list<string>>>, content: string> {
  let it = $in
  let txt = match $s {
    null => $it
    _ => $s
  }

  # Try TOML first (CRLF and LF)
  let t1 = (slice-front-matter $txt "+++\n" "\n+++")
  if $t1 != null {
    let parsed = (try { $t1.header | from toml } catch { null })
    { format: 'toml', raw: $t1.header, meta: $parsed, content: $t1.content }
  } else {
    let t2 = (slice-front-matter $txt "+++\r\n" "\r\n+++")
    if $t2 != null {
      let parsed = (try { $t2.header | from toml } catch { null })
      { format: 'toml', raw: $t2.header, meta: $parsed, content: $t2.content }
    } else {
      # Then YAML (CRLF and LF)
      let y1 = (slice-front-matter $txt "---\n" "\n---")
      if $y1 != null {
        let parsed = (try { $y1.header | from yaml } catch { null })
        { format: 'yaml', raw: $y1.header, meta: $parsed, content: $y1.content }
      } else {
        let y2 = (slice-front-matter $txt "---\r\n" "\r\n---")
        if $y2 != null {
          let parsed = (try { $y2.header | from yaml } catch { null })
          { format: 'yaml', raw: $y2.header, meta: $parsed, content: $y2.content }
        } else {
          # No front matter
          { format: null, raw: null, meta: null, content: $txt }
        }
      }
    }
  }
}

# --- Front matter stripping helpers -----------------------------------------

# strip-delimited: if string starts with `start`, cut up to the first `end`, then trim leading CR/LF.
def strip-delimited [
  s: string,
  start: string,
  end: string
] {
  if ( $s | str starts-with $start ) {
    # find closing delimiter after the opening
    let from = ($start | str length)
    let idx  = ($s | str index-of $end --range $from..)
    if $idx < 0 { null } else {
      let cut  = $idx + ($end | str length)
      let rest = ($s | str substring $cut..)
      # remove any leading \r or \n after the end delimiter
      $rest | str replace -r '^(\r\n|\n|\r)+' ''
    }
  } else { null }
}

# strip-front-matter: try TOML +++ ... +++ and YAML --- ... --- (CRLF or LF).
def strip-front-matter [s: string] {
  let t1 = (strip-delimited $s "+++\n" "\n+++")
  if $t1 != null { $t1 } else {
    let t2 = (strip-delimited $s "+++\r\n" "\r\n+++")
    if $t2 != null { $t2 } else {
      let y1 = (strip-delimited $s "---\n" "\n---")
      if $y1 != null { $y1 } else {
        let y2 = (strip-delimited $s "---\r\n" "\r\n---")
        if $y2 != null { $y2 } else { $s }
      }
    }
  }
}

# --- Main entrypoint ---------------------------------------------------------

# Flags mirror your Kotlin system properties and defaults.
def main [
  --content-root:            path = "content"          # root to scan for .md
  --output-root:             path = "static/raw"       # where .yaml + index.html go
  --output-whitespace:       path = "whitespace.json"  # path to .whitespace metadata holding temporary file
  --strip-front-matter            = true               # strip Zola front matter
  --template-article-file: string = ''                 # path to template filled with content and metdata from markdown post
  --template-article:      string = '{kind: Article, version: 1, metadata: {}, content: ""}' # template filled with content and metdata from markdown post as plain NUON string
] {
  let abs_content = ($content_root | path expand)
  let abs_output  = ($output_root  | path expand)

  if not ($abs_content | path exists) {
    error make --unspanned { msg: $"Content root not found: ($abs_content)" }
  }

  # Make sure output root exists (mkdir makes parents by default).
  mkdir $abs_output

  # Find all Markdown files under content-root, skipping Zola _index.md files.
  # Using glob gives us full paths we can transform reliably.
  let files = (
    glob $"($abs_content)/**/*.md" --no-dir --follow-symlinks
    | where { |p| ($p | path basename) != "_index.md" }
  )

  # Process each file: compute relative path, change extension to .txt,
  # optionally strip front matter, and write to output tree.
  let struct_files = (
    $files | each { |file|
      let rel      = ($file | path relative-to $abs_content)
      let parsed   = ($rel | path parse)
            # Read as bytes, decode to UTF-8 string.
      let raw = (open --raw $file | decode utf-8)
      let extract = ($raw | extract-front-matter)
      [
        yaml
        toml
      ] | each { |ext|
        let struct_file_name  = ($parsed | update extension $ext | path join)
        let struct_file_path  = ($abs_output | path join $struct_file_name)

        mkdir ($struct_file_path | path dirname)

        let content = $extract.content
        let article_tpl = if ($template_article_file | is-not-empty) {
          open $template_article_file
        } else {
          $template_article | from nuon
        }
        let article = (
          $article_tpl
          | update metadata $extract.meta
          | update metadata { |record|
            $record.metadata | update date { |metadata| $metadata.date | format date '%Y%m%dT%H%M%S%Z' }
          }
          | update content $content
        )

        $article
        | save --force $struct_file_path

        match $ext {
          yaml => {
            textman remember-tag-ws $struct_file_path $output_whitespace
            textman restore-tag-ws $struct_file_path $output_whitespace
          }
          _ => {
            open --raw $struct_file_path | lines | textman save-encoded $struct_file_path
          }
        }

        # Clean temporary support file
        rm --force $output_whitespace

        # Return the path relative to output root for index.html listing.
        $struct_file_name
      }
    } | flatten
  )

  # Deploy indexes for structured content artefacts.
  let index_html_yaml = (
    $struct_files
    | sort
    | each { |rel|
      $'((open config.toml | get base_url) | path join ("raw" | path join $rel))'
    }
  )
  let index_html = {
    urls: {
      yaml: $index_html_yaml
    }
  }

  print $"1: ($index_html | get urls | get yaml)"

  [
    yaml
    toml
  ] | each { |ext|
    $index_html | save --force ($abs_output | path join $"index.($ext)")
  }

  # Make plain Markdown Article available
  cp --verbose --force --update ...$files $output_root

  print $"Exported ($struct_files | length) structured & plain Markdown ($files | length) files into directory '($abs_output)'."
}
