use comrak::arena_tree::Node;
use comrak::{
    nodes::{Ast, NodeValue},
    parse_document, Arena, ComrakOptions,
};
use std::cell::RefCell;
use std::env;
use std::fs;

fn validate_document_structure<'a>(root: &'a Node<'a, RefCell<Ast>>) -> Result<(), String> {
    let mut found_level_2 = false;

    for node in root.children() {
        match &node.data.borrow().value {
            NodeValue::Heading(heading) => {
                if heading.level == 1 && found_level_2 {
                    return Err("Level 1 heading found after a level 2 heading.".to_string());
                }
                if heading.level == 2 {
                    found_level_2 = true;
                }
            }
            _ => (),
        }
    }

    Ok(())
} 