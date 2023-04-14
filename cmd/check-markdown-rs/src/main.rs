use comrak::arena_tree::Node;
use comrak::{
    nodes::{Ast, NodeValue},
    parse_document, Arena, ComrakOptions,
};
use std::cell::RefCell;
use std::env;
use std::fs;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let arena = Arena::new();
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: {} <input_file>", args[0]);
        std::process::exit(1);
    }

    let input_file_path = env::current_dir()?.join("src").join(args[1].clone());
    let input = fs::read_to_string(input_file_path)?;
    let root = parse_document(&arena, &input, &ComrakOptions::default());
    print_nodes(&root, &arena, 0);

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
        NodeValue::Text(text) => println!("{}Text: {}", indent, String::from_utf8_lossy(text.as_bytes())),
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
