//
// Copyright (c) 2023 Maxwell Wendlandt, Christopher Robinson
//
// SPDX-License-Identifier: Apache-2.0
//
use crate::node::{get_node_text};                                                                                             
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

pub fn collect_heading_info<'a>(node: &'a Node<'a, RefCell<Ast>>) -> Vec<HeadingInfo> {
    let mut heading_infos = Vec::new();
    collect_heading_info_recursive(node, &mut heading_infos);
    heading_infos
}

pub fn collect_heading_info_recursive<'a>(
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

pub fn generate_unique_id(text: &str, heading_infos: &[HeadingInfo]) -> String {
    let mut id = text.to_lowercase().replace(" ", "-");
    let mut count = 1;

    while heading_infos.iter().any(|info| info.id == id) {
        id = format!("{}-{}", text.to_lowercase().replace(" ", "-"), count);
        count += 1;
    }

    id
}

pub fn generate_toc(heading_infos: &[HeadingInfo]) -> String {
    let mut toc = String::new();

    for heading_info in heading_infos {
        let indent = "  ".repeat((heading_info.level - 1) as usize);
        toc.push_str(&format!(
            "{}- [{}](#{})\n",
            indent, heading_info.text, heading_info.id
        ));
    }

    toc
}

// Recursive function to generate a table of contents
pub fn generate_toc_recursive<'a>(
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