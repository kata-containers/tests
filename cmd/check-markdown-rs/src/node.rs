use std::collections::HashSet;                                                                                              
use comrak::arena_tree::Node;                                                                                               
use comrak::{                                                                                                               
    nodes::{Ast, NodeValue},                                                                                                
    Arena                                                                                   
};                                                                                                                          

use std::cell::RefCell;
use std::cmp::Ord;
use std::cmp::Ordering;

#[derive(Debug, PartialEq, Eq, Clone)]
pub struct HeadingInfo {                                                                                                                                           
    pub level: u32,                                                                                                                                                
    pub id: String,                                                                                                                                                
    pub text: String,                                                                                                                                              
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

pub fn handle_heading_node(indent: &str, level: u32, text: String) {
    println!("{}Header (level {}): {}", indent, level, text);
}

pub fn handle_text_node(indent: &str, text: String) {
    println!("{}Text: {}", indent, text);
}

pub fn handle_link_node(indent: &str, title: String, url: String) {
    println!("{}Link: [{}]({})", indent, title, url);
}

pub fn print_nodes<'a>(
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
        }
        NodeValue::Text(text) => {
            let content = String::from_utf8_lossy(text.as_bytes()).to_string();
            handle_text_node(&indent, content);
        }
        NodeValue::Link(link) => {
            let title = String::from_utf8_lossy(link.title.as_bytes()).to_string();
            // Replace the deprecated into_string method with Into<String>
            let url = link.url.clone().into();
            handle_link_node(&indent, title, url);
        }
        _ => println!("{}{:?}", indent, node.data.borrow().value),
    }
    for child in node.children() {
        print_nodes(&child, arena, level + 1);
    }
}

pub fn get_node_text<'a>(node: &'a Node<'a, RefCell<Ast>>) -> String {
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

// Recursive function to find all heading nodes in the AST
pub fn find_heading_nodes<'a>(
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

// Recursive function to find all heading nodes in the AST
pub fn find_heading_ids<'a>(node: &'a Node<'a, RefCell<Ast>>, heading_ids: &mut HashSet<String>) {
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
pub fn find_link_nodes<'a>(
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
