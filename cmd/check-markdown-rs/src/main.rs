use std::collections::HashSet;                                                                                              
use comrak::arena_tree::Node;                                                                                               
use comrak::{                                                                                                               
    nodes::{Ast, NodeValue},                                                                                                
    parse_document, Arena, ComrakOptions,                                                                                   
};                                                                                                                          
use comrak::nodes::LineColumn;
use std::cell::RefCell;
use std::collections::HashMap;
use std::env;
use std::fs;
use url::Url;
use async_std::task;
use std::path::{Path, PathBuf};
use std::cmp::Ord;
use std::cmp::Ordering;

                                                                                                                            
// Add a custom structure to hold the heading information
#[derive(Debug, PartialEq, Eq, Clone)]
struct HeadingInfo {
    level: u32,
    id: String,
    text: String,
}

// Add implementation for PartialOrd and Ord to sort the HeadingInfo
impl PartialOrd for HeadingInfo {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for HeadingInfo {
    fn cmp(&self, other: &Self) -> Ordering {
        self.level
            .cmp(&other.level)
            .then_with(|| self.text.cmp(&other.text))
    }
}
                                                                                                                            
// Main function
fn main() -> Result<(), Box<dyn std::error::Error>> {  
    let args: Vec<String> = env::args().collect();
    let arena = Arena::new();

    if args.len() < 2 {
        return Err("Usage: <input_file>".into());
    }

    let input_file_path = env::current_dir()?.join(args[1].clone());
    let input = fs::read_to_string(&input_file_path)?;
    let root = parse_document(&arena, &input, &ComrakOptions::default());

    let heading_infos: &[HeadingInfo] = &collect_heading_info(&root);
    let toc = generate_toc(heading_infos);

    let link_validation_result = validate_links(&root, &input);
    let structure_validation_result = validate_document_structure(&root, &input_file_path);

    let document_statistics = print_document_statistics(&root);

    generate_output(
        &input_file_path,
        &toc,
        &link_validation_result,
        &structure_validation_result,
        &document_statistics,
        &heading_infos,
    );
    

    Ok(())
}

fn handle_heading_node(indent: &str, level: u32, text: String) {
    println!("{}Header (level {}): {}", indent, level, text);
}

fn handle_text_node(indent: &str, text: String) {
    println!("{}Text: {}", indent, text);
}

fn handle_link_node(indent: &str, title: String, url: String) {
    println!("{}Link: [{}]({})", indent, title, url);
}

fn print_nodes<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    arena: &'a Arena<Node<'a, RefCell<Ast>>>,
    level: usize,
) {
    let indent = "  ".repeat(level);
    match &node.data.borrow().value {
        NodeValue::Heading(heading) => {
            let text = get_node_text(&node);
            // Convert heading.level from u8 to u32
            handle_heading_node(&indent, heading.level.into(), text);
        },
        NodeValue::Text(text) => {
            let content = String::from_utf8_lossy(text.as_bytes()).to_string();
            handle_text_node(&indent, content);
        },
        NodeValue::Link(link) => {
            let title = String::from_utf8_lossy(link.title.as_bytes()).to_string();
            // Replace the deprecated into_string method with Into<String>
            let url = link.url.clone().into();
            handle_link_node(&indent, title, url);
        },
        _ => println!("{}{:?}", indent, node.data.borrow().value),
    }
    for child in node.children() {
        print_nodes(&child, arena, level + 1);
    }
}

// Function to get the text content of a node
fn get_node_text<'a>(node: &'a Node<'a, RefCell<Ast>>) -> String {
    // Iterate through the children of the node
    node.children()
        // Filter and map each child node to its text content, if it's a Text node
        .filter_map(|child| match &child.data.borrow().value {
            NodeValue::Text(text) => Some(String::from_utf8_lossy(text.as_bytes()).into_owned()),
            _ => None,
        })
        // Collect the text content into a vector of strings
        .collect::<Vec<String>>()
        // Join the strings together to form a single string
        .join("")
}

// Struct to represent the error with file path, heading, and error message
struct StructureError {
    file: PathBuf,
    heading: Option<String>,
    error: String,
}

// Function to validate the structure of the document
fn validate_document_structure<'a>(
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


// Recursive function to find all heading nodes in the AST
fn find_heading_nodes<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    heading_nodes: &mut Vec<&'a Node<'a, RefCell<Ast>>>,
) {
    match &node.data.borrow().value {
        NodeValue::Heading(_) => heading_nodes.push(node),
        _ => {}
    }

    for child in node.children() {
        find_heading_nodes(&child, heading_nodes);
    }
}

// Generate a table of contents based on the headings present in the document
fn generate_toc(heading_infos: &[HeadingInfo]) -> String {
    let mut toc = String::new();

    for heading_info in heading_infos {
        let indent = "  ".repeat((heading_info.level - 1) as usize);
        toc.push_str(&format!(
            "{}- [{}](#{})\n",
            indent,
            heading_info.text,
            heading_info.id
        ));
    }

    toc
}

// Recursive function to generate a table of contents
fn generate_toc_recursive<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    arena: &'a Arena<Node<'a, RefCell<Ast>>>,
    toc: &mut String,
    level: usize,
) {
    match &node.data.borrow().value {
        NodeValue::Heading(heading) => {
            let indent = "  ".repeat(level);
            let text = get_node_text(&node);
            toc.push_str(&format!("{}- [{}](#)\n", indent, text));
        }
        _ => {}
    }
    for child in node.children() {
        generate_toc_recursive(&child, arena, toc, level + 1);
    }
}

