use comrak::arena_tree::Node;
use comrak::{
    nodes::{Ast, NodeValue},
    parse_document, Arena, ComrakOptions,
};
use std::cell::RefCell;
use std::collections::HashMap;
use std::collections::HashSet;
use std::env;
use std::fs;
use url::Url;

// Main function
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let arena = Arena::new();
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: {} <input_file>", args[0]);
    }

    let input_file_path = env::current_dir()?.join(args[1].clone());
    let input = fs::read_to_string(input_file_path)?;
    let root = parse_document(&arena, &input, &ComrakOptions::default());

    let toc = generate_toc(&root, &arena);

    let link_validation_result = validate_links(&root);

    let structure_validation_result = validate_document_structure(&root);

    let document_statistics = print_document_statistics(&root);

    // Call the generate_output function
    let document_statistics = print_document_statistics(&root);
    generate_output(
        &toc,
        &link_validation_result,
        &structure_validation_result,
        &document_statistics,
    );

    Ok(())
}

// Recursive function to print the nodes of the AST
fn print_nodes<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    arena: &'a Arena<Node<'a, RefCell<Ast>>>,
    level: usize,
) {
    // Create an indent string based on the current recursion level
    let indent = "  ".repeat(level);
    // Match the node value to handle different node types
    match &node.data.borrow().value {
        // If the node is a Heading node, print its level and text
        NodeValue::Heading(heading) => println!(
            "{}Header (level {}): {}",
            indent,
            heading.level,
            get_node_text(&node)
        ),
        // If the node is a Text node, print its content
        NodeValue::Text(text) => println!(
            "{}Text: {}",
            indent,
            String::from_utf8_lossy(text.as_bytes())
        ),
        // If the node is a Link node, print its title and URL
        NodeValue::Link(link) => println!(
            "{}Link: [{}]({})",
            indent,
            String::from_utf8_lossy(link.title.as_bytes()),
            String::from_utf8_lossy(link.url.as_bytes())
        ),
        // For other node types, print the debug output
        _ => println!("{}{:?}", indent, node.data.borrow().value),
    }
    // Iterate through the children of the current node and recursively print them
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

// Function to validate the structure of the document
fn validate_document_structure<'a>(root: &'a Node<'a, RefCell<Ast>>) -> Result<(), String> {
    let mut last_seen_level = 0;
    let mut h1_count = 0;

    let mut heading_nodes = Vec::new();
    find_heading_nodes(root, &mut heading_nodes);

    for node in heading_nodes {
        match &node.data.borrow().value {
            NodeValue::Heading(heading) => {
                let level = heading.level;

                if level == 1 {
                    h1_count += 1;
                    if h1_count > 1 {
                        return Err(String::from("More than one H1 heading found."));
                    }
                }

                if level > last_seen_level + 1 {
                    return Err(String::from("Invalid heading level order."));
                }

                last_seen_level = level;
            }
            _ => {}
        }
    }

    Ok(())
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
fn generate_toc<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    arena: &'a Arena<Node<'a, RefCell<Ast>>>,
) -> String {
    let mut toc = String::new();
    generate_toc_recursive(node, arena, &mut toc, 0);
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
fn validate_links<'a>(root: &'a Node<'a, RefCell<Ast>>) -> Result<(), Vec<String>> {
    let mut heading_ids = HashSet::new();
    find_heading_ids(root, &mut heading_ids);

    let mut link_nodes = Vec::new();
    find_link_nodes(root, &mut link_nodes);

    let mut errors = Vec::new();

    for node in link_nodes {
        match &node.data.borrow().value {
            NodeValue::Link(link) => {
                let link_url = String::from_utf8_lossy(link.url.as_bytes()).into_owned();

                if link_url.starts_with('#') {
                    // Internal link
                    if !heading_ids.contains(&link_url[1..]) {
                        errors.push(format!(
                            "Internal link '{}' points to non-existing heading.",
                            link_url
                        ));
                    }
                } else {
                    // External link
                    if Url::parse(&link_url).is_err() {
                        errors.push(format!(
                            "External link '{}' has an invalid URL format.",
                            link_url
                        ));
                    }
                }
            }
            _ => {}
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

// Recursive function to find all heading nodes in the AST
fn find_heading_ids<'a>(node: &'a Node<'a, RefCell<Ast>>, heading_ids: &mut HashSet<String>) {
    match &node.data.borrow().value {
        NodeValue::Heading(heading) => {
            // Use one of the available fields for NodeHeading
            let level = heading.level;
            // Do something with level...
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

fn generate_output(
    toc: &str,
    link_validation_result: &Result<(), Vec<String>>,
    structure_validation_result: &Result<(), String>,
    document_statistics: &HashMap<&str, usize>,
) {
    println!("Final Output:");
    println!("\nDocument Structure Validation:");
    match structure_validation_result {
        Ok(_) => println!("  The document structure is valid."),
        Err(err) => eprintln!("  ERROR: {}", err),
    }

    println!("\nTable of Contents:");
    println!("{}", toc);

    println!("\nLink Validation:");
    match link_validation_result {
        Ok(_) => println!("  All links are valid."),
        Err(errors) => {
            println!("  Found {} invalid links:", errors.len());
            for error in errors {
                eprintln!("  ERROR: {}", error);
            }
        }
    }

    println!("\nDocument Statistics:");
    for (stat, count) in document_statistics {
        println!("  {}: {}", stat, count);
    }
}