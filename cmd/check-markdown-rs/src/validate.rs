//
// Copyright (c) 2023 Maxwell Wendlandt, Christopher Robinson
//
// SPDX-License-Identifier: Apache-2.0
//
use crate::node::{find_heading_ids, find_link_nodes}; 
use crate::toc::collect_heading_info;

use std::collections::HashSet;                                                                                              
use comrak::arena_tree::Node;                                                                                               
use comrak::{                                                                                                               
    nodes::{Ast, NodeValue}                                                                                   
};                                                                                                                          
use comrak::nodes::LineColumn;
use std::cell::RefCell;
use std::collections::HashMap;
use std::env;
use std::fs;
use url::Url;
use async_std::task;
use std::path::{Path, PathBuf};

// Struct to represent the error with file path, heading, and error message
pub struct StructureError {                                                                                                                                        
    pub file: PathBuf,                                                                                                                                             
    pub heading: Option<String>,                                                                                                                                   
    pub error: String,                                                                                                                                             
}      

// Function to validate the structure of the document
pub fn validate_document_structure<'a>(
    root: &'a Node<'a, RefCell<Ast>>,
    input_file: &PathBuf,
) -> Result<(), Vec<StructureError>> {
    let mut last_seen_level = 0;
    let mut h1_count = 0;

    let heading_nodes = collect_heading_info(root);

    // Add a HashMap to track heading texts at each level
    let mut headings_at_level: HashMap<u32, HashSet<String>> = HashMap::new();
    let mut errors = Vec::new();

    for heading_info in &heading_nodes {
        let level = heading_info.level;

        if level == 1 {
            h1_count += 1;
            if h1_count > 1 {
                errors.push(StructureError {
                    file: input_file.clone(),
                    heading: Some(heading_info.text.clone()),
                    error: String::from("More than one H1 heading found."),
                });
            }
        }

        if level > last_seen_level + 1 {
            errors.push(StructureError {
                file: input_file.clone(),
                heading: Some(heading_info.text.clone()),
                error: String::from("Invalid heading level order."),
            });
        }

        // Check for repeated headings at the same level
        let heading_texts = headings_at_level.entry(level).or_insert_with(HashSet::new);
        if !heading_texts.insert(heading_info.text.clone()) {
            errors.push(StructureError {
                file: input_file.clone(),
                heading: Some(heading_info.text.clone()),
                error: format!(
                    "Repeated heading '{}' at level {}.",
                    heading_info.text, level
                ),
            });
        }

        last_seen_level = level;
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

// Function to gather and print heading information
pub fn line_column(input: &str, line_col: LineColumn) -> (usize, usize) {
    let mut line = 1;
    let mut column = 1;

    for (index, ch) in input.char_indices() {
        let current_line_col = LineColumn { line, column };

        if line_col == current_line_col {
            break;
        }
        if ch == '\n' {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    (line, column)
}

// validate links method
pub fn validate_links<'a>(
    root: &'a Node<'a, RefCell<Ast>>,
    input: &str,
) -> Result<(), Vec<String>> {
    let mut heading_ids = HashSet::new();
    find_heading_ids(root, &mut heading_ids);

    let mut link_nodes = Vec::new();
    find_link_nodes(root, &mut link_nodes);

    let mut errors = Vec::new();
    let mut external_urls = Vec::new();

    for node in link_nodes {
        let start_offset = node.data.borrow().sourcepos.start;

        // Get the line and column numbers for the byte offset in the input string
        let (line, column) = line_column(input, start_offset);

        match &node.data.borrow().value {
            NodeValue::Link(link) => {
                let link_url = String::from_utf8_lossy(link.url.as_bytes()).into_owned();
                let resolved_url = resolve_link_url(link_url.clone(), root);

                if resolved_url.starts_with('#') {
                    // Internal link
                    let heading_id = &resolved_url[1..];
                    if !heading_ids.contains(heading_id) {
                        errors.push(format!(
                            "Internal link '{}' points to non-existing heading at line {}, column {}.",
                            link_url,
                            line + 1,
                            column + 1
                        ));
                    }
                } else {
                    // External link
                    if is_directory_link(&resolved_url) {
                        continue; // Skip validation for directory links
                    } else if Url::parse(&resolved_url).is_err() {
                        errors.push(format!(
                            "External link '{}' has an invalid URL format at line {}, column {}.",
                            link_url,
                            line + 1,
                            column + 1
                        ));
                    } else {
                        external_urls.push(resolved_url);
                    }
                }
            }
            _ => {}
        }
    }

    // Validate external URLs
    let external_url_errors = task::block_on(validate_external_links(external_urls));
    errors.extend(external_url_errors);

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

// Recursive function to find all link nodes in the AST
pub fn is_directory_link(url: &str) -> bool {
    let args: Vec<String> = env::args().collect();
    let readme_path = Path::new(&args[1]);
    let parent_dir = readme_path.parent().expect("Failed to get parent directory");

    // Resolve the link URL against the parent directory
    let absolute_path = parent_dir.join(&Path::new(url.trim_start_matches('/')));

    // Check if the resolved path is a directory
    if let Ok(metadata) = fs::metadata(&absolute_path) {
        metadata.is_dir()
    } else {
        false
    }
}

// Resolve relative URLs to absolute URLs based on the current document's URL
pub fn resolve_link_url(link_url: String, root: &Node<RefCell<Ast>>) -> String {
    let current_url = get_current_document_url(root);
    let current_url = current_url.as_str();

    // Resolve relative URLs to absolute URLs based on the current document's URL
    if link_url.starts_with('.') {
        let resolved_url = Url::parse(current_url)
            .and_then(|base_url| base_url.join(&link_url))
            .map(|url| url.into_string())
            .unwrap_or(link_url);

        // Check if the resolved URL corresponds to a directory
        if is_directory_link(&resolved_url) {
            return format!("{}/", resolved_url); // Modify URL to represent a directory link
        }

        return resolved_url;
    }

    link_url
}

// Get the URL of the current document
pub fn get_current_document_url(root: &Node<RefCell<Ast>>) -> String {
    // Replace `README.md` with the actual URL of the current document
    let base_url = "https://github.com/kata-containers/tests/blob/main/README.md";
    base_url.to_owned()
}

// Function to validate external links
pub async fn validate_external_links(urls: Vec<String>) -> Vec<String> {
    let mut errors = Vec::new();

    for url in urls {
        let response = surf::get(&url).await;

        if response.is_err() {
            errors.push(format!("External link '{}' is not reachable.", url));
        }
    }

    errors
}