// validate links method
fn validate_links<'a>(
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
fn is_directory_link(url: &str) -> bool {
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
fn resolve_link_url(link_url: String, root: &Node<RefCell<Ast>>) -> String {
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
fn get_current_document_url(root: &Node<RefCell<Ast>>) -> String {
    // Replace `README.md` with the actual URL of the current document
    let base_url = "https://github.com/kata-containers/tests/blob/main/README.md";
    base_url.to_owned()
}

// Recursive function to find all heading nodes in the AST
fn find_heading_ids<'a>(node: &'a Node<'a, RefCell<Ast>>, heading_ids: &mut HashSet<String>) {
    match &node.data.borrow().value {
        NodeValue::Heading(heading) => {
            let text = get_node_text(&node);
            let id = text.to_lowercase().replace(" ", "-");
            heading_ids.insert(id);
        }
        _ => {}
    }

    for child in node.children() {
        find_heading_ids(&child, heading_ids);
    }
}

// Recursive function to find all link nodes in the AST
fn find_link_nodes<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    link_nodes: &mut Vec<&'a Node<'a, RefCell<Ast>>>,
) {
    match &node.data.borrow().value {
        NodeValue::Link(_) => link_nodes.push(node),
        _ => {}
    }

    for child in node.children() {
        find_link_nodes(&child, link_nodes);
    }
}

// Function to gather and print document statistics
fn print_document_statistics<'a>(root: &'a Node<'a, RefCell<Ast>>) -> HashMap<&'a str, usize> {
    let mut statistics: HashMap<&str, usize> = HashMap::new();
    gather_document_statistics(root, &mut statistics);

    statistics
}

// Recursive function to gather document statistics
fn gather_document_statistics<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    statistics: &mut HashMap<&'a str, usize>,
) {
    match &node.data.borrow().value {
        NodeValue::Heading(_) => {
            *statistics.entry("headings").or_insert(0) += 1;
        }
        NodeValue::Text(text) => {
            let word_count = String::from_utf8_lossy(text.as_bytes())
                .split_whitespace()
                .count();
            *statistics.entry("words").or_insert(0) += word_count;
        }
        NodeValue::Link(_) => {
            *statistics.entry("links").or_insert(0) += 1;
        }
        _ => {}
    }

    for child in node.children() {
        gather_document_statistics(&child, statistics);
    }
}

// Function to gather and print heading information
fn line_column(input: &str, line_col: LineColumn) -> (usize, usize) {
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

// Function to generate the output
fn generate_output(
    input_file: &PathBuf,
    toc: &str,
    link_validation_result: &Result<(), Vec<String>>,
    structure_validation_result: &Result<(), Vec<StructureError>>,
    document_statistics: &HashMap<&str, usize>,
    heading_infos: &[HeadingInfo],
) {
    println!("Final Output for file {:?}:", input_file);

    println!("\nDocument Structure Validation:");
    match structure_validation_result {
        Ok(_) => println!("  The document structure is valid."),
        Err(errors) => {
            println!("  Found {} file(s) with structure errors:", errors.len());
            for error in errors {
                if let Some(heading) = &error.heading {
                    eprintln!(
                        "  File: {:?}, Error: {}",
                        error.file, error.error
                    );
                } else {
                    eprintln!("  File: {:?}, Error: {}", error.file, error.error);
                }
            }
        }
    }

    println!("    Level 1 Headings:");
    for heading_info in heading_infos {
        if heading_info.level == 1 {
            println!("    - [{}](#{})", heading_info.text, heading_info.id,);
        }
    }

    println!("\nTable of Contents:");
    println!("{}", toc);

    println!("\nLink Validation:");
    match link_validation_result {
        Ok(_) => println!("  All links are valid."),
        Err(errors) => {
            println!("  Found {} file(s) with link validation errors:", errors.len());
            for error in errors {
                eprintln!("  Error: {}", error);
            }
        }
    }

    println!("\nDocument Statistics:");
    for (stat, count) in document_statistics {
        println!("  {}: {}", stat, count);
    }
}

// Function to validate external links
async fn validate_external_links(urls: Vec<String>) -> Vec<String> {
    let mut errors = Vec::new();

    for url in urls {
        let response = surf::get(&url).await;

        if response.is_err() {
            errors.push(format!("External link '{}' is not reachable.", url));
        }
    }

    errors
}

// Function to generate the table of contents
fn collect_heading_info<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
) -> Vec<HeadingInfo> {
    let mut heading_infos = Vec::new();
    collect_heading_info_recursive(node, &mut heading_infos);
    heading_infos
}

// Add a modified version of the 'generate_toc_recursive' function that collects heading information
fn collect_heading_info_recursive<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    heading_infos: &mut Vec<HeadingInfo>,
) {
    match &node.data.borrow().value {
        NodeValue::Heading(heading) => {
            let text = get_node_text(&node);
            let id = generate_unique_id(&text, heading_infos);
            let heading_info = HeadingInfo {
                level: heading.level as u32,
                id,
                text,
            };
            heading_infos.push(heading_info);
        }
        _ => {}
    }
    for child in node.children() {
        collect_heading_info_recursive(&child, heading_infos);
    }
}

// Function to generate a unique id for a heading
fn generate_unique_id(text: &str, heading_infos: &[HeadingInfo]) -> String {
    let mut id = text.to_lowercase().replace(" ", "-");
    let mut count = 1;

    while heading_infos.iter().any(|info| info.id == id) {
        id = format!("{}-{}", text.to_lowercase().replace(" ", "-"), count);
        count += 1;
    }

    id
}