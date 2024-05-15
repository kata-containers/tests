//
// Copyright (c) 2023 Maxwell Wendlandt, Christopher Robinson
//
// SPDX-License-Identifier: Apache-2.0
//
use comrak::arena_tree::Node;
use comrak::{
    nodes::{Ast, NodeValue}
};
use std::collections::HashSet;

use std::cell::RefCell;
use std::cmp::Ord;
use std::cmp::Ordering;

#[derive(Debug, PartialEq, Eq, Clone)]
pub struct HeadingInfo {
    pub level: u32,
    pub id: String,
    pub text: String,
    pub line: usize,
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
pub fn find_heading_ids<'a>(node: &'a Node<'a, RefCell<Ast>>, heading_ids: &mut HashSet<String>) {
    match &node.data.borrow().value {
        NodeValue::Heading(_heading) => {
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